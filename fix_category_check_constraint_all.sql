-- ====================================================
-- GYMOS - FIX FINANCE TRANSACTIONS CATEGORY CHECK CONSTRAINT
-- ====================================================
-- Run this in Supabase SQL Editor to permanently allow all
-- custom categories in finance_transactions table.

-- 1. Drop existing restrictive category check constraint
ALTER TABLE public.finance_transactions 
  DROP CONSTRAINT IF EXISTS finance_transactions_category_check;

-- 2. Add flexible category check constraint matching all app options
ALTER TABLE public.finance_transactions 
  ADD CONSTRAINT finance_transactions_category_check 
  CHECK (category IN (
    'Membership', 'Membership Fee', 'Personal Training', 'Protein Sale', 'Supplements', 
    'Locker Rent', 'Locker Fee', 'Merchandise', 'Other Income', 'Income',
    'Salary', 'Salaries', 'Rent', 'Utilities', 'Maintenance', 'Equipment', 'Other Expense', 'Expense', 'Other'
  ));

-- 3. Verify constraint is updated
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname = 'finance_transactions_category_check';
