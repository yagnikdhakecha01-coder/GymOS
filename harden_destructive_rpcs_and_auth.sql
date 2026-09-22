-- =============================================================================
-- GYMOS SECURITY HARDENING: PART 1 - RPC & BACKUP EXPLOIT SHIELD
-- PURPOSE: Fix critical exploit vectors where destructive functions or backup
--          tables were accessible to anonymous or unauthorized users.
-- SAFETY GUARANTEE: ZERO data deleted, ZERO tables dropped. 100% live data intact.
-- =============================================================================

BEGIN;

-- 1. REVOKE DANGEROUS PUBLIC / ANON EXECUTE PERMISSIONS
REVOKE EXECUTE ON FUNCTION public.delete_gym_cascade(UUID) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.restore_gym_backup(JSONB) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.get_gym_monthly_financial_summary(UUID, INT, INT) FROM anon, public;

-- Also revoke from any other sensitive helper if present
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'full_database_import') THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.full_database_import(JSONB) FROM anon, public;';
    END IF;
END $$;

-- 2. HARDEN delete_gym_cascade WITH SUPER ADMIN GATEKEEPER
-- Even if an authenticated user calls this via RPC, it will verify they are a super admin.
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
    -- Step A: Extract caller auth id
    v_caller_id := auth.uid();

    -- Step B: If called via REST API without super admin rights, REJECT IMMEDIATELY
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SECURITY ERROR: Anonymous callers cannot delete gym data (Code: 40101)';
    END IF;

    -- Verify super admin status
    SELECT EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE user_id = v_caller_id 
          AND LOWER(COALESCE(role, 'admin')) IN ('super_admin', 'superadmin', 'owner')
    ) INTO v_is_authorized;

    IF NOT v_is_authorized THEN
        -- Check if user is registered in admin_users or has global admin flag
        IF NOT (public.is_admin(v_caller_id)) THEN
            RAISE EXCEPTION 'SECURITY ERROR: Unauthorized. Only verified Super Admins can wipe gym data (Code: 40301)';
        END IF;
    END IF;

    -- Step C: Check if target gym exists
    IF NOT EXISTS (SELECT 1 FROM public.gyms WHERE id = p_gym_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'Gym not found');
    END IF;

    -- Step D: Safely tally counts before cascade removal
    BEGIN SELECT COUNT(*) INTO v_members_count FROM public.members WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN SELECT COUNT(*) INTO v_staff_count FROM public.staff WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN SELECT COUNT(DISTINCT user_id) INTO v_users_count FROM public.user_gym_associations WHERE gym_id = p_gym_id; EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Step E: Clean cascade removal of child records belonging ONLY to this gym
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

    -- Finally remove the Gym record
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

-- Grant execution ONLY to authenticated users and service_role (function itself checks admin permissions)
GRANT EXECUTE ON FUNCTION public.delete_gym_cascade(UUID) TO authenticated, service_role;


-- 3. HARDEN restore_gym_backup WITH SUPER ADMIN GATEKEEPER & SIZE LIMIT
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

    -- Reject unauthenticated calls
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SECURITY ERROR: Authentication required to restore backups (Code: 40102)';
    END IF;

    -- Verify super admin status
    SELECT EXISTS (
        SELECT 1 FROM public.admin_users 
        WHERE user_id = v_caller_id 
          AND LOWER(COALESCE(role, 'admin')) IN ('super_admin', 'superadmin', 'owner')
    ) INTO v_is_authorized;

    IF NOT v_is_authorized AND NOT (public.is_admin(v_caller_id)) THEN
        RAISE EXCEPTION 'SECURITY ERROR: Unauthorized. Only verified Super Admins can restore backups (Code: 40302)';
    END IF;

    -- Reject oversized JSON payloads that could cause Out Of Memory (DoS protection: max 15MB text representation)
    IF length(p_backup_data::text) > 15728640 THEN
        RAISE EXCEPTION 'PAYLOAD TOO LARGE: Backup data exceeds maximum allowed size of 15MB (DoS Protection)';
    END IF;

    -- Enterprise format check
    IF v_payload->'gyms' IS NOT NULL OR v_payload->'_meta' IS NOT NULL THEN
        IF v_payload->'_meta' IS NULL THEN
            v_payload := jsonb_set(v_payload, '{_meta}', '{"version": "2.0", "system": "GymOS Enterprise Backup"}'::jsonb);
        END IF;
        RETURN public.full_database_import(v_payload);
    END IF;

    -- Legacy single gym format check
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


-- 4. HARDEN fn_user_accessible_gym_ids (PREVENT ARBITRARY USER ENUMERATION)
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
    -- Security guard: A caller can only query their own gym associations,
    -- unless they are an admin.
    IF v_caller_id IS NOT NULL AND v_caller_id <> p_user_id THEN
        IF NOT (public.is_admin(v_caller_id)) THEN
            -- Unauthorized probe: Return empty set instead of throwing error to prevent enumeration
            RETURN;
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


-- 5. SECURE gym_backups TABLE RLS (STOP PUBLIC BACKUP LEAKAGE)
ALTER TABLE public.gym_backups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gym_backups_admin_policy ON public.gym_backups;
DROP POLICY IF EXISTS gym_backups_secure_policy ON public.gym_backups;

-- Revoke all table permissions from anon role
REVOKE ALL ON TABLE public.gym_backups FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.gym_backups TO authenticated, service_role;

-- Allow ONLY super admins or the owners of that specific gym to see or create backups
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

COMMIT;
