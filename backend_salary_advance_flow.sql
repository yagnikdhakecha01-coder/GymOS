-- ====================================================
-- GYMOS - FULL BACKEND ADVANCE & SALARY FLOW INTEGRATION
-- ====================================================
-- 1. Automatic Expense Entry when Advance Salary is Given/Approved
-- 2. Accumulates ALL multiple advances (e.g. 2000 + 3000 = 5000)
-- 3. Automatic calculation in Salary Draft Trigger
-- ====================================================

-- 1. Trigger Function to insert Finance Expense when Advance Salary is Approved/Given
CREATE OR REPLACE FUNCTION public.fn_on_advance_salary_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status) THEN
        -- Fetch Staff Name
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Insert Expense record in Finance Transactions automatically
        INSERT INTO public.transactions (
            gym_id, 
            type, 
            title, 
            amount, 
            category, 
            date, 
            payment_mode, 
            reference_id, 
            notes
        )
        VALUES (
            NEW.gym_id,
            'Expense',
            'Salary Advance - ' || COALESCE(s_name, 'Staff'),
            NEW.amount,
            'Salaries',
            NEW.requested_date::TEXT,
            'Cash',
            NEW.staff_id::TEXT,
            NEW.reason
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to salary_advances table
DROP TRIGGER IF EXISTS trg_on_advance_salary_created ON public.salary_advances;
CREATE TRIGGER trg_on_advance_salary_created
AFTER INSERT OR UPDATE ON public.salary_advances
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_salary_created();


-- 2. Update Salary Draft Live Calculations Trigger (Base + Commission + Adjustments - Total Advances = Net Pending Salary)
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- 1. Calculate pending commission amount for staff
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    -- 2. Accumulate ALL advances given to staff (e.g. 2000 + 3000 = 5000)
    SELECT COALESCE(SUM(amount), 0.0) INTO adv_total 
    FROM public.salary_advances 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- 3. Calculate manual additions (Adjustments section)
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;

    -- 4. Calculate manual deductions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    -- 5. Set Draft values automatically in Backend
    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    -- Net Pending Payable Salary = (Base + Commission + Additions - Deductions) - Total Accumulative Advance
    NEW.net_salary := ((NEW.base_salary + comm_total + adj_add) - adj_ded) - adv_total;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach Trigger to salary_drafts table
DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;

CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();
