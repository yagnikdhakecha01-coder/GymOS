-- ====================================================
-- GYMOS - FIX FINANCE TRANSACTIONS TRIGGER (TARGET RIGHT TABLE)
-- ====================================================
-- Run this in your Supabase SQL Editor to solve:
-- "column 'notes' of relation 'transactions' does not exist"

-- 1. Ensure `finance_transactions` table exists
CREATE TABLE IF NOT EXISTS public.finance_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    type TEXT NOT NULL CHECK (type IN ('Revenue', 'Expense')),
    category TEXT NOT NULL,
    payment_method TEXT DEFAULT 'Cash' NOT NULL,
    transaction_date TIMESTAMPTZ DEFAULT now() NOT NULL,
    reference_id TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Grant privileges
GRANT ALL ON TABLE public.finance_transactions TO anon, authenticated, service_role;

-- 2. Trigger Function inserting into `finance_transactions` (Correct table with notes column)
CREATE OR REPLACE FUNCTION public.fn_on_advance_salary_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status) THEN
        -- Fetch Staff Name
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Insert Expense record into `finance_transactions`
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

-- Re-attach trigger to salary_advances table
DROP TRIGGER IF EXISTS trg_on_advance_salary_created ON public.salary_advances;
CREATE TRIGGER trg_on_advance_salary_created
AFTER INSERT OR UPDATE ON public.salary_advances
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_salary_created();
