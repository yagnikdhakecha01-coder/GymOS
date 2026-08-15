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
-- 2. FULL DATABASE EXPORT — exports ALL tables
-- =============================================
DROP FUNCTION IF EXISTS public.full_database_export();

CREATE OR REPLACE FUNCTION public.full_database_export()
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
    v_gyms JSONB := '[]'::jsonb;
    v_profiles JSONB := '[]'::jsonb;
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
    v_platform_settings JSONB := '[]'::jsonb;
    v_total INT := 0;
    v_counts JSONB;
BEGIN
    -- Export each table as JSON array (each safely caught)
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_gyms FROM public.gyms t; EXCEPTION WHEN OTHERS THEN v_gyms := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_profiles FROM public.profiles t; EXCEPTION WHEN OTHERS THEN v_profiles := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_members FROM public.members t; EXCEPTION WHEN OTHERS THEN v_members := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_staff FROM public.staff t; EXCEPTION WHEN OTHERS THEN v_staff := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_subscriptions FROM public.subscriptions t; EXCEPTION WHEN OTHERS THEN v_subscriptions := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_transactions FROM public.transactions t; EXCEPTION WHEN OTHERS THEN v_transactions := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_finance_transactions FROM public.finance_transactions t; EXCEPTION WHEN OTHERS THEN v_finance_transactions := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_logs FROM public.attendance_logs t; EXCEPTION WHEN OTHERS THEN v_attendance_logs := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_member_memberships FROM public.member_memberships t; EXCEPTION WHEN OTHERS THEN v_member_memberships := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_salary_drafts FROM public.salary_drafts t; EXCEPTION WHEN OTHERS THEN v_salary_drafts := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_salary_advance_ledger FROM public.salary_advance_ledger t; EXCEPTION WHEN OTHERS THEN v_salary_advance_ledger := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_leave_requests FROM public.leave_requests t; EXCEPTION WHEN OTHERS THEN v_leave_requests := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_workout_plans FROM public.workout_plans t; EXCEPTION WHEN OTHERS THEN v_workout_plans := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_diet_plans FROM public.diet_plans t; EXCEPTION WHEN OTHERS THEN v_diet_plans := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_goals FROM public.goals t; EXCEPTION WHEN OTHERS THEN v_goals := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_custom_fields FROM public.custom_fields t; EXCEPTION WHEN OTHERS THEN v_custom_fields := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_attendance_settings FROM public.attendance_settings t; EXCEPTION WHEN OTHERS THEN v_attendance_settings := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_activity_logs FROM public.activity_logs t; EXCEPTION WHEN OTHERS THEN v_activity_logs := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_notifications FROM public.notifications t; EXCEPTION WHEN OTHERS THEN v_notifications := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_support_tickets FROM public.support_tickets t; EXCEPTION WHEN OTHERS THEN v_support_tickets := '[]'::jsonb; END;
    BEGIN SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_platform_settings FROM public.platform_settings t; EXCEPTION WHEN OTHERS THEN v_platform_settings := '[]'::jsonb; END;

    -- Count totals
    v_counts := jsonb_build_object(
        'gyms', jsonb_array_length(v_gyms),
        'profiles', jsonb_array_length(v_profiles),
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
        'support_tickets', jsonb_array_length(v_support_tickets),
        'platform_settings', jsonb_array_length(v_platform_settings)
    );

    v_total := jsonb_array_length(v_gyms) + jsonb_array_length(v_profiles) + jsonb_array_length(v_members) +
               jsonb_array_length(v_staff) + jsonb_array_length(v_subscriptions) + jsonb_array_length(v_transactions) +
               jsonb_array_length(v_finance_transactions) + jsonb_array_length(v_attendance_logs) +
               jsonb_array_length(v_member_memberships) + jsonb_array_length(v_salary_drafts) +
               jsonb_array_length(v_salary_advance_ledger) + jsonb_array_length(v_leave_requests) +
               jsonb_array_length(v_workout_plans) + jsonb_array_length(v_diet_plans) +
               jsonb_array_length(v_goals) + jsonb_array_length(v_custom_fields) +
               jsonb_array_length(v_attendance_settings) + jsonb_array_length(v_activity_logs) +
               jsonb_array_length(v_notifications) + jsonb_array_length(v_support_tickets) +
               jsonb_array_length(v_platform_settings);

    -- Build final export payload
    v_result := jsonb_build_object(
        '_meta', jsonb_build_object(
            'exported_at', now()::TEXT,
            'version', '2.0',
            'system', 'GymOS Enterprise Backup',
            'total_records', v_total,
            'table_counts', v_counts
        ),
        'gyms', v_gyms,
        'profiles', v_profiles,
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
        'support_tickets', v_support_tickets,
        'platform_settings', v_platform_settings
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
    v_row JSONB;
BEGIN
    v_meta := p_backup->'_meta';
    
    -- Validate backup format
    IF v_meta IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Invalid backup format: Missing _meta header. Make sure this is a GymOS Enterprise Backup v2.0 file.');
    END IF;

    -- 1. GYMS (parent of everything)
    IF p_backup->'gyms' IS NOT NULL AND jsonb_array_length(p_backup->'gyms') > 0 THEN
        BEGIN
            FOR v_row IN SELECT jsonb_array_elements(p_backup->'gyms') LOOP
                INSERT INTO public.gyms SELECT * FROM jsonb_populate_record(null::public.gyms, v_row)
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name, owner_name = EXCLUDED.owner_name, email = EXCLUDED.email,
                    phone = EXCLUDED.phone, address = EXCLUDED.address, status = EXCLUDED.status,
                    is_locked = EXCLUDED.is_locked, plan_type = EXCLUDED.plan_type,
                    expiry_date = EXCLUDED.expiry_date, max_staff_limit = EXCLUDED.max_staff_limit,
                    max_members_limit = EXCLUDED.max_members_limit;
            END LOOP;
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'gyms');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'gyms: ' || SQLERRM);
        END;
    END IF;

    -- 2. PROFILES
    IF p_backup->'profiles' IS NOT NULL AND jsonb_array_length(p_backup->'profiles') > 0 THEN
        BEGIN
            FOR v_row IN SELECT jsonb_array_elements(p_backup->'profiles') LOOP
                INSERT INTO public.profiles SELECT * FROM jsonb_populate_record(null::public.profiles, v_row)
                ON CONFLICT (id) DO UPDATE SET
                    full_name = EXCLUDED.full_name, email = EXCLUDED.email,
                    phone_number = EXCLUDED.phone_number, role = EXCLUDED.role,
                    gym_id = EXCLUDED.gym_id, avatar_url = EXCLUDED.avatar_url;
            END LOOP;
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'profiles');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'profiles: ' || SQLERRM);
        END;
    END IF;

    -- 3. SUBSCRIPTIONS
    IF p_backup->'subscriptions' IS NOT NULL AND jsonb_array_length(p_backup->'subscriptions') > 0 THEN
        BEGIN
            FOR v_row IN SELECT jsonb_array_elements(p_backup->'subscriptions') LOOP
                INSERT INTO public.subscriptions SELECT * FROM jsonb_populate_record(null::public.subscriptions, v_row)
                ON CONFLICT (id) DO UPDATE SET
                    gym_id = EXCLUDED.gym_id, status = EXCLUDED.status, plan_type = EXCLUDED.plan_type;
            END LOOP;
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'subscriptions');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'subscriptions: ' || SQLERRM);
        END;
    END IF;

    -- 4. MEMBERS
    IF p_backup->'members' IS NOT NULL AND jsonb_array_length(p_backup->'members') > 0 THEN
        BEGIN
            FOR v_row IN SELECT jsonb_array_elements(p_backup->'members') LOOP
                INSERT INTO public.members SELECT * FROM jsonb_populate_record(null::public.members, v_row)
                ON CONFLICT (id) DO UPDATE SET
                    full_name = EXCLUDED.full_name, phone = EXCLUDED.phone, email = EXCLUDED.email,
                    gym_id = EXCLUDED.gym_id, status = EXCLUDED.status;
            END LOOP;
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'members');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'members: ' || SQLERRM);
        END;
    END IF;

    -- 5. STAFF
    IF p_backup->'staff' IS NOT NULL AND jsonb_array_length(p_backup->'staff') > 0 THEN
        BEGIN
            FOR v_row IN SELECT jsonb_array_elements(p_backup->'staff') LOOP
                INSERT INTO public.staff SELECT * FROM jsonb_populate_record(null::public.staff, v_row)
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name, role = EXCLUDED.role, salary = EXCLUDED.salary,
                    gym_id = EXCLUDED.gym_id;
            END LOOP;
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'staff');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'staff: ' || SQLERRM);
        END;
    END IF;

    -- 6. MEMBER_MEMBERSHIPS
    IF p_backup->'member_memberships' IS NOT NULL AND jsonb_array_length(p_backup->'member_memberships') > 0 THEN
        BEGIN
            FOR v_row IN SELECT jsonb_array_elements(p_backup->'member_memberships') LOOP
                INSERT INTO public.member_memberships SELECT * FROM jsonb_populate_record(null::public.member_memberships, v_row)
                ON CONFLICT (id) DO UPDATE SET
                    member_id = EXCLUDED.member_id, gym_id = EXCLUDED.gym_id;
            END LOOP;
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'member_memberships');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'member_memberships: ' || SQLERRM);
        END;
    END IF;

    -- 7-21. ALL REMAINING CHILD TABLES
    DECLARE
        v_table_name TEXT;
        v_table_names TEXT[] := ARRAY[
            'transactions', 'finance_transactions', 'attendance_logs',
            'salary_drafts', 'salary_advance_ledger', 'leave_requests',
            'workout_plans', 'diet_plans', 'goals', 'custom_fields',
            'attendance_settings', 'activity_logs', 'notifications',
            'support_tickets', 'platform_settings'
        ];
    BEGIN
        FOREACH v_table_name IN ARRAY v_table_names LOOP
            IF p_backup->v_table_name IS NOT NULL AND jsonb_array_length(p_backup->v_table_name) > 0 THEN
                BEGIN
                    EXECUTE format(
                        'INSERT INTO public.%I SELECT * FROM jsonb_populate_recordset(null::public.%I, $1) ON CONFLICT DO NOTHING',
                        v_table_name, v_table_name
                    ) USING p_backup->v_table_name;
                    
                    v_tables_restored := v_tables_restored + 1;
                    v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->v_table_name);
                EXCEPTION WHEN OTHERS THEN
                    v_errors := array_append(v_errors, v_table_name || ': ' || SQLERRM);
                END;
            END IF;
        END LOOP;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'tables_restored', v_tables_restored,
        'records_inserted', v_records_inserted,
        'errors', to_jsonb(v_errors),
        'message', CASE WHEN array_length(v_errors, 1) IS NULL 
            THEN 'Full database restored successfully with 0 errors!' 
            ELSE 'Database restored with ' || array_length(v_errors, 1) || ' warnings (non-critical)' END
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
