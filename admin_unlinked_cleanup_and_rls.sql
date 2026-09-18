-- Migration: Clean orphaned transaction in Apex Premium GYM, add admin_delete_unlinked_entry RPC, and enforce strong RLS

-- 1. Delete the specific orphaned transaction in Apex Premium GYM
DELETE FROM finance_transactions 
WHERE id = 'd8dbf320-246f-45bd-ae1f-f7420ef0ab43'
  AND gym_id = 'f896e071-c136-458a-842c-5e171b746f96';

-- 2. Add Super Admin RLS policy to member_memberships
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'member_memberships' AND policyname = 'super_admin_all_member_memberships'
    ) THEN
        CREATE POLICY super_admin_all_member_memberships ON member_memberships
        FOR ALL TO authenticated
        USING (is_super_admin(auth.uid()))
        WITH CHECK (is_super_admin(auth.uid()));
    END IF;
END $$;

-- 3. Add Super Admin RLS policy to membership_payments
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'membership_payments' AND policyname = 'super_admin_all_membership_payments'
    ) THEN
        CREATE POLICY super_admin_all_membership_payments ON membership_payments
        FOR ALL TO authenticated
        USING (is_super_admin(auth.uid()))
        WITH CHECK (is_super_admin(auth.uid()));
    END IF;
END $$;

-- 4. Add Super Admin RLS policy to attendance_logs
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'attendance_logs' AND policyname = 'super_admin_all_attendance_logs'
    ) THEN
        CREATE POLICY super_admin_all_attendance_logs ON attendance_logs
        FOR ALL TO authenticated
        USING (is_super_admin(auth.uid()))
        WITH CHECK (is_super_admin(auth.uid()));
    END IF;
END $$;

-- 5. RPC function: admin_delete_unlinked_entry
-- Cascades and deletes an unlinked/orphaned financial record and all lingering references
CREATE OR REPLACE FUNCTION admin_delete_unlinked_entry(
    p_tx_id UUID,
    p_gym_id UUID,
    p_ref_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted_tx INT := 0;
    v_deleted_mships INT := 0;
    v_deleted_payments INT := 0;
    v_deleted_att INT := 0;
BEGIN
    -- Strict Admin / Super Admin Authorization Check
    IF NOT is_super_admin(auth.uid()) AND NOT is_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Access Denied: Super Admin or Admin role required.';
    END IF;

    -- 1. Delete from finance_transactions if p_tx_id is provided
    IF p_tx_id IS NOT NULL THEN
        DELETE FROM finance_transactions
        WHERE id = p_tx_id AND gym_id = p_gym_id;
        GET DIAGNOSTICS v_deleted_tx = ROW_COUNT;
    END IF;

    -- 2. Clean up any related orphaned tables if p_ref_id (former member_id) is provided
    IF p_ref_id IS NOT NULL AND TRIM(p_ref_id) != '' THEN
        -- Delete any remaining finance transactions referencing this unlinked member
        DELETE FROM finance_transactions
        WHERE reference_id = p_ref_id AND gym_id = p_gym_id;

        -- Clean member_memberships
        BEGIN
            DELETE FROM member_memberships
            WHERE member_id::text = p_ref_id AND gym_id = p_gym_id;
            GET DIAGNOSTICS v_deleted_mships = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        -- Clean attendance_logs
        BEGIN
            DELETE FROM attendance_logs
            WHERE member_id::text = p_ref_id AND gym_id = p_gym_id;
            GET DIAGNOSTICS v_deleted_att = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        -- Clean member_badge_status & xp_history
        BEGIN
            DELETE FROM member_badge_status WHERE member_id::text = p_ref_id;
            DELETE FROM xp_history WHERE member_id::text = p_ref_id;
            DELETE FROM commission_ledger WHERE member_id::text = p_ref_id;
            DELETE FROM invitations WHERE member_id::text = p_ref_id;
            DELETE FROM pt_assignments WHERE member_id::text = p_ref_id;
            DELETE FROM pt_sessions WHERE member_id::text = p_ref_id;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'deleted_tx_count', v_deleted_tx,
        'deleted_mships_count', v_deleted_mships,
        'deleted_attendance_count', v_deleted_att
    );
END;
$$;
