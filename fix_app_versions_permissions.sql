-- Fix permissions and RLS for app_versions table in GymOS Admin
-- 1. Grant table-level permissions to authenticated, anon, and service_role
GRANT ALL ON TABLE public.app_versions TO authenticated, anon, service_role;
GRANT ALL ON TABLE public.version_activity_logs TO authenticated, anon, service_role;

-- 2. Grant sequence permissions
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, anon, service_role;

-- 3. Clean up and recreate RLS policies for app_versions
DROP POLICY IF EXISTS app_versions_select_policy ON public.app_versions;
DROP POLICY IF EXISTS app_versions_write_policy ON public.app_versions;
DROP POLICY IF EXISTS app_versions_admin_write ON public.app_versions;
DROP POLICY IF EXISTS app_versions_read ON public.app_versions;
DROP POLICY IF EXISTS app_versions_select ON public.app_versions;
DROP POLICY IF EXISTS app_versions_insert ON public.app_versions;
DROP POLICY IF EXISTS app_versions_update ON public.app_versions;
DROP POLICY IF EXISTS app_versions_delete ON public.app_versions;

CREATE POLICY app_versions_select ON public.app_versions
    FOR SELECT USING (true);

CREATE POLICY app_versions_insert ON public.app_versions
    FOR INSERT TO authenticated
    WITH CHECK (true);

CREATE POLICY app_versions_update ON public.app_versions
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY app_versions_delete ON public.app_versions
    FOR DELETE TO authenticated
    USING (true);

-- 4. Clean up and recreate RLS policies for version_activity_logs
DROP POLICY IF EXISTS logs_select_policy ON public.version_activity_logs;
DROP POLICY IF EXISTS logs_write_policy ON public.version_activity_logs;

CREATE POLICY logs_select_policy ON public.version_activity_logs
    FOR SELECT TO authenticated USING (true);

CREATE POLICY logs_write_policy ON public.version_activity_logs
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);
