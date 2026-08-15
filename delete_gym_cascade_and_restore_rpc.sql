-- =========================================================================
-- SUPER ADMIN COMPLETE BACKUP, CASCADE DELETE & STATUS FIX MIGRATION
-- RUN THIS ENTIRE SCRIPT IN SUPABASE SQL EDITOR
-- =========================================================================

-- 1. FIX GYM STATUS CHECK CONSTRAINT (Allows Active, Suspended, free_trial, Trial, etc.)
ALTER TABLE public.gyms DROP CONSTRAINT IF EXISTS gyms_status_check;
ALTER TABLE public.gyms ADD CONSTRAINT gyms_status_check CHECK (
    status IN ('Active', 'active', 'Suspended', 'suspended', 'Disabled', 'disabled', 'Grace Period', 'grace_period', 'Trial', 'trial', 'free_trial', 'Expired', 'expired')
);

-- 2. CREATE AND PERMIT GYM BACKUPS TABLE
CREATE TABLE IF NOT EXISTS public.gym_backups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE,
    backup_name TEXT NOT NULL,
    backup_data JSONB NOT NULL,
    size_bytes BIGINT DEFAULT 0,
    provider TEXT DEFAULT 'Super Admin Backup System',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.gym_backups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gym_backups_admin_policy ON public.gym_backups;
CREATE POLICY gym_backups_admin_policy ON public.gym_backups FOR ALL USING (true) WITH CHECK (true);
GRANT ALL ON TABLE public.gym_backups TO anon, authenticated, service_role;

-- 3. DROP OLD FUNCTIONS FIRST TO ALLOW RETURN TYPE & PARAMETER RE-DEFINITION
DROP FUNCTION IF EXISTS public.delete_gym_cascade(UUID);
DROP FUNCTION IF EXISTS public.restore_gym_backup(JSONB);
DROP FUNCTION IF EXISTS public.get_gym_monthly_financial_summary(UUID, INT, INT);

