-- ====================================================
-- GYMOS ADMIN - MASTER ARCHITECTURE DATABASE MIGRATION
-- ====================================================

-- 1. ADD COLUMNS TO EXISTING GYMS TABLE IF THEY DO NOT EXIST
DO $$ 
BEGIN
    -- Add status column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='status') THEN
        ALTER TABLE public.gyms ADD COLUMN status TEXT CHECK (status IN ('trial', 'active', 'grace_period', 'suspended', 'disabled')) DEFAULT 'trial';
    END IF;

    -- Add plan column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='plan') THEN
        ALTER TABLE public.gyms ADD COLUMN plan TEXT CHECK (plan IN ('free_trial', 'starter', 'pro', 'business')) DEFAULT 'free_trial';
    END IF;

    -- Add expiry_date column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='expiry_date') THEN
        ALTER TABLE public.gyms ADD COLUMN expiry_date TIMESTAMPTZ;
    END IF;

    -- Add trial_end_date column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='trial_end_date') THEN
        ALTER TABLE public.gyms ADD COLUMN trial_end_date TIMESTAMPTZ DEFAULT (now() + interval '3 months');
    END IF;

    -- Add disabled_reason column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='disabled_reason') THEN
        ALTER TABLE public.gyms ADD COLUMN disabled_reason TEXT;
    END IF;

    -- Add suspended_reason column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='suspended_reason') THEN
        ALTER TABLE public.gyms ADD COLUMN suspended_reason TEXT;
    END IF;

    -- Add notes column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='notes') THEN
        ALTER TABLE public.gyms ADD COLUMN notes TEXT;
    END IF;

    -- Add app_version column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='app_version') THEN
        ALTER TABLE public.gyms ADD COLUMN app_version TEXT DEFAULT 'v2.4.1';
    END IF;

    -- Add last_login_at column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='gyms' AND column_name='last_login_at') THEN
        ALTER TABLE public.gyms ADD COLUMN last_login_at TIMESTAMPTZ;
    END IF;
END $$;


-- 2. CREATE NEW TABLES FOR ADMIN MODULES
CREATE TABLE IF NOT EXISTS public.admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
    role TEXT NOT NULL CHECK (role IN ('super_admin', 'support', 'read_only')) DEFAULT 'super_admin',
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.admin_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    device_info TEXT,
    ip_address TEXT,
    logged_in_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    admin_email TEXT,
    action TEXT NOT NULL,
    category TEXT NOT NULL,
    gym_id UUID,
    gym_name TEXT,
    details TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.platform_plans (
    id TEXT PRIMARY KEY, -- 'free_trial', 'starter', 'pro', 'business'
    name TEXT NOT NULL,
    price NUMERIC(12,2) NOT NULL,
    billing_cycle TEXT NOT NULL CHECK (billing_cycle IN ('monthly', 'yearly')),
    features TEXT[] NOT NULL,
    is_popular BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.platform_coupons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    discount_percentage NUMERIC(5,2) NOT NULL,
    valid_until TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.platform_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    plan_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('Success', 'Failed', 'Pending')),
    payment_method TEXT NOT NULL,
    transaction_id TEXT UNIQUE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.app_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    latest_version TEXT NOT NULL,
    minimum_version TEXT NOT NULL,
    force_update BOOLEAN DEFAULT false NOT NULL,
    maintenance_mode BOOLEAN DEFAULT false NOT NULL,
    update_message TEXT,
    release_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.platform_feature_flags (
    key TEXT PRIMARY KEY,
    is_enabled BOOLEAN DEFAULT true NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.platform_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('push', 'banner', 'popup', 'maintenance', 'offer')),
    target_type TEXT NOT NULL CHECK (target_type IN ('all_gyms', 'trial_gyms', 'active_gyms', 'selected_gyms')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    priority TEXT NOT NULL CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    status TEXT NOT NULL CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')) DEFAULT 'open',
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.duplicate_gym_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    new_gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    existing_gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    similarity_score INTEGER NOT NULL,
    reasons TEXT[] NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'ignored', 'suspended', 'deleted')) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);


