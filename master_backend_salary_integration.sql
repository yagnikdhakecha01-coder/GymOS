-- ====================================================================
-- GYMOS: COMPLETE BACKEND SQL INTEGRATION FOR SALARY & ADVANCES
-- ====================================================================
-- Copy and paste this script in your Supabase SQL Editor and click 'Run'.
-- It sets up database columns, tables, triggers, and views.

-- 1. Ensure columns and types exist safely
ALTER TYPE public.advance_status ADD VALUE IF NOT EXISTS 'Given';

-- 2. Clean and replace Check Constraints safely on finance_transactions
ALTER TABLE public.finance_transactions 
  DROP CONSTRAINT IF EXISTS finance_transactions_category_check;

ALTER TABLE public.finance_transactions 
  ADD CONSTRAINT finance_transactions_category_check 
  CHECK (category IN ('Membership', 'Salary', 'Salaries', 'Salary Advance', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other'));

-- 3. Automatic Expense Logger on Advance Salary Approval / Handout
CREATE OR REPLACE FUNCTION public.fn_on_advance_salary_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    -- When advance is approved or directly given by owner
    IF NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status) THEN
        -- Fetch Staff name
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Record Expense in Finance Ledger dynamically
        INSERT INTO public.finance_transactions (
            gym_id,
            type,
            category,
            amount,
            payment_method,
            reference_id,
            notes
        )
        VALUES (
            NEW.gym_id,
            'Expense',
            'Salary Advance',
            NEW.amount,
            'Cash',
            NEW.staff_id::TEXT,
            'Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || NEW.reason || ')', '')
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger
DROP TRIGGER IF EXISTS trg_on_advance_salary_created ON public.salary_advances;
CREATE TRIGGER trg_on_advance_salary_created
AFTER INSERT OR UPDATE ON public.salary_advances
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_salary_created();


-- 4. Automatically Mark Advances as 'Recovered' on Paying Salary Draft
-- This prevents the same advance from being deducted twice!
CREATE OR REPLACE FUNCTION public.fn_on_salary_draft_paid()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'Paid'::public.draft_status AND OLD.status <> 'Paid'::public.draft_status THEN
        -- Update all Approved / Given / Pending advances of this staff to Recovered
        UPDATE public.salary_advances
        SET status = 'Recovered'::public.advance_status
        WHERE staff_id = NEW.staff_id 
          AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_salary_draft_paid ON public.salary_drafts;
CREATE TRIGGER trg_on_salary_draft_paid
AFTER UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_on_salary_draft_paid();


-- 5. Updated Live Calculations Trigger inside public.salary_drafts
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- 5.1 Calculate pending commission
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    -- 5.2 Calculate only Active / Unrecovered advances
    SELECT COALESCE(SUM(amount), 0.0) INTO adv_total 
    FROM public.salary_advances 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- 5.3 Calculate manual additions / deductions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    -- Assign computed values
    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    -- Formula: (Base + Commission + Additions - Deductions) - Unrecovered Advances
    NEW.net_salary := ((NEW.base_salary + comm_total + adj_add) - adj_ded) - adv_total;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;
CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();


-- 6. Dynamic View for Dashboard Pending Salaries List
CREATE OR REPLACE VIEW public.vw_pending_salary_list AS
SELECT 
    s.id AS staff_id,
    s.gym_id,
    s.name,
    s.role,
    s.avatar,
    s.salary AS base_salary,
    COALESCE((
        SELECT SUM(cl.amount) 
        FROM public.commission_ledger cl 
        WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
    ), 0.0) AS pending_commission,
    COALESCE((
        SELECT SUM(sa.amount) 
        FROM public.salary_advances sa 
        WHERE sa.staff_id = s.id 
          AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
    ), 0.0) AS total_advance,
    -- Pending Net = (Salary + Commission) - Advances Taken
    GREATEST(
        (s.salary + COALESCE((
            SELECT SUM(cl.amount) 
            FROM public.commission_ledger cl 
            WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
        ), 0.0)) - COALESCE((
            SELECT SUM(sa.amount) 
            FROM public.salary_advances sa 
            WHERE sa.staff_id = s.id 
              AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
        ), 0.0), 
        0.0
    ) AS net_pending_salary
FROM public.staff s
WHERE NOT EXISTS (
    SELECT 1 FROM public.salary_drafts sd 
    WHERE sd.staff_id = s.id 
      AND sd.salary_month = to_char(now(), 'Month YYYY')
      AND sd.status = 'Paid'::public.draft_status
);

GRANT SELECT ON public.vw_pending_salary_list TO anon, authenticated, service_role;
