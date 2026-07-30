-- ====================================================
-- GYMOS - FINANCE & ACCOUNTING ENGINE MIGRATION
-- ====================================================

-- 1. Create Transaction Ledger Table (Double-entry / Auditable)
CREATE TABLE IF NOT EXISTS public.finance_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    type TEXT NOT NULL CHECK (type IN ('Revenue', 'Expense')),
    category TEXT NOT NULL CHECK (category IN ('Membership', 'Salary', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other')),
    payment_method TEXT NOT NULL CHECK (payment_method IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other')),
    transaction_date TIMESTAMPTZ DEFAULT now() NOT NULL,
    expense_date DATE DEFAULT CURRENT_DATE,
    revenue_date DATE DEFAULT CURRENT_DATE,
    entry_date DATE DEFAULT CURRENT_DATE,
    reference_id TEXT, -- e.g. member_id, staff_id, or custom invoice reference
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing for fast search and report generation
CREATE INDEX IF NOT EXISTS idx_finance_tx_gym_date ON public.finance_transactions(gym_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_finance_tx_type ON public.finance_transactions(gym_id, type);

-- 2. Modify Members Table to support normal payment summary
ALTER TABLE public.members 
  ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
  ADD COLUMN IF NOT EXISTS total_received_amount NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
  ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'Pending' CHECK (payment_status IN ('Pending', 'Partial', 'Paid', 'Cancelled'));

-- 3. Modify Salaries/Staff table to support Month/Year specific accruals
CREATE TABLE IF NOT EXISTS public.salary_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    salary_month INT NOT NULL CHECK (salary_month BETWEEN 1 AND 12),
    salary_year INT NOT NULL CHECK (salary_year > 2000),
    payment_type TEXT NOT NULL CHECK (payment_type IN ('Advance', 'Final')),
    payment_date TIMESTAMPTZ DEFAULT now() NOT NULL,
    payment_method TEXT NOT NULL,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_salary_payments_staff_month ON public.salary_payments(staff_id, salary_year, salary_month);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.finance_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_payments ENABLE ROW LEVEL SECURITY;

-- 5. Define RLS Policies
DROP POLICY IF EXISTS gym_isolation_policy_tx ON public.finance_transactions;
CREATE POLICY gym_isolation_policy_tx ON public.finance_transactions
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS gym_isolation_policy_salaries ON public.salary_payments;
CREATE POLICY gym_isolation_policy_salaries ON public.salary_payments
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- 6. GRANT SCHEMA PRIVILEGES
GRANT ALL ON TABLE public.finance_transactions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.salary_payments TO anon, authenticated, service_role;
