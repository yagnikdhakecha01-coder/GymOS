-- ====================================================
-- GYMOS - COMPLETE MIGRATION & SUBSCRIPTION SCHEMA
-- ====================================================

-- 1. DROP EXISTING TRIGGERS AND FUNCTIONS IF ANY
DROP TRIGGER IF EXISTS trg_enforce_member_limit ON public.members;
DROP TRIGGER IF EXISTS trg_enforce_staff_limit ON public.staff;
DROP TRIGGER IF EXISTS trg_new_gym_subscription ON public.user_gym_associations;
DROP TRIGGER IF EXISTS trg_auto_first_admin ON auth.users;

DROP FUNCTION IF EXISTS public.enforce_gym_member_limit() CASCADE;
DROP FUNCTION IF EXISTS public.enforce_gym_staff_limit() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_gym_subscription() CASCADE;
DROP FUNCTION IF EXISTS public.auto_setup_first_super_admin() CASCADE;

-- DROP EXISTING SUBSCRIPTION TABLES IF THEY EXIST
DROP TABLE IF EXISTS public.renewal_logs CASCADE;
DROP TABLE IF EXISTS public.subscription_history CASCADE;
DROP TABLE IF EXISTS public.payments CASCADE;
DROP TABLE IF EXISTS public.invoices CASCADE;
DROP TABLE IF EXISTS public.subscriptions CASCADE;
DROP TABLE IF EXISTS public.subscription_plans CASCADE;


-- 2. CREATE DATABASE TABLES

-- Subscription Plans Table
CREATE TABLE public.subscription_plans (
    id TEXT PRIMARY KEY, -- 'free_trial', 'starter', 'pro', 'business'
    name TEXT NOT NULL,
    price NUMERIC(12, 2) NOT NULL,
    max_members INT, -- NULL for unlimited
    max_staff INT,   -- NULL for unlimited
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Subscriptions Table
CREATE TABLE public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL UNIQUE,
    owner_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    plan_id TEXT REFERENCES public.subscription_plans(id) NOT NULL DEFAULT 'free_trial',
    status TEXT NOT NULL CHECK (status IN ('trial', 'active', 'expired', 'cancelled', 'pending_payment', 'paused', 'failed_payment')) DEFAULT 'trial',
    trial_start TIMESTAMPTZ DEFAULT now(),
    trial_end TIMESTAMPTZ DEFAULT (now() + interval '3 months'),
    start_date TIMESTAMPTZ DEFAULT now() NOT NULL,
    end_date TIMESTAMPTZ DEFAULT (now() + interval '3 months') NOT NULL,
    razorpay_subscription_id TEXT,
    razorpay_customer_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Invoices Table
CREATE TABLE public.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    subscription_id UUID REFERENCES public.subscriptions(id) ON DELETE CASCADE NOT NULL,
    invoice_number TEXT UNIQUE NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('paid', 'unpaid', 'expired', 'cancelled')),
    billing_date TIMESTAMPTZ DEFAULT now() NOT NULL,
    due_date TIMESTAMPTZ NOT NULL,
    pdf_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Payments Table (Payment History)
CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    subscription_id UUID REFERENCES public.subscriptions(id) ON DELETE CASCADE,
    invoice_id UUID REFERENCES public.invoices(id) ON DELETE SET NULL,
    amount NUMERIC(12, 2) NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('Success', 'Failed', 'Pending')),
    payment_method TEXT NOT NULL,
    razorpay_payment_id TEXT UNIQUE,
    razorpay_signature TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Subscription History Table (Audit Logs)
CREATE TABLE public.subscription_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    old_plan_id TEXT REFERENCES public.subscription_plans(id),
    new_plan_id TEXT REFERENCES public.subscription_plans(id) NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('Trial Activated', 'Plan Purchased', 'Plan Renewed', 'Plan Upgraded', 'Plan Downgraded', 'Payment Failed', 'Subscription Cancelled')),
    changed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Renewal Logs Table
CREATE TABLE public.renewal_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    subscription_id UUID REFERENCES public.subscriptions(id) ON DELETE CASCADE NOT NULL,
    payment_status TEXT NOT NULL,
    attempts INT DEFAULT 1 NOT NULL,
    last_attempt TIMESTAMPTZ DEFAULT now() NOT NULL,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);


