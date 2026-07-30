-- ====================================================
-- GYMOS - BACKEND AUTOMATIC SALARY ADVANCE DEDUCTION TRIGGER
-- ====================================================
-- Run this in your Supabase SQL Editor to calculate and deduct
-- Advance Salary automatically inside the Database backend!

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

    -- 2. Calculate advance salary amount (Approved, Given, or Pending status)
    SELECT COALESCE(SUM(amount), 0.0) INTO adv_total 
    FROM public.salary_advances 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- 3. Calculate manual additions
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
    
    -- Net Salary = (Base Salary + Commission + Additions) - (Advance Deduction + Manual Deductions)
    NEW.net_salary := (NEW.base_salary + comm_total + adj_add) - (adv_total + adj_ded);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach Trigger to salary_drafts table
DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;

CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();
