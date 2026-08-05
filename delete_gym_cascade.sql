-- =========================================================================
-- DELETE GYM CASCADE: delete_gym_cascade.sql
-- Run this in Supabase SQL Editor.
-- Creates an RPC function that Super Admin can call to permanently delete
-- a gym and ALL its related data (members, staff, attendance, etc.)
-- while KEEPING payments/subscriptions/invoices for financial records.
-- Also forces logout of all gym users (owner, staff, members).
-- =========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_gym_cascade(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_ids UUID[];
    v_gym_name TEXT;
    v_deleted_counts JSONB;
    v_members_count INT := 0;
    v_staff_count INT := 0;
    v_attendance_count INT := 0;
BEGIN
    -- 0. Verify gym exists
    SELECT name INTO v_gym_name FROM public.gyms WHERE id = p_gym_id;
    IF v_gym_name IS NULL THEN
        RAISE EXCEPTION 'Gym not found with id: %', p_gym_id;
    END IF;

    -- 1. Collect ALL user_ids associated with this gym (owners, staff, members)
    SELECT ARRAY_AGG(DISTINCT user_id) INTO v_user_ids
    FROM public.user_gym_associations
    WHERE gym_id = p_gym_id AND user_id IS NOT NULL;

    -- 2. Count records before deletion (for response summary)
    SELECT COUNT(*) INTO v_members_count FROM public.members WHERE gym_id = p_gym_id;
    SELECT COUNT(*) INTO v_staff_count FROM public.staff WHERE gym_id = p_gym_id;
    SELECT COUNT(*) INTO v_attendance_count FROM public.attendance_logs WHERE gym_id = p_gym_id;

    -- 3. Delete all gym-related data (child tables first, parent tables last)
    --    NOTE: We KEEP payments, subscriptions, invoices for financial records.

    -- Attendance & Audit
    DELETE FROM public.attendance_audit_log WHERE gym_id = p_gym_id;
    DELETE FROM public.attendance_alerts WHERE gym_id = p_gym_id;
    DELETE FROM public.attendance_logs WHERE gym_id = p_gym_id;
    DELETE FROM public.attendance WHERE gym_id = p_gym_id;
    DELETE FROM public.attendance_displays WHERE gym_id = p_gym_id;
    DELETE FROM public.attendance_settings WHERE gym_id = p_gym_id;

    -- Member-related
    DELETE FROM public.xp_history WHERE member_id IN (SELECT id FROM public.members WHERE gym_id = p_gym_id);
    DELETE FROM public.member_badge_status WHERE member_id IN (SELECT id FROM public.members WHERE gym_id = p_gym_id);
    DELETE FROM public.member_achievements WHERE member_id IN (SELECT id FROM public.members WHERE gym_id = p_gym_id);
    DELETE FROM public.membership_payments WHERE gym_id = p_gym_id;
    DELETE FROM public.member_memberships WHERE gym_id = p_gym_id;
    DELETE FROM public.trial_members WHERE gym_id = p_gym_id;
    DELETE FROM public.members WHERE gym_id = p_gym_id;

    -- Staff-related
    DELETE FROM public.leave_requests WHERE gym_id = p_gym_id;
    DELETE FROM public.salary_advance_ledger WHERE staff_id IN (SELECT id FROM public.staff WHERE gym_id = p_gym_id);
    DELETE FROM public.salary_payment_commissions WHERE salary_payment_id IN (
        SELECT id FROM public.salary_payments WHERE gym_id = p_gym_id
    );
    DELETE FROM public.salary_payments WHERE gym_id = p_gym_id;
    DELETE FROM public.salary_drafts WHERE gym_id = p_gym_id;
    DELETE FROM public.salaries WHERE gym_id = p_gym_id;
    DELETE FROM public.staff_shift_assignments WHERE staff_id IN (SELECT id FROM public.staff WHERE gym_id = p_gym_id);
    DELETE FROM public.pt_sessions WHERE gym_id = p_gym_id;
    DELETE FROM public.pt_assignments WHERE gym_id = p_gym_id;
    DELETE FROM public.staff WHERE gym_id = p_gym_id;

    -- Plans & Config
    DELETE FROM public.workout_plans WHERE gym_id = p_gym_id;
    DELETE FROM public.diet_plans WHERE gym_id = p_gym_id;
    DELETE FROM public.membership_plans WHERE gym_id = p_gym_id;
    DELETE FROM public.fitness_goals WHERE gym_id = p_gym_id;
    DELETE FROM public.custom_member_fields WHERE gym_id = p_gym_id;
    DELETE FROM public.gym_shifts WHERE gym_id = p_gym_id;
    DELETE FROM public.gym_shift_settings WHERE gym_id = p_gym_id;

    -- Finance (delete internal transactions, but KEEP platform payments)
    DELETE FROM public.expenses WHERE gym_id = p_gym_id;
    DELETE FROM public.finance_transactions WHERE gym_id = p_gym_id;
    DELETE FROM public.transactions WHERE gym_id = p_gym_id;

    -- Invitations, Notifications, Support
    DELETE FROM public.invitations WHERE gym_id = p_gym_id;
    DELETE FROM public.holidays WHERE gym_id = p_gym_id;
    DELETE FROM public.notifications WHERE gym_id = p_gym_id;
    DELETE FROM public.support_messages WHERE ticket_id IN (
        SELECT id FROM public.support_tickets WHERE gym_id = p_gym_id
    );
    DELETE FROM public.support_tickets WHERE gym_id = p_gym_id;
    DELETE FROM public.duplicate_gym_alerts WHERE gym_id = p_gym_id;
    DELETE FROM public.renewal_logs WHERE gym_id = p_gym_id;

    -- User-Gym associations (disconnect all users from this gym)
    DELETE FROM public.user_gym_associations WHERE gym_id = p_gym_id;

    -- 4. Force logout ALL associated users by deleting their auth sessions
    IF v_user_ids IS NOT NULL AND array_length(v_user_ids, 1) > 0 THEN
        DELETE FROM auth.sessions WHERE user_id = ANY(v_user_ids);
        DELETE FROM auth.refresh_tokens WHERE user_id::UUID = ANY(v_user_ids);
    END IF;

    -- 5. Finally, delete the gym record itself
    DELETE FROM public.gyms WHERE id = p_gym_id;

    -- 6. Build response summary
    v_deleted_counts := jsonb_build_object(
        'gym_name', v_gym_name,
        'members_deleted', v_members_count,
        'staff_deleted', v_staff_count,
        'attendance_deleted', v_attendance_count,
        'users_logged_out', COALESCE(array_length(v_user_ids, 1), 0),
        'status', 'success'
    );

    RETURN v_deleted_counts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users (admin check is in the app)
GRANT EXECUTE ON FUNCTION public.delete_gym_cascade(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_gym_cascade(UUID) TO service_role;

COMMIT;
