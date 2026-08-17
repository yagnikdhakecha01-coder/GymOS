-- =========================================================================
-- DATABASE MIGRATION: update_subscription_plans_schema.sql
-- Copy and run this script in your Supabase SQL Editor
-- Ensures subscription_plans table has max_members, max_staff, max_gyms, price, razorpay_plan_id
-- and configures full RLS write permissions for Super Admin.
-- =========================================================================

-- 1. Create subscription_plans table if not exists
CREATE TABLE IF NOT EXISTS public.subscription_plans (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    max_members INT DEFAULT 50, -- NULL or -1 for unlimited
    max_staff INT DEFAULT 5,    -- NULL or -1 for unlimited
    max_gyms INT DEFAULT 1,     -- NULL or -1 for unlimited
    razorpay_plan_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure all required columns exist
ALTER TABLE public.subscription_plans ADD COLUMN IF NOT EXISTS max_members INT DEFAULT 50;
ALTER TABLE public.subscription_plans ADD COLUMN IF NOT EXISTS max_staff INT DEFAULT 5;
ALTER TABLE public.subscription_plans ADD COLUMN IF NOT EXISTS max_gyms INT DEFAULT 1;
ALTER TABLE public.subscription_plans ADD COLUMN IF NOT EXISTS price NUMERIC(12, 2) DEFAULT 0.00;
ALTER TABLE public.subscription_plans ADD COLUMN IF NOT EXISTS razorpay_plan_id TEXT;

-- Enable RLS & Policies
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscription_plans_select_policy ON public.subscription_plans;
CREATE POLICY subscription_plans_select_policy ON public.subscription_plans FOR SELECT USING (true);

DROP POLICY IF EXISTS subscription_plans_all_policy ON public.subscription_plans;
CREATE POLICY subscription_plans_all_policy ON public.subscription_plans FOR ALL USING (true);

GRANT ALL ON public.subscription_plans TO anon, authenticated, service_role;

-- 2. Insert or update default plans in subscription_plans table
INSERT INTO public.subscription_plans (id, name, price, max_members, max_staff, max_gyms)
VALUES
    ('free_trial', 'Free Trial', 0.00, 50, 5, 1),
    ('starter', 'Starter', 699.00, 100, 5, 1),
    ('pro', 'Pro', 999.00, 500, 15, 2),
    ('business', 'Business', 1999.00, -1, -1, 5)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    price = COALESCE(public.subscription_plans.price, EXCLUDED.price),
    max_members = COALESCE(public.subscription_plans.max_members, EXCLUDED.max_members),
    max_staff = COALESCE(public.subscription_plans.max_staff, EXCLUDED.max_staff),
    max_gyms = COALESCE(public.subscription_plans.max_gyms, EXCLUDED.max_gyms);
