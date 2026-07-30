-- ====================================================
-- GYMOS - ADD EXPENSE_DATE AND ENTRY_DATE TO FINANCE_TRANSACTIONS
-- ====================================================

-- 1. Add columns to finance_transactions
ALTER TABLE public.finance_transactions 
ADD COLUMN IF NOT EXISTS expense_date DATE DEFAULT CURRENT_DATE,
ADD COLUMN IF NOT EXISTS entry_date DATE DEFAULT CURRENT_DATE;

-- 2. Populate columns for existing transactions
UPDATE public.finance_transactions 
SET expense_date = COALESCE(transaction_date::date, CURRENT_DATE) 
WHERE expense_date IS NULL;

UPDATE public.finance_transactions 
SET entry_date = COALESCE(created_at::date, CURRENT_DATE) 
WHERE entry_date IS NULL;

-- 3. Re-grant privileges on table to keep security clean
GRANT ALL ON TABLE public.finance_transactions TO anon, authenticated, service_role;
