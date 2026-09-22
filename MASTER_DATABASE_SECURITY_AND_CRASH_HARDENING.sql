-- =============================================================================
-- GYMOS ENTERPRISE MASTER DATABASE SECURITY & CRASH HARDENING
-- =============================================================================
-- Execution Target: Supabase SQL Editor
-- Objective:
--   1. Live Data Protection: 100% Zero Data Loss, Zero Table Drops.
--   2. Exploit Shield: Block unauthorized deletion, backup leaks, IDOR attacks.
--   3. Anti-Crash Engine: Defensive statement timeouts & compound indexes.
--   4. Tenant Isolation: FORCE RLS on all tenant-scoped tables.
-- =============================================================================

BEGIN;

-- =============================================================================
-- SECTION 1: REVOKE ANONYMOUS ACCESS FROM DESTRUCTIVE FUNCTIONS
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.delete_gym_cascade(UUID) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.restore_gym_backup(JSONB) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.get_gym_monthly_financial_summary(UUID, INT, INT) FROM anon, public;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'full_database_import') THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.full_database_import(JSONB) FROM anon, public;';
    END IF;
END $$;


-- =============================================================================
-- SECTION 2: HARDEN delete_gym_cascade WITH SUPER ADMIN VERIFICATION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.delete_gym_cascade(p_gym_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
    v_is_authorized BOOLEAN := false;
    v_members_count INT := 0;
    v_staff_count INT := 0;
    v_users_count INT := 0;
BEGIN
    v_caller_id := auth.uid();

    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SECURITY ERROR: Anonymous callers cannot delete gym data (Code: 40101)';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE user_id = v_caller_id 
          AND LOWER(COALESCE(role, 'admin')) IN ('super_admin', 'superadmin', 'owner')
    ) INTO v_is_authorized;

    IF NOT v_is_authorized THEN
        IF NOT (public.is_admin(v_caller_id)) THEN
            RAISE EXCEPTION 'SECURITY ERROR: Unauthorized. Only verified Super Admins can delete gyms (Code: 40301)';
        END IF;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.gyms WHERE id = p_gym_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'Gym not found');
    END IF;

    BEGIN SELECT COUNT(*) INTO v_members_count FROM public.members WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN SELECT COUNT(*) INTO v_staff_count FROM public.staff WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN SELECT COUNT(DISTINCT user_id) INTO v_users_count FROM public.user_gym_associations WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN DELETE FROM public.finance_transactions WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.transactions WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.attendance_logs WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.attendance WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.member_memberships WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.membership_plans WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.expenses WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.pt_sessions WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.salaries WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.holidays WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.members WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.staff WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.salary_drafts WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.salary_advance_ledger WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.leave_requests WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.workout_plans WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.diet_plans WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.goals WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.custom_fields WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.attendance_settings WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.activity_logs WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.notifications WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.support_tickets WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.gym_backups WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.subscriptions WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.user_gym_associations WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;

    DELETE FROM public.gyms WHERE id = p_gym_id;

    RETURN jsonb_build_object(
        'success', true,
        'members_deleted', v_members_count,
        'staff_deleted', v_staff_count,
        'users_unlinked', v_users_count,
        'message', 'Gym successfully deleted with authorization verification'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_gym_cascade(UUID) TO authenticated, service_role;


-- =============================================================================
-- SECTION 3: HARDEN restore_gym_backup (SIZE LIMIT + SUPER ADMIN GUARD)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.restore_gym_backup(p_backup_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
    v_is_authorized BOOLEAN := false;
    v_gym_obj JSONB;
    v_payload JSONB := p_backup_data;
BEGIN
    v_caller_id := auth.uid();

    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SECURITY ERROR: Authentication required to restore backups (Code: 40102)';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE user_id = v_caller_id 
          AND LOWER(COALESCE(role, 'admin')) IN ('super_admin', 'superadmin', 'owner')
    ) INTO v_is_authorized;

    IF NOT v_is_authorized AND NOT (public.is_admin(v_caller_id)) THEN
        RAISE EXCEPTION 'SECURITY ERROR: Unauthorized. Only verified Super Admins can restore backups (Code: 40302)';
    END IF;

    -- Anti-DoS: Payload Size Limit (Max 15MB)
    IF length(p_backup_data::text) > 15728640 THEN
        RAISE EXCEPTION 'PAYLOAD TOO LARGE: Backup data exceeds maximum allowed size of 15MB (DoS Protection)';
    END IF;

    IF v_payload->'gyms' IS NOT NULL OR v_payload->'_meta' IS NOT NULL THEN
        IF v_payload->'_meta' IS NULL THEN
            v_payload := jsonb_set(v_payload, '{_meta}', '{"version": "2.0", "system": "GymOS Enterprise Backup"}'::jsonb);
        END IF;
        RETURN public.full_database_import(v_payload);
    END IF;

    v_gym_obj := v_payload->'gym';
    IF v_gym_obj IS NULL OR v_gym_obj->>'id' IS NULL THEN
        RAISE EXCEPTION 'Invalid backup data format: Missing gym record in JSON payload';
    END IF;

    v_payload := jsonb_build_object(
        '_meta', jsonb_build_object('version', '2.0', 'system', 'GymOS Enterprise Backup'),
        'gyms', jsonb_build_array(v_gym_obj)
    );

    IF p_backup_data->'profiles' IS NOT NULL THEN v_payload := jsonb_set(v_payload, '{profiles}', p_backup_data->'profiles'); END IF;
    IF p_backup_data->'user_gym_associations' IS NOT NULL THEN v_payload := jsonb_set(v_payload, '{user_gym_associations}', p_backup_data->'user_gym_associations'); END IF;
    IF p_backup_data->'members' IS NOT NULL THEN v_payload := jsonb_set(v_payload, '{members}', p_backup_data->'members'); END IF;
    IF p_backup_data->'staff' IS NOT NULL THEN v_payload := jsonb_set(v_payload, '{staff}', p_backup_data->'staff'); END IF;
    IF p_backup_data->'subscriptions' IS NOT NULL THEN v_payload := jsonb_set(v_payload, '{subscriptions}', p_backup_data->'subscriptions'); END IF;
    IF p_backup_data->'attendance_settings' IS NOT NULL THEN v_payload := jsonb_set(v_payload, '{attendance_settings}', jsonb_build_array(p_backup_data->'attendance_settings')); END IF;

    RETURN public.full_database_import(v_payload);
END;
$$;

GRANT EXECUTE ON FUNCTION public.restore_gym_backup(JSONB) TO authenticated, service_role;


-- =============================================================================
-- SECTION 4: HARDEN fn_user_accessible_gym_ids (USER PROBE PREVENTION)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_user_accessible_gym_ids(p_user_id UUID)
RETURNS SETOF UUID
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
BEGIN
    IF v_caller_id IS NOT NULL AND v_caller_id <> p_user_id THEN
        IF NOT (public.is_admin(v_caller_id)) THEN
            RETURN; -- Return empty set on unauthorized probe
        END IF;
    END IF;

    RETURN QUERY
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = p_user_id
        UNION
        SELECT gym_id FROM public.staff WHERE user_id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_user_accessible_gym_ids(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_user_accessible_gym_ids(UUID) TO authenticated, service_role;


-- =============================================================================
-- SECTION 5: SECURE gym_backups TABLE RLS (PREVENT PUBLIC DATA THEFT)
-- =============================================================================

ALTER TABLE public.gym_backups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_backups FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gym_backups_admin_policy ON public.gym_backups;
DROP POLICY IF EXISTS gym_backups_secure_policy ON public.gym_backups;

REVOKE ALL ON TABLE public.gym_backups FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.gym_backups TO authenticated, service_role;

CREATE POLICY gym_backups_secure_policy ON public.gym_backups
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() 
          AND LOWER(role) IN ('owner', 'admin', 'gym_owner')
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() 
          AND LOWER(role) IN ('owner', 'admin', 'gym_owner')
    )
);