-- 3. DEFINE SUPER ADMIN CHECK HELPER FUNCTION
CREATE OR REPLACE FUNCTION public.is_super_admin(req_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE admin_users.user_id = req_user_id AND role = 'super_admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. ENABLE RLS FOR NEW TABLES AND SETUP POLICIES
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_feature_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.duplicate_gym_alerts ENABLE ROW LEVEL SECURITY;

-- Create Policies to grant full access to Super Admins across all tables
DO $$
DECLARE
    t TEXT;
    tables_list TEXT[] := ARRAY[
        'gyms', 'profiles', 'user_gym_associations', 'invitations', 'members', 'staff', 'attendance', 'transactions',
        'membership_plans', 'expenses', 'workout_plans', 'diet_plans', 'pt_sessions', 'salaries', 'notifications', 'holidays',
        'admin_users', 'admin_sessions', 'audit_logs', 'platform_plans', 'platform_coupons', 'platform_payments', 
        'app_versions', 'platform_feature_flags', 'platform_notifications', 'support_tickets', 'duplicate_gym_alerts'
    ];
BEGIN
    FOREACH t IN ARRAY tables_list LOOP
        -- Drop if policy exists
        EXECUTE format('DROP POLICY IF EXISTS super_admin_all_%I ON public.%I', t, t);
        
        -- Create permissive policy for Super Admin
        EXECUTE format('CREATE POLICY super_admin_all_%I ON public.%I FOR ALL TO authenticated USING (public.is_super_admin(auth.uid())) WITH CHECK (public.is_super_admin(auth.uid()))', t, t);
    END LOOP;
END $$;

-- Allow read-only access to platform_plans and feature_flags for non-admin users (e.g. gym owners checking features/plans)
DROP POLICY IF EXISTS select_platform_plans_public ON public.platform_plans;
CREATE POLICY select_platform_plans_public ON public.platform_plans FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS select_feature_flags_public ON public.platform_feature_flags;
CREATE POLICY select_feature_flags_public ON public.platform_feature_flags FOR SELECT TO authenticated USING (true);


-- 5. POPULATE INITIAL DEFAULT DATA FOR PREVIEW
INSERT INTO public.platform_plans (id, name, price, billing_cycle, features, is_popular)
VALUES 
('free_trial', 'Free Trial', 0.00, 'monthly', ARRAY['3 Months Free', 'All Features', 'Up to 50 Members', '2 Staff'], false),
('starter', 'Starter', 499.00, 'monthly', ARRAY['100 Members', '5 Staff', 'QR Attendance', 'Basic Reports'], false),
('pro', 'Pro', 999.00, 'monthly', ARRAY['500 Members', '15 Staff', 'All Attendance', 'AI Features', 'Priority Support'], true),
('business', 'Business', 1999.00, 'monthly', ARRAY['Unlimited Members', 'Unlimited Staff', 'All Features', 'Custom Branding', 'Dedicated Support'], false)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, price = EXCLUDED.price, features = EXCLUDED.features, is_popular = EXCLUDED.is_popular;

INSERT INTO public.platform_feature_flags (key, is_enabled)
VALUES 
('qr_attendance', true),
('manual_attendance', true),
('pt_module', true),
('ai_diet', false),
('ai_workout', true),
('finance', true),
('member_app', true),
('staff_app', true),
('beacon_attendance', false),
('notifications', true)
ON CONFLICT (key) DO NOTHING;

-- Pre-seed App Version information
INSERT INTO public.app_versions (latest_version, minimum_version, force_update, maintenance_mode, update_message, release_notes)
VALUES ('2.4.1', '2.3.0', false, false, 'A new version is available with bug fixes and performance improvements.', '• Fixed attendance sync issue\n• Improved dashboard loading\n• New AI diet recommendations\n• Bug fixes')
LIMIT 1;
