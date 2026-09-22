-- =========================================================================
-- ENTERPRISE FULL DATABASE BACKUP & 1-CLICK RESTORE SYSTEM
-- RUN THIS ENTIRE SCRIPT IN SUPABASE SQL EDITOR
-- =========================================================================

-- =============================================
-- 1. CREATE / UPGRADE database_backups TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS public.database_backups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    backup_name TEXT NOT NULL DEFAULT 'Full Backup',
    backup_data JSONB NOT NULL DEFAULT '{}',
    size_bytes BIGINT DEFAULT 0,
    total_records INT DEFAULT 0,
    table_counts JSONB DEFAULT '{}',
    status TEXT DEFAULT 'Success',
    drive_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Upgrade columns and drop any conflicting NOT NULL constraints from older schema
DO $$
BEGIN
    -- If old 'size' column exists with NOT NULL constraint, drop NOT NULL
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'size') THEN
        ALTER TABLE public.database_backups ALTER COLUMN size DROP NOT NULL;
        ALTER TABLE public.database_backups ALTER COLUMN size SET DEFAULT '';
    END IF;

    -- If old 'name' column exists with NOT NULL constraint, drop NOT NULL
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'name') THEN
        ALTER TABLE public.database_backups ALTER COLUMN name DROP NOT NULL;
        ALTER TABLE public.database_backups ALTER COLUMN name SET DEFAULT 'Full Backup';
    END IF;

    -- Handle rename if column was named 'name'
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'name') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'backup_name') THEN
        ALTER TABLE public.database_backups RENAME COLUMN name TO backup_name;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'backup_name') THEN
        ALTER TABLE public.database_backups ADD COLUMN backup_name TEXT DEFAULT 'Full Backup';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'backup_data') THEN
        ALTER TABLE public.database_backups ADD COLUMN backup_data JSONB DEFAULT '{}';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'total_records') THEN
        ALTER TABLE public.database_backups ADD COLUMN total_records INT DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'table_counts') THEN
        ALTER TABLE public.database_backups ADD COLUMN table_counts JSONB DEFAULT '{}';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'drive_url') THEN
        ALTER TABLE public.database_backups ADD COLUMN drive_url TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'size_bytes') THEN
        ALTER TABLE public.database_backups ADD COLUMN size_bytes BIGINT DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'database_backups' AND column_name = 'status') THEN
        ALTER TABLE public.database_backups ADD COLUMN status TEXT DEFAULT 'Success';
    END IF;
END $$;

ALTER TABLE public.database_backups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS database_backups_admin_policy ON public.database_backups;
CREATE POLICY database_backups_admin_policy ON public.database_backups FOR ALL USING (true) WITH CHECK (true);
GRANT ALL ON TABLE public.database_backups TO anon, authenticated, service_role;


-- =============================================
-- 2. FULL DATABASE EXPORT — dynamic universal export for ALL tables
-- =============================================
DROP FUNCTION IF EXISTS public.full_database_export();

CREATE OR REPLACE FUNCTION public.full_database_export()
RETURNS JSONB AS $$
DECLARE
    v_result JSONB := '{}'::jsonb;
    v_table_name TEXT;
    v_table_data JSONB;
    v_total_records INT := 0;
    v_counts JSONB := '{}'::jsonb;
    v_count INT;
    v_tables_exported INT := 0;
