-- ====================================================================
-- GYMOS - FIX SUBSCRIPTION, INVOICES, PAYMENTS & HISTORY RLS POLICIES
-- Run this script in your Supabase SQL Editor to resolve RLS 403 Errors
-- ====================================================================

-- 1. Enable RLS on all subscription-related tables
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing restrictive policies if any
DROP POLICY IF EXISTS subscriptions_isolation_policy ON public.subscriptions;
DROP POLICY IF EXISTS invoices_isolation_policy ON public.invoices;
DROP POLICY IF EXISTS payments_isolation_policy ON public.payments;
DROP POLICY IF EXISTS history_isolation_policy ON public.subscription_history;
DROP POLICY IF EXISTS plans_read_policy ON public.subscription_plans;

-- 3. Create permissive policies for authenticated users tied to their gym
CREATE POLICY subscriptions_isolation_policy ON public.subscriptions
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
    WITH CHECK (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY invoices_isolation_policy ON public.invoices
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
    WITH CHECK (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY payments_isolation_policy ON public.payments
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
    WITH CHECK (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY history_isolation_policy ON public.subscription_history
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
    WITH CHECK (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY plans_read_policy ON public.subscription_plans
    FOR SELECT TO authenticated
    USING (true);

-- 4. Grant explicit table privileges to authenticated and service_role
GRANT ALL ON TABLE public.subscriptions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.invoices TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.payments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_history TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_plans TO anon, authenticated, service_role;