-- 3. SEED SUBSCRIPTION PLANS
INSERT INTO public.subscription_plans (id, name, price, max_members, max_staff) VALUES
('free_trial', 'Free Trial (Pro)', 0.00, 1000, 10),
('starter', 'Starter', 699.00, 150, 3),
('pro', 'Pro', 999.00, 1000, 10),
('business', 'Business', 1999.00, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET max_members = EXCLUDED.max_members, max_staff = EXCLUDED.max_staff;


-- 4. AUTOMATIC 3-MONTH FREE TRIAL TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION public.handle_new_gym_subscription()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role = 'owner' THEN
        INSERT INTO public.subscriptions (gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date)
        VALUES (
            NEW.gym_id,
            NEW.user_id,
            'free_trial',
            'trial',
            now(),
            now() + interval '3 months',
            now(),
            now() + interval '3 months'
        )
        ON CONFLICT (gym_id) DO NOTHING;
        
        -- Log history
        INSERT INTO public.subscription_history (gym_id, old_plan_id, new_plan_id, action, changed_by, notes)
        VALUES (
            NEW.gym_id,
            NULL,
            'free_trial',
            'Trial Activated',
            NEW.user_id,
            '3-month Pro free trial automatically activated.'
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_new_gym_subscription
AFTER INSERT ON public.user_gym_associations
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_gym_subscription();


-- 5. SECURE BACKEND LIMIT ENFORCEMENT FUNCTIONS & TRIGGERS

-- Member Limit Trigger
CREATE OR REPLACE FUNCTION public.enforce_gym_member_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_id TEXT;
    v_status TEXT;
    v_max_members INT;
    v_current_members INT;
BEGIN
    -- Get subscription details for the gym
    SELECT plan_id, status INTO v_plan_id, v_status
    FROM public.subscriptions
    WHERE gym_id = NEW.gym_id;
    
    -- If no subscription found, block additions
    IF v_plan_id IS NULL THEN
        RAISE EXCEPTION 'limit_reached:No active subscription found for this gym. Please purchase a plan.';
    END IF;

    -- If subscription is expired, block additions
    IF v_status IN ('expired', 'cancelled', 'failed_payment') THEN
        RAISE EXCEPTION 'limit_reached:Your subscription status is % and has expired. Please renew or upgrade to add members.', v_status;
    END IF;

    -- Get plan limits
    SELECT max_members INTO v_max_members
    FROM public.subscription_plans
    WHERE id = v_plan_id;

    -- Enforce limits
    IF v_max_members IS NOT NULL THEN
        -- Get current members count
        SELECT count(*) INTO v_current_members
        FROM public.members
        WHERE gym_id = NEW.gym_id;

        IF v_current_members >= v_max_members THEN
            RAISE EXCEPTION 'limit_reached:You have reached your % Plan limit (% Members). Upgrade your subscription to continue.', v_plan_id, v_max_members;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_enforce_member_limit
BEFORE INSERT ON public.members
FOR EACH ROW
EXECUTE FUNCTION public.enforce_gym_member_limit();


-- Staff Limit Trigger
CREATE OR REPLACE FUNCTION public.enforce_gym_staff_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_id TEXT;
    v_status TEXT;
    v_max_staff INT;
    v_current_staff INT;
BEGIN
    -- Get subscription details for the gym
    SELECT plan_id, status INTO v_plan_id, v_status
    FROM public.subscriptions
    WHERE gym_id = NEW.gym_id;
    
    -- If no subscription found, block additions
    IF v_plan_id IS NULL THEN
        RAISE EXCEPTION 'limit_reached:No active subscription found for this gym. Please purchase a plan.';
    END IF;

    -- If subscription is expired, block additions
    IF v_status IN ('expired', 'cancelled', 'failed_payment') THEN
        RAISE EXCEPTION 'limit_reached:Your subscription status is % and has expired. Please renew or upgrade to add staff.', v_status;
    END IF;

    -- Get plan limits
    SELECT max_staff INTO v_max_staff
    FROM public.subscription_plans
    WHERE id = v_plan_id;

    -- Enforce limits
    IF v_max_staff IS NOT NULL THEN
        -- Get current staff count
        SELECT count(*) INTO v_current_staff
        FROM public.staff
        WHERE gym_id = NEW.gym_id;

        IF v_current_staff >= v_max_staff THEN
            RAISE EXCEPTION 'limit_reached:You have reached your % Plan limit (% Staff). Upgrade your subscription to continue.', v_plan_id, v_max_staff;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_enforce_staff_limit
BEFORE INSERT ON public.staff
FOR EACH ROW
EXECUTE FUNCTION public.enforce_gym_staff_limit();


-- 6. PUT ALL EXISTING GYMS INTO THE 3-MONTH FREE TRIAL
INSERT INTO public.subscriptions (gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date)
SELECT 
    g.id as gym_id, 
    (SELECT user_id FROM public.user_gym_associations WHERE gym_id = g.id AND role = 'owner' LIMIT 1) as owner_id,
    'free_trial' as plan_id,
    'trial' as status,
    COALESCE(g.created_at, now()) as trial_start,
    COALESCE(g.created_at, now()) + interval '3 months' as trial_end,
    COALESCE(g.created_at, now()) as start_date,
    COALESCE(g.created_at, now()) + interval '3 months' as end_date
FROM public.gyms g
WHERE (SELECT user_id FROM public.user_gym_associations WHERE gym_id = g.id AND role = 'owner' LIMIT 1) IS NOT NULL
ON CONFLICT (gym_id) DO UPDATE SET 
    plan_id = EXCLUDED.plan_id, 
    status = EXCLUDED.status,
    trial_start = EXCLUDED.trial_start,
    trial_end = EXCLUDED.trial_end,
    start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date;


-- 7. AUTO SETUP FIRST SUPER ADMIN TRIGGER
CREATE OR REPLACE FUNCTION public.auto_setup_first_super_admin()
RETURNS TRIGGER AS $$
DECLARE
    v_count INT;
BEGIN
    SELECT count(*) INTO v_count FROM public.admin_users;
    IF v_count = 0 THEN
        INSERT INTO public.admin_users (user_id, role)
        VALUES (NEW.id, 'super_admin')
        ON CONFLICT (user_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_auto_first_admin
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.auto_setup_first_super_admin();


-- 7.5 AUTO EMAIL CONFIRMATION TRIGGER FOR ADMIN SIGNUP
CREATE OR REPLACE FUNCTION auth.auto_confirm_user_email()
RETURNS TRIGGER AS $$
BEGIN
    NEW.email_confirmed_at := now();
    NEW.confirmed_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_auto_confirm_email
BEFORE INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION auth.auto_confirm_user_email();


-- 8. ENABLE ROW LEVEL SECURITY & GRANT PERMISSIONS
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.renewal_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY subscriptions_isolation_policy ON public.subscriptions
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY invoices_isolation_policy ON public.invoices
    FOR SELECT TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY payments_isolation_policy ON public.payments
    FOR SELECT TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY history_isolation_policy ON public.subscription_history
    FOR SELECT TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY plans_read_policy ON public.subscription_plans
    FOR SELECT TO authenticated
    USING (true);

-- Grant privileges
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