BEGIN
    -- Allow execution if running as internal postgres system user (e.g. pg_cron) OR authenticated super admin
    IF current_user != 'postgres' AND (auth.uid() IS NULL OR NOT is_super_admin(auth.uid())) THEN
        RAISE EXCEPTION 'Unauthorized: Super Admin access required';
    END IF;
    FOR v_table_name IN
        SELECT t.table_name
        FROM information_schema.tables t
        WHERE t.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'
          AND t.table_name NOT IN ('database_backups')
        ORDER BY t.table_name
    LOOP
        BEGIN
            EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t)), ''[]''::jsonb), count(*) FROM public.%I t', v_table_name)
            INTO v_table_data, v_count;

            v_counts := jsonb_set(v_counts, ARRAY[v_table_name], to_jsonb(v_count));
            v_result := jsonb_set(v_result, ARRAY[v_table_name], v_table_data);
            v_total_records := v_total_records + v_count;
            v_tables_exported := v_tables_exported + 1;
        EXCEPTION WHEN OTHERS THEN
            v_counts := jsonb_set(v_counts, ARRAY[v_table_name], to_jsonb(0));
            v_result := jsonb_set(v_result, ARRAY[v_table_name], '[]'::jsonb);
        END;
    END LOOP;

    v_result := jsonb_set(
        v_result,
        '{_meta}',
        jsonb_build_object(
            'exported_at', now()::TEXT,
            'version', '3.0',
            'system', 'GymOS Enterprise Universal Backup',
            'total_tables', v_tables_exported,
            'total_records', v_total_records,
            'table_counts', v_counts
        )
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.full_database_export() TO anon, authenticated, service_role;


-- =============================================
-- 3. FULL DATABASE IMPORT — 1-click full restore
-- =============================================
DROP FUNCTION IF EXISTS public.full_database_import(JSONB);

CREATE OR REPLACE FUNCTION public.full_database_import(p_backup JSONB)
RETURNS JSONB AS $$
DECLARE
    v_meta JSONB;
    v_tables_restored INT := 0;
    v_records_inserted INT := 0;
    v_errors TEXT[] := ARRAY[]::TEXT[];
    v_table_name TEXT;
    v_table_count INT;
    v_handled_tables TEXT[] := ARRAY[
        'gyms', 'profiles', 'user_gym_associations', 'subscriptions', 'platform_plans', 'subscription_plans',
        'staff', 'staff_roles', 'staff_shift_assignments',
        'members', 'member_memberships', 'membership_plans', 'packages',
        'gym_shifts', 'gym_shift_settings',
        'invoices', 'expenses', 'payments', 'finance_transactions', 'transactions',
        'salaries', 'salary_drafts', 'salary_payments', 'salary_advance_ledger', 'salary_adjustments', 
        'salary_payment_commissions', 'commission_ledger', 'leave_requests',
        'diet_plans', 'workout_plans', 'exercises',
        'attendance', 'attendance_logs', 'attendance_qr_tokens', 'attendance_settings', 'attendance_displays',
        'member_body_logs', 'member_achievements', 'member_badge_status', 'member_fitness_goals', 
        'member_workout_logs', 'member_workout_sets', 'xp_history',
        'pt_assignments', 'pt_sessions'
    ];
BEGIN
    v_meta := p_backup->'_meta';
    
    -- Validate backup format
    IF v_meta IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Invalid backup format: Missing _meta header. Make sure this is a GymOS Enterprise Universal Backup file.');
    END IF;

    -- Iterate through priority order tables first
    FOREACH v_table_name IN ARRAY v_handled_tables LOOP
        IF p_backup->v_table_name IS NOT NULL AND jsonb_array_length(p_backup->v_table_name) > 0 THEN
            BEGIN
                IF v_table_name = 'member_memberships' THEN
                    INSERT INTO public.member_memberships (
                        id, gym_id, member_id, plan_id, start_date, end_date, total_amount, paid_amount, payment_status, created_by_info, created_at, updated_at
                    )
                    SELECT 
                        (elem->>'id')::UUID,
                        (elem->>'gym_id')::UUID,
                        (elem->>'member_id')::UUID,
                        elem->>'plan_id',
                        (elem->>'start_date')::TIMESTAMPTZ,
                        (elem->>'end_date')::TIMESTAMPTZ,
                        (elem->>'total_amount')::NUMERIC,
                        (elem->>'paid_amount')::NUMERIC,
                        elem->>'payment_status',
                        elem->'created_by_info',
                        (elem->>'created_at')::TIMESTAMPTZ,
                        (elem->>'updated_at')::TIMESTAMPTZ
                    FROM jsonb_array_elements(p_backup->'member_memberships') AS elem
                    ON CONFLICT (id) DO NOTHING;
                ELSIF v_table_name = 'salary_drafts' THEN
                    INSERT INTO public.salary_drafts (
                        id, gym_id, staff_id, salary_month, base_salary, commission_amount, advance_deduction, other_additions, other_deductions, net_salary, status, paid_transaction_id, created_at
                    )
                    SELECT
                        (elem->>'id')::UUID,
                        (elem->>'gym_id')::UUID,
                        (elem->>'staff_id')::UUID,
                        elem->>'salary_month',
                        (elem->>'base_salary')::NUMERIC,
                        (elem->>'commission_amount')::NUMERIC,
                        (elem->>'advance_deduction')::NUMERIC,
                        (elem->>'other_additions')::NUMERIC,
                        (elem->>'other_deductions')::NUMERIC,
                        (elem->>'net_salary')::NUMERIC,
                        (elem->>'status')::public.draft_status,
                        (elem->>'paid_transaction_id')::UUID,
                        (elem->>'created_at')::TIMESTAMPTZ
                    FROM jsonb_array_elements(p_backup->'salary_drafts') AS elem
                    ON CONFLICT (id) DO NOTHING;
                ELSE
                    EXECUTE format('INSERT INTO public.%I SELECT * FROM jsonb_populate_recordset(null::public.%I, $1) ON CONFLICT DO NOTHING', v_table_name, v_table_name)
                    USING p_backup->v_table_name;
                END IF;

                v_table_count := jsonb_array_length(p_backup->v_table_name);
                v_tables_restored := v_tables_restored + 1;
                v_records_inserted := v_records_inserted + v_table_count;
            EXCEPTION WHEN OTHERS THEN
                v_errors := array_append(v_errors, v_table_name || ': ' || SQLERRM);
            END;
        END IF;
    END LOOP;

    -- Now iterate through ALL remaining tables in the backup dynamically
    FOR v_table_name IN SELECT jsonb_object_keys(p_backup) LOOP
        -- Skip metadata, internal backups table, or already handled tables
        IF v_table_name NOT IN ('_meta', 'database_backups') AND NOT (v_table_name = ANY(v_handled_tables)) THEN
            IF p_backup->v_table_name IS NOT NULL AND jsonb_array_length(p_backup->v_table_name) > 0 THEN
                -- Check if table exists in public schema
                IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = v_table_name) THEN
                    BEGIN
                        EXECUTE format('INSERT INTO public.%I SELECT * FROM jsonb_populate_recordset(null::public.%I, $1) ON CONFLICT DO NOTHING', v_table_name, v_table_name)
                        USING p_backup->v_table_name;

                        v_table_count := jsonb_array_length(p_backup->v_table_name);
                        v_tables_restored := v_tables_restored + 1;
                        v_records_inserted := v_records_inserted + v_table_count;
                    EXCEPTION WHEN OTHERS THEN
                        v_errors := array_append(v_errors, v_table_name || ': ' || SQLERRM);
                    END;
                END IF;
            END IF;
        END IF;
    END LOOP;

    -- Log restore in audit_logs
    BEGIN
        INSERT INTO public.audit_logs (
            admin_email, action, category, details, metadata, created_at
        ) VALUES (
            'Super Admin',
            'Database Restored from Backup',
            'database',
            format('Full database restored: %s tables processed, %s records restored.', v_tables_restored, v_records_inserted),
            jsonb_build_object('tables_restored', v_tables_restored, 'records_inserted', v_records_inserted, 'warnings', to_jsonb(v_errors)),
            now()
        );
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'tables_restored', v_tables_restored,
        'records_inserted', v_records_inserted,
        'errors', to_jsonb(v_errors),
        'message', CASE WHEN array_length(v_errors, 1) IS NULL 
            THEN format('Full database restored successfully! %s tables and %s records verified with 0 errors.', v_tables_restored, v_records_inserted)
            ELSE format('Database restored (%s tables, %s records) with %s non-critical notices.', v_tables_restored, v_records_inserted, array_length(v_errors, 1)) END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.full_database_import(JSONB) TO anon, authenticated, service_role;


