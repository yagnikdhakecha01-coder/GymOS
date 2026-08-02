-- ====================================================
-- GYMOS - TRIAL MEMBER MODULE MIGRATION
-- ====================================================

-- 1. Create Trial Members Table
CREATE TABLE IF NOT EXISTS public.trial_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    avatar TEXT,
    trial_type TEXT NOT NULL CHECK (trial_type IN ('Free', 'Paid')),
    trial_days INT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Expired', 'Converted')),
    fee NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    discount NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    received_amount NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    payment_method TEXT,
    payment_date DATE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing for fast search
CREATE INDEX IF NOT EXISTS idx_trial_members_gym ON public.trial_members(gym_id);
CREATE INDEX IF NOT EXISTS idx_trial_members_phone ON public.trial_members(phone);

-- Enable Row-Level Security
ALTER TABLE public.trial_members ENABLE ROW LEVEL SECURITY;

-- Dynamic RLS Policy based on active associated gym membership
DROP POLICY IF EXISTS trial_members_isolation_policy ON public.trial_members;
CREATE POLICY trial_members_isolation_policy ON public.trial_members
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- 2. Drop old restrict constraint on finance_transactions if present
ALTER TABLE public.finance_transactions 
  DROP CONSTRAINT IF EXISTS finance_transactions_category_check;

-- 3. Add updated category check constraint including 'Trial Membership'
ALTER TABLE public.finance_transactions 
  ADD CONSTRAINT finance_transactions_category_check 
  CHECK (category IN ('Membership', 'Salary', 'Salaries', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Trial Membership', 'Other'));

-- 4. Grant schema privileges on the new table
GRANT ALL ON TABLE public.trial_members TO anon, authenticated, service_role;