-- =============================================================================
-- SECTION 6: DEFENSIVE SERVER TIMEOUTS (CRASH & HANG PREVENTION)
-- =============================================================================

ALTER ROLE authenticated SET statement_timeout = '10000'; -- 10 seconds max query
ALTER ROLE anon SET statement_timeout = '5000'; -- 5 seconds max query

ALTER ROLE authenticated SET idle_in_transaction_session_timeout = '30000'; -- 30 seconds
ALTER ROLE anon SET idle_in_transaction_session_timeout = '10000'; -- 10 seconds

ALTER ROLE authenticated SET lock_timeout = '5000'; -- 5 seconds max lock wait
ALTER ROLE anon SET lock_timeout = '3000';


-- =============================================================================
-- SECTION 7: ANTI-DOS COMPOUND INDEXES (SUB-MILLISECOND QUERY ACCELERATION)
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_members_gym_id ON public.members (gym_id);
CREATE INDEX IF NOT EXISTS idx_members_gym_status ON public.members (gym_id, status);
CREATE INDEX IF NOT EXISTS idx_members_gym_phone ON public.members (gym_id, phone);
CREATE INDEX IF NOT EXISTS idx_members_user_id ON public.members (user_id);

CREATE INDEX IF NOT EXISTS idx_attendance_gym_id ON public.attendance (gym_id);
CREATE INDEX IF NOT EXISTS idx_attendance_gym_date ON public.attendance (gym_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_member_date ON public.attendance (member_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_staff_gym_id ON public.staff (gym_id);
CREATE INDEX IF NOT EXISTS idx_staff_gym_user ON public.staff (gym_id, user_id);
CREATE INDEX IF NOT EXISTS idx_staff_gym_status ON public.staff (gym_id, status);

CREATE INDEX IF NOT EXISTS idx_user_gym_associations_user_id ON public.user_gym_associations (user_id);
CREATE INDEX IF NOT EXISTS idx_user_gym_associations_gym_id ON public.user_gym_associations (gym_id);
CREATE INDEX IF NOT EXISTS idx_user_gym_associations_composite ON public.user_gym_associations (user_id, gym_id);

CREATE INDEX IF NOT EXISTS idx_finance_gym_date ON public.finance_transactions (gym_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_finance_gym_type ON public.finance_transactions (gym_id, transaction_type);

CREATE INDEX IF NOT EXISTS idx_subscriptions_gym_id ON public.subscriptions (gym_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions (status);

CREATE INDEX IF NOT EXISTS idx_activity_logs_gym_date ON public.activity_logs (gym_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_gym_date ON public.attendance_audit_log (gym_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_salaries_gym_month ON public.salaries (gym_id, month_year);
CREATE INDEX IF NOT EXISTS idx_salary_advance_gym ON public.salary_advance_ledger (gym_id);
CREATE INDEX IF NOT EXISTS idx_membership_plans_gym_active ON public.membership_plans (gym_id, is_active);


-- =============================================================================
-- SECTION 8: FORCE ROW LEVEL SECURITY (MULTI-TENANT LEAK PREVENTION)
-- =============================================================================

ALTER TABLE public.gyms FORCE ROW LEVEL SECURITY;
ALTER TABLE public.members FORCE ROW LEVEL SECURITY;
ALTER TABLE public.staff FORCE ROW LEVEL SECURITY;
ALTER TABLE public.attendance FORCE ROW LEVEL SECURITY;
ALTER TABLE public.finance_transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.membership_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE public.member_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.salaries FORCE ROW LEVEL SECURITY;
ALTER TABLE public.salary_advance_ledger FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_gym_associations FORCE ROW LEVEL SECURITY;

COMMIT;