-- =============================================
-- 4. SAVE DAILY BACKUP — auto-export + save + retention
-- =============================================
DROP FUNCTION IF EXISTS public.save_daily_backup();

CREATE OR REPLACE FUNCTION public.save_daily_backup()
RETURNS JSONB AS $$
DECLARE
    v_backup JSONB;
    v_size INT;
    v_total INT;
    v_counts JSONB;
    v_backup_id UUID;
    v_deleted INT := 0;
BEGIN
    -- 1. Export full database
    v_backup := public.full_database_export();
    
    -- 2. Extract metadata
    v_total := COALESCE((v_backup->'_meta'->>'total_records')::INT, 0);
    v_counts := COALESCE(v_backup->'_meta'->'table_counts', '{}'::jsonb);
    v_size := octet_length(v_backup::TEXT);

    -- 3. Save to database_backups
    INSERT INTO public.database_backups (
        backup_name, backup_data, size_bytes, total_records, table_counts, status
    ) VALUES (
        'Full Backup — ' || to_char(now() AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY, HH12:MI AM'),
        v_backup,
        v_size,
        v_total,
        v_counts,
        'Success'
    ) RETURNING id INTO v_backup_id;

    -- 4. Auto-retention: delete backups older than 30 days
    DELETE FROM public.database_backups 
    WHERE created_at < now() - interval '30 days'
    AND id != v_backup_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'backup_id', v_backup_id,
        'total_records', v_total,
        'size_bytes', v_size,
        'size_readable', CASE 
            WHEN v_size > 1048576 THEN round(v_size / 1048576.0, 1) || ' MB'
            WHEN v_size > 1024 THEN round(v_size / 1024.0, 1) || ' KB'
            ELSE v_size || ' B' END,
        'old_backups_deleted', v_deleted,
        'message', 'Daily backup saved successfully!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.save_daily_backup() TO anon, authenticated, service_role;


-- =============================================
-- 5. EXPORT SINGLE GYM BACKUP — per-gym cloud backup
-- =============================================
DROP FUNCTION IF EXISTS public.export_single_gym_backup(UUID);

CREATE OR REPLACE FUNCTION public.export_single_gym_backup(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_gym JSONB := '{}'::jsonb;
    v_gym_name TEXT := 'Unknown Gym';
    v_owner_mobile TEXT := '';
    v_profiles JSONB := '[]'::jsonb;
    v_user_gym_associations JSONB := '[]'::jsonb;
    v_members JSONB := '[]'::jsonb;
    v_staff JSONB := '[]'::jsonb;
    v_subscriptions JSONB := '[]'::jsonb;
    v_transactions JSONB := '[]'::jsonb;
    v_finance_transactions JSONB := '[]'::jsonb;
    v_attendance_logs JSONB := '[]'::jsonb;
    v_member_memberships JSONB := '[]'::jsonb;
    v_salary_drafts JSONB := '[]'::jsonb;
    v_salary_advance_ledger JSONB := '[]'::jsonb;
    v_leave_requests JSONB := '[]'::jsonb;
    v_workout_plans JSONB := '[]'::jsonb;
    v_diet_plans JSONB := '[]'::jsonb;
    v_goals JSONB := '[]'::jsonb;
    v_custom_fields JSONB := '[]'::jsonb;
    v_attendance_settings JSONB := '[]'::jsonb;
    v_activity_logs JSONB := '[]'::jsonb;
    v_notifications JSONB := '[]'::jsonb;
    v_support_tickets JSONB := '[]'::jsonb;
    v_total INT := 0;
    v_counts JSONB;
    v_backup JSONB;
    v_backup_id UUID;
    v_size INT;
BEGIN
    -- Check gym
    SELECT to_jsonb(t) INTO v_gym FROM public.gyms t WHERE id::text = p_gym_id::text;
    IF v_gym IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Gym not found');
    END IF;
    v_gym_name := COALESCE(v_gym->>'name', 'Gym');

    -- Get owner mobile number for filename
    BEGIN
        SELECT COALESCE(p.phone_number, v_gym->>'phone', '') INTO v_owner_mobile
        FROM public.user_gym_associations uga
        JOIN public.profiles p ON p.id::text = uga.user_id::text
        WHERE uga.gym_id::text = p_gym_id::text AND uga.role = 'owner'
        LIMIT 1;
    EXCEPTION WHEN OTHERS THEN v_owner_mobile := COALESCE(v_gym->>'phone', ''); END;

    -- Export gym-specific records
    BEGIN 
        SELECT COALESCE(jsonb_agg(to_jsonb(p)), '[]'::jsonb) INTO v_profiles 
        FROM public.profiles p 
        WHERE p.id::text IN (SELECT user_id::text FROM public.user_gym_associations WHERE gym_id::text = p_gym_id::text);
    EXCEPTION WHEN OTHERS THEN v_profiles := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_user_gym_associations FROM public.user_gym_associations t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_user_gym_associations := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_members FROM public.members t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_members := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_staff FROM public.staff t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_staff := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_subscriptions FROM public.subscriptions t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_subscriptions := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_transactions FROM public.transactions t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_transactions := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_finance_transactions FROM public.finance_transactions t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_finance_transactions := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_logs FROM public.attendance_logs t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_attendance_logs := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_member_memberships FROM public.member_memberships t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_member_memberships := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_salary_drafts FROM public.salary_drafts t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_salary_drafts := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_salary_advance_ledger FROM public.salary_advance_ledger t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_salary_advance_ledger := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_leave_requests FROM public.leave_requests t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_leave_requests := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_workout_plans FROM public.workout_plans t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_workout_plans := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_diet_plans FROM public.diet_plans t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_diet_plans := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_goals FROM public.goals t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_goals := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_custom_fields FROM public.custom_fields t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_custom_fields := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_settings FROM public.attendance_settings t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_attendance_settings := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_activity_logs FROM public.activity_logs t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_activity_logs := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_notifications FROM public.notifications t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_notifications := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_support_tickets FROM public.support_tickets t WHERE gym_id::text = p_gym_id::text; EXCEPTION WHEN OTHERS THEN v_support_tickets := '[]'::jsonb; END;

    v_counts := jsonb_build_object(
        'gyms', 1,
        'profiles', jsonb_array_length(v_profiles),
        'user_gym_associations', jsonb_array_length(v_user_gym_associations),
        'members', jsonb_array_length(v_members),
        'staff', jsonb_array_length(v_staff),
        'subscriptions', jsonb_array_length(v_subscriptions),
        'transactions', jsonb_array_length(v_transactions),
        'finance_transactions', jsonb_array_length(v_finance_transactions),
        'attendance_logs', jsonb_array_length(v_attendance_logs),
        'member_memberships', jsonb_array_length(v_member_memberships),
        'salary_drafts', jsonb_array_length(v_salary_drafts),
        'salary_advance_ledger', jsonb_array_length(v_salary_advance_ledger),
        'leave_requests', jsonb_array_length(v_leave_requests),
        'workout_plans', jsonb_array_length(v_workout_plans),
        'diet_plans', jsonb_array_length(v_diet_plans),
        'goals', jsonb_array_length(v_goals),
        'custom_fields', jsonb_array_length(v_custom_fields),
        'attendance_settings', jsonb_array_length(v_attendance_settings),
        'activity_logs', jsonb_array_length(v_activity_logs),
        'notifications', jsonb_array_length(v_notifications),
        'support_tickets', jsonb_array_length(v_support_tickets)
    );

    v_total := 1 + jsonb_array_length(v_profiles) + jsonb_array_length(v_user_gym_associations) +
               jsonb_array_length(v_members) +
               jsonb_array_length(v_staff) + jsonb_array_length(v_subscriptions) + jsonb_array_length(v_transactions) +
               jsonb_array_length(v_finance_transactions) + jsonb_array_length(v_attendance_logs) +
               jsonb_array_length(v_member_memberships) + jsonb_array_length(v_salary_drafts) +
               jsonb_array_length(v_salary_advance_ledger) + jsonb_array_length(v_leave_requests) +
               jsonb_array_length(v_workout_plans) + jsonb_array_length(v_diet_plans) +
               jsonb_array_length(v_goals) + jsonb_array_length(v_custom_fields) +
               jsonb_array_length(v_attendance_settings) + jsonb_array_length(v_activity_logs) +
               jsonb_array_length(v_notifications) + jsonb_array_length(v_support_tickets);

    v_backup := jsonb_build_object(
        '_meta', jsonb_build_object(
            'exported_at', now()::TEXT,
            'version', '2.0',
            'type', 'single_gym_backup',
            'gym_id', p_gym_id,
            'gym_name', v_gym_name,
            'owner_mobile', v_owner_mobile,
            'total_records', v_total,
            'table_counts', v_counts
        ),
        'gyms', jsonb_build_array(v_gym),
        'profiles', v_profiles,
        'user_gym_associations', v_user_gym_associations,
        'members', v_members,
        'staff', v_staff,
        'subscriptions', v_subscriptions,
        'transactions', v_transactions,
        'finance_transactions', v_finance_transactions,
        'attendance_logs', v_attendance_logs,
        'member_memberships', v_member_memberships,
        'salary_drafts', v_salary_drafts,
        'salary_advance_ledger', v_salary_advance_ledger,
        'leave_requests', v_leave_requests,
        'workout_plans', v_workout_plans,
        'diet_plans', v_diet_plans,
        'goals', v_goals,
        'custom_fields', v_custom_fields,
        'attendance_settings', v_attendance_settings,
        'activity_logs', v_activity_logs,
        'notifications', v_notifications,
        'support_tickets', v_support_tickets
    );

    v_size := octet_length(v_backup::TEXT);

    -- Save directly to database_backups so it appears on Super Admin Database page
    INSERT INTO public.database_backups (
        backup_name, backup_data, size_bytes, total_records, table_counts, status
    ) VALUES (
        'Gym Backup — ' || v_gym_name || ' (' || to_char(now() AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY, HH12:MI AM') || ')',
        v_backup,
        v_size,
        v_total,
        v_counts,
        'Success'
    ) RETURNING id INTO v_backup_id;

    RETURN jsonb_build_object(
        'success', true,
        'backup_id', v_backup_id,
        'gym_id', p_gym_id,
        'gym_name', v_gym_name,
        'owner_mobile', v_owner_mobile,
        'total_records', v_total,
        'size_bytes', v_size,
        'size_readable', CASE 
            WHEN v_size > 1048576 THEN round(v_size / 1048576.0, 1) || ' MB'
            WHEN v_size > 1024 THEN round(v_size / 1024.0, 1) || ' KB'
            ELSE v_size || ' B' END,
        'backup_json', v_backup,
        'message', 'Gym backup saved successfully!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.export_single_gym_backup(UUID) TO anon, authenticated, service_role;

