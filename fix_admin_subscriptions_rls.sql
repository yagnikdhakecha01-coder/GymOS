-- ====================================================================
-- GYMOS ADMIN - SUBSCRIPTIONS & PLANS SUPER ADMIN RLS FIX
-- Run this script in your Supabase SQL Editor
-- ====================================================================

-- 1. Enable RLS on all related tables
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_history ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing restrictive policies if any
DROP POLICY IF EXISTS super_admin_all_subscriptions ON public.subscriptions;
DROP POLICY IF EXISTS super_admin_all_subscription_plans ON public.subscription_plans;
DROP POLICY IF EXISTS super_admin_all_invoices ON public.invoices;
DROP POLICY IF EXISTS super_admin_all_payments ON public.payments;
DROP POLICY IF EXISTS super_admin_all_subscription_history ON public.subscription_history;

-- 3. Create full permission policies for super admins and authenticated users
CREATE POLICY super_admin_all_subscriptions ON public.subscriptions
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY super_admin_all_subscription_plans ON public.subscription_plans
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY super_admin_all_invoices ON public.invoices
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY super_admin_all_payments ON public.payments
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY super_admin_all_subscription_history ON public.subscription_history
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 4. Grant explicit table permissions
GRANT ALL ON TABLE public.subscriptions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_plans TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.invoices TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.payments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_history TO anon, authenticated, service_role;
