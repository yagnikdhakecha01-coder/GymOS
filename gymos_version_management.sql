-- ====================================================
-- GYMOS - APP VERSION MANAGEMENT SYSTEM SCHEMA
-- ====================================================

-- 1. DROP EXISTING TRIGGERS AND TABLES IF THEY EXIST
DROP TRIGGER IF EXISTS trg_log_version_changes ON public.app_versions;
DROP FUNCTION IF EXISTS public.log_version_change() CASCADE;
DROP TABLE IF EXISTS public.version_activity_logs CASCADE;
DROP TABLE IF EXISTS public.app_versions CASCADE;


-- 2. CREATE APP VERSIONS TABLE
CREATE TABLE public.app_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    version_name TEXT NOT NULL,
    build_number INT NOT NULL,
    min_supported_version TEXT NOT NULL DEFAULT '1.0.0',
    latest_version TEXT NOT NULL DEFAULT '1.0.0',
    download_url TEXT,
    release_notes TEXT,
    is_force_update BOOLEAN NOT NULL DEFAULT false,
    is_optional_update BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL CHECK (status IN ('draft', 'published')) DEFAULT 'draft',
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT unique_platform_version_build UNIQUE (platform, version_name, build_number)
);


-- 3. CREATE VERSION ACTIVITY LOGS TABLE
CREATE TABLE public.version_activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_id UUID REFERENCES public.app_versions(id) ON DELETE SET NULL,
    action TEXT NOT NULL, -- 'Created', 'Published', 'Modified', 'Forced Update Enabled', 'Optional Update Enabled'
    changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);


-- 4. SEED INITIAL LIVE VERSION 1.0.0
INSERT INTO public.app_versions (platform, version_name, build_number, min_supported_version, latest_version, download_url, release_notes, is_force_update, is_optional_update, status)
VALUES 
('android', '1.0.0', 1, '1.0.0', '1.0.0', 'https://play.google.com/store/apps/details?id=com.gymos.app', 'Initial release of GymOS app.', false, false, 'published'),
('ios', '1.0.0', 1, '1.0.0', '1.0.0', 'https://apps.apple.com/app/gymos', 'Initial release of GymOS app.', false, false, 'published')
ON CONFLICT (platform, version_name, build_number) DO NOTHING;


-- 5. AUTOMATIC AUDITING TRIGGER ON APP VERSIONS
CREATE OR REPLACE FUNCTION public.log_version_change()
RETURNS TRIGGER AS $$
DECLARE
    v_action TEXT;
    v_notes TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.log_version_change()
RETURNS TRIGGER AS $$
DECLARE
    v_action TEXT;
    v_notes TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_action := CASE WHEN NEW.status = 'published' THEN 'Published' ELSE 'Created' END;
        v_notes := 'New version ' || NEW.version_name || ' (' || NEW.build_number || ') created as ' || NEW.status || '.';
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'draft' AND NEW.status = 'published' THEN
            v_action := 'Published';
            v_notes := 'Version ' || NEW.version_name || ' published to production.';
        ELSE
            v_action := 'Modified';
            v_notes := 'Version metadata updated.';
            IF OLD.is_force_update != NEW.is_force_update THEN
                v_notes := v_notes || ' Force Update changed to ' || NEW.is_force_update || '.';
            END IF;
        END IF;
    END IF;

    INSERT INTO public.version_activity_logs (version_id, action, changed_by, notes)
    VALUES (NEW.id, v_action, auth.uid(), v_notes);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_log_version_changes
AFTER INSERT OR UPDATE ON public.app_versions
FOR EACH ROW
EXECUTE FUNCTION public.log_version_change();


-- 6. SECURITY & ROW LEVEL SECURITY (RLS)
ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.version_activity_logs ENABLE ROW LEVEL SECURITY;

-- Dynamic RLS Policies
-- Allow anyone (even anonymous/unauthenticated client checks) to select versions
CREATE POLICY app_versions_select_policy ON public.app_versions
    FOR SELECT USING (true);

-- Allow authenticated users to view logs
CREATE POLICY logs_select_policy ON public.version_activity_logs
    FOR SELECT TO authenticated USING (true);

-- Restrict write/modify access to Super Admins only
CREATE POLICY app_versions_write_policy ON public.app_versions
    FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid() AND role = 'super_admin'))
    WITH CHECK (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid() AND role = 'super_admin'));

CREATE POLICY logs_write_policy ON public.version_activity_logs
    FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid() AND role = 'super_admin'))
    WITH CHECK (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid() AND role = 'super_admin'));

-- Grant read privileges to authenticated and anonymous users
GRANT SELECT ON public.app_versions TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
