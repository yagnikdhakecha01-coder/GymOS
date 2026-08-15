-- =========================================================================
-- SUPER ADMIN COMPLETE BACKUP, CASCADE DELETE & STATUS FIX MIGRATION
-- RUN THIS ENTIRE SCRIPT IN SUPABASE SQL EDITOR
-- =========================================================================

-- 1. FIX GYMS & SUBSCRIPTIONS STATUS CHECK CONSTRAINTS
ALTER TABLE public.gyms DROP CONSTRAINT IF EXISTS gyms_status_check;
ALTER TABLE public.gyms ADD CONSTRAINT gyms_status_check CHECK (
    status IN ('Active', 'active', 'Suspended', 'suspended', 'Disabled', 'disabled', 'Grace Period', 'grace_period', 'Trial', 'trial', 'free_trial', 'Expired', 'expired')
);

ALTER TABLE public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_status_check;
ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_status_check CHECK (
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

-- 4. CLEAN CASCADE DELETE GYM (Auto-unlinks users, leaves 0 dummy accounts)
CREATE OR REPLACE FUNCTION public.delete_gym_cascade(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_members_count INT := 0;
    v_staff_count INT := 0;
    v_users_count INT := 0;
BEGIN
    -- Check if gym exists
    IF NOT EXISTS (SELECT 1 FROM public.gyms WHERE id::text = p_gym_id::text) THEN
        RETURN jsonb_build_object('success', false, 'message', 'Gym not found');
    END IF;

    -- Count before deletion for summary
    BEGIN SELECT COUNT(*) INTO v_members_count FROM public.members WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN SELECT COUNT(*) INTO v_staff_count FROM public.staff WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN SELECT COUNT(DISTINCT user_id) INTO v_users_count FROM public.user_gym_associations WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Delete all child table records linked to gym_id safely with text casting
    BEGIN DELETE FROM public.finance_transactions WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.transactions WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.attendance_logs WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.attendance WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.member_memberships WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.membership_plans WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.expenses WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.pt_sessions WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.salaries WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.holidays WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.members WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.staff WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.salary_drafts WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.salary_advance_ledger WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.leave_requests WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.workout_plans WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.diet_plans WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.goals WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.custom_fields WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.attendance_settings WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.activity_logs WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.notifications WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.support_tickets WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.gym_backups WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.subscriptions WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN DELETE FROM public.user_gym_associations WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Finally delete the Gym itself
    DELETE FROM public.gyms WHERE id::text = p_gym_id::text;

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


-- 5. ONE-CLICK RESTORE GYM FROM BACKUP JSON BUNDLE (Universal 20+ table restore)
CREATE OR REPLACE FUNCTION public.restore_gym_backup(p_backup_data JSONB)
RETURNS JSONB AS $$
DECLARE
    v_gym_obj JSONB;
    v_payload JSONB := p_backup_data;
BEGIN
    -- If payload has '_meta' or 'gyms' array (Enterprise v2.0 format), route directly through full_database_import
    IF v_payload->'gyms' IS NOT NULL OR v_payload->'_meta' IS NOT NULL THEN
        IF v_payload->'_meta' IS NULL THEN
            v_payload := jsonb_set(v_payload, '{_meta}', '{"version": "2.0", "system": "GymOS Enterprise Backup"}'::jsonb);
        END IF;
        RETURN public.full_database_import(v_payload);
    END IF;

    -- Handle legacy format with single 'gym' object
    v_gym_obj := v_payload->'gym';
    IF v_gym_obj IS NULL OR v_gym_obj->>'id' IS NULL THEN
        RAISE EXCEPTION 'Invalid backup data format: Missing gym record or gyms list in JSON payload';
    END IF;

    -- Build standard enterprise payload and import
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