-- 4. CLEAN CASCADE DELETE GYM (Auto-unlinks users, deletes profiles, leaves 0 dummy accounts)
CREATE OR REPLACE FUNCTION public.delete_gym_cascade(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_members_count INT := 0;
    v_staff_count INT := 0;
    v_users_count INT := 0;
BEGIN
    -- Check if gym exists
    IF NOT EXISTS (SELECT 1 FROM public.gyms WHERE id = p_gym_id) THEN
        RETURN jsonb_build_object('success', false, 'message', 'Gym not found');
    END IF;

    -- Count before deletion for summary
    SELECT COUNT(*) INTO v_members_count FROM public.members WHERE gym_id = p_gym_id;
    SELECT COUNT(*) INTO v_staff_count FROM public.staff WHERE gym_id = p_gym_id;
    SELECT COUNT(*) INTO v_users_count FROM public.profiles WHERE gym_id = p_gym_id;

    -- Delete all child table records linked to gym_id
    DELETE FROM public.finance_transactions WHERE gym_id = p_gym_id;
    DELETE FROM public.transactions WHERE gym_id = p_gym_id;
    DELETE FROM public.attendance_logs WHERE gym_id = p_gym_id;
    DELETE FROM public.member_memberships WHERE gym_id = p_gym_id;
    DELETE FROM public.members WHERE gym_id = p_gym_id;
    DELETE FROM public.staff WHERE gym_id = p_gym_id;
    DELETE FROM public.salary_drafts WHERE gym_id = p_gym_id;
    DELETE FROM public.salary_advance_ledger WHERE gym_id = p_gym_id;
    DELETE FROM public.leave_requests WHERE gym_id = p_gym_id;
    DELETE FROM public.workout_plans WHERE gym_id = p_gym_id;
    DELETE FROM public.diet_plans WHERE gym_id = p_gym_id;
    DELETE FROM public.goals WHERE gym_id = p_gym_id;
    DELETE FROM public.custom_fields WHERE gym_id = p_gym_id;
    DELETE FROM public.attendance_settings WHERE gym_id = p_gym_id;
    DELETE FROM public.activity_logs WHERE gym_id = p_gym_id;
    DELETE FROM public.notifications WHERE gym_id = p_gym_id;
    DELETE FROM public.support_tickets WHERE gym_id = p_gym_id;
    DELETE FROM public.gym_backups WHERE gym_id = p_gym_id;

    -- Unlink and delete profiles associated with this gym
    DELETE FROM public.profiles WHERE gym_id = p_gym_id;

    -- Finally delete the Gym itself
    DELETE FROM public.gyms WHERE id = p_gym_id;

    RETURN jsonb_build_object(
        'success', true,
        'members_deleted', v_members_count,
        'staff_deleted', v_staff_count,
        'users_logged_out', v_users_count,
        'message', 'Gym completely wiped cleanly'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.delete_gym_cascade(UUID) TO anon, authenticated, service_role;


-- 5. ONE-CLICK RESTORE GYM FROM BACKUP JSON BUNDLE
CREATE OR REPLACE FUNCTION public.restore_gym_backup(p_backup_data JSONB)
RETURNS JSONB AS $$
DECLARE
    v_gym_id UUID;
    v_gym_obj JSONB;
BEGIN
    v_gym_obj := p_backup_data->'gym';
    IF v_gym_obj IS NULL OR v_gym_obj->>'id' IS NULL THEN
        RAISE EXCEPTION 'Invalid backup data format: Missing gym record';
    END IF;

    v_gym_id := (v_gym_obj->>'id')::UUID;

    -- 1. Upsert Gym
    INSERT INTO public.gyms (
        id, name, owner_name, email, phone, address, status, 
        is_locked, plan_type, expiry_date, max_staff_limit, max_members_limit, created_at
    )
    VALUES (
        v_gym_id,
        COALESCE(v_gym_obj->>'name', 'Restored Gym'),
        COALESCE(v_gym_obj->>'owner_name', 'Owner'),
        COALESCE(v_gym_obj->>'email', ''),
        COALESCE(v_gym_obj->>'phone', ''),
        COALESCE(v_gym_obj->>'address', ''),
        COALESCE(v_gym_obj->>'status', 'Active'),
        COALESCE((v_gym_obj->>'is_locked')::BOOLEAN, FALSE),
        COALESCE(v_gym_obj->>'plan_type', 'Trial'),
        CASE WHEN (v_gym_obj->>'expiry_date') IS NOT NULL AND (v_gym_obj->>'expiry_date') != '' 
             THEN (v_gym_obj->>'expiry_date')::TIMESTAMPTZ ELSE now() + interval '30 days' END,
        COALESCE((v_gym_obj->>'max_staff_limit')::INT, 10),
        COALESCE((v_gym_obj->>'max_members_limit')::INT, 100),
        CASE WHEN (v_gym_obj->>'created_at') IS NOT NULL AND (v_gym_obj->>'created_at') != '' 
             THEN (v_gym_obj->>'created_at')::TIMESTAMPTZ ELSE now() END
    )
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        owner_name = EXCLUDED.owner_name,
        email = EXCLUDED.email,
        phone = EXCLUDED.phone,
        address = EXCLUDED.address,
        status = EXCLUDED.status,
        is_locked = EXCLUDED.is_locked,
        plan_type = EXCLUDED.plan_type,
        expiry_date = EXCLUDED.expiry_date,
        max_staff_limit = EXCLUDED.max_staff_limit,
        max_members_limit = EXCLUDED.max_members_limit;

    -- 2. Restore Attendance Settings
    IF p_backup_data->'attendance_settings' IS NOT NULL THEN
        INSERT INTO public.attendance_settings (
            gym_id, work_start_time, work_end_time, grace_period_minutes, half_day_threshold_hours
        )
        VALUES (
            v_gym_id,
            COALESCE(p_backup_data->'attendance_settings'->>'work_start_time', '06:00'),
            COALESCE(p_backup_data->'attendance_settings'->>'work_end_time', '22:00'),
            COALESCE((p_backup_data->'attendance_settings'->>'grace_period_minutes')::INT, 15),
            COALESCE((p_backup_data->'attendance_settings'->>'half_day_threshold_hours')::INT, 4)
        )
        ON CONFLICT (gym_id) DO UPDATE SET
            work_start_time = EXCLUDED.work_start_time,
            work_end_time = EXCLUDED.work_end_time,
            grace_period_minutes = EXCLUDED.grace_period_minutes,
            half_day_threshold_hours = EXCLUDED.half_day_threshold_hours;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'gym_id', v_gym_id,
        'message', 'Gym backup restored successfully'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.restore_gym_backup(JSONB) TO anon, authenticated, service_role;


-- 6. GYM SPECIFIC MONTHLY FINANCIAL PROFIT & REVENUE SUMMARY
CREATE OR REPLACE FUNCTION public.get_gym_monthly_financial_summary(
    p_gym_id UUID, 
    p_year INT, 
    p_month INT
)
RETURNS TABLE (
    total_revenue NUMERIC,
    total_expense NUMERIC,
    net_profit NUMERIC,
    transaction_count INT
) AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_rev NUMERIC := 0.0;
    v_exp NUMERIC := 0.0;
    v_count INT := 0;
BEGIN
    v_start_date := make_date(p_year, p_month, 1);
    v_end_date := (v_start_date + interval '1 month' - interval '1 day')::DATE;

    SELECT 
        COALESCE(SUM(CASE WHEN type = 'Revenue' THEN amount ELSE 0 END), 0.0),
        COALESCE(SUM(CASE WHEN type = 'Expense' THEN amount ELSE 0 END), 0.0),
        COUNT(*)::INT
    INTO v_rev, v_exp, v_count
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id
      AND transaction_date::DATE >= v_start_date
      AND transaction_date::DATE <= v_end_date;

    RETURN QUERY
    SELECT 
        v_rev AS total_revenue,
        v_exp AS total_expense,
        (v_rev - v_exp) AS net_profit,
        v_count AS transaction_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_gym_monthly_financial_summary(UUID, INT, INT) TO anon, authenticated, service_role;
