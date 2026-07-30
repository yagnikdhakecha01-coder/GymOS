-- ====================================================================
-- GYMOS - DATABASE FIX: REBUILD SALARY DRAFT TRIGGER & REMOVE OBSOLETE TRIGGERS
-- Run this in your Supabase SQL Editor to fully clean up references
-- to the deleted "salary_advances" table and solve the payment error!
-- ====================================================================

-- 1. Drop the obsolete trigger and function that references public.salary_advances
DROP TRIGGER IF EXISTS trg_on_salary_draft_paid ON public.salary_drafts;
DROP FUNCTION IF EXISTS public.fn_on_salary_draft_paid();

-- 2. Drop the old trigger function for advance salary creation if it exists
DROP FUNCTION IF EXISTS public.fn_on_advance_salary_created();

-- 3. Rebuild the main totals calculation trigger function for salary_drafts
-- Added lock check: If the draft is already Paid or is transitioning to Paid, we do NOT recalculate totals to prevent them from resetting to zero.
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- If draft is already Paid, or is being updated to Paid, LOCK the calculated totals and do not recalculate.
    IF NEW.status = 'Paid'::public.draft_status OR (TG_OP = 'UPDATE' AND OLD.status = 'Paid'::public.draft_status) THEN
        RETURN NEW;
    END IF;

    -- Calculate pending commission amount for staff
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    -- Calculate active advance salary amount (using remaining_amount from the new ledger table)
    SELECT COALESCE(SUM(remaining_amount), 0.0) INTO adv_total 
    FROM public.salary_advance_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- Calculate manual additions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;

    -- Calculate manual deductions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    -- Set Draft values automatically in Backend
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


-- 4. Rebuild vw_pending_salary_list view using salary_advance_ledger
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
        SELECT SUM(sa.remaining_amount) 
        FROM public.salary_advance_ledger sa 
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
            SELECT SUM(sa.remaining_amount) 
            FROM public.salary_advance_ledger sa 
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


-- 5. OPTIONAL: Fix existing paid draft for July 2026 if it was set to base salary only
-- Run this if your existing history item shows incorrect values.
-- UPDATE public.salary_drafts
-- SET commission_amount = 3150.00,
--     advance_deduction = 550.00,
--     net_salary = 14600.00
-- WHERE salary_month = 'July 2026' AND status = 'Paid';
