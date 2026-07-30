-- ====================================================
-- GYMOS - FIX CHECK CONSTRAINT & OLD TRIGGERS ON SUPABASE
-- ====================================================
-- Run this ONCE in Supabase SQL Editor to completely solve
-- "violates check constraint finance_transactions_category_check"

-- 1. Drop old triggers that were inserting 'Salaries'
DROP TRIGGER IF EXISTS trg_on_advance_salary_created ON public.salary_advances;
DROP FUNCTION IF EXISTS public.fn_on_advance_salary_created() CASCADE;

-- 2. Drop old restrict constraint on finance_transactions if present
ALTER TABLE public.finance_transactions 
  DROP CONSTRAINT IF EXISTS finance_transactions_category_check;

-- 3. Add flexible category check constraint (allows 'Salary', 'Salaries', 'Membership', etc.)
ALTER TABLE public.finance_transactions 
  ADD CONSTRAINT finance_transactions_category_check 
  CHECK (category IN ('Membership', 'Salary', 'Salaries', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other'));

-- 4. Create clean Database Trigger using 'Salary'
CREATE OR REPLACE FUNCTION public.fn_on_advance_salary_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status) THEN
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

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
            'Salary',
            NEW.amount,
            'Cash',
            NEW.staff_id::TEXT,
            'Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || NEW.reason || ')', '')
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_advance_salary_created
AFTER INSERT OR UPDATE ON public.salary_advances
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_salary_created();
