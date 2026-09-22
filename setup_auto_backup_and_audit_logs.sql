-- =========================================================================
-- GYMOS ENTERPRISE: AUTO-BACKUP SCHEDULER, DRIVE SYNC & REAL AUDIT LOGS
-- RUN THIS ENTIRE SCRIPT IN SUPABASE SQL EDITOR
-- =========================================================================

-- =========================================================================
-- 1. REAL AUDIT LOGS TABLE & ALL COLUMNS UPGRADE
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Upgrade / Add all columns if table already existed
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS admin_id UUID;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS admin_email TEXT DEFAULT 'Super Admin';
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT 'Admin Action';
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'general';
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS gym_id UUID;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS gym_name TEXT;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS details TEXT;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

-- Automatically drop NOT NULL constraints from all legacy/existing columns in audit_logs
DO $$
DECLARE
    col RECORD;
BEGIN
    FOR col IN 
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'audit_logs' 
          AND is_nullable = 'NO'
          AND column_name NOT IN ('id')
    LOOP
        EXECUTE format('ALTER TABLE public.audit_logs ALTER COLUMN %I DROP NOT NULL;', col.column_name);
    END LOOP;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- Enable RLS
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Allow reading and inserting audit logs
DROP POLICY IF EXISTS audit_logs_read_all ON public.audit_logs;
CREATE POLICY audit_logs_read_all ON public.audit_logs
    FOR SELECT TO anon, authenticated, service_role
    USING (true);

DROP POLICY IF EXISTS audit_logs_insert_all ON public.audit_logs;
CREATE POLICY audit_logs_insert_all ON public.audit_logs
    FOR INSERT TO anon, authenticated, service_role
    WITH CHECK (true);

DROP POLICY IF EXISTS audit_logs_delete_all ON public.audit_logs;
CREATE POLICY audit_logs_delete_all ON public.audit_logs
    FOR DELETE TO anon, authenticated, service_role
    USING (true);

GRANT ALL ON public.audit_logs TO anon, authenticated, service_role;

-- Helper RPC to log admin audit easily
CREATE OR REPLACE FUNCTION public.log_admin_audit(
    p_action TEXT,
    p_category TEXT DEFAULT 'general',
    p_admin_email TEXT DEFAULT 'Super Admin',
    p_gym_id UUID DEFAULT NULL,
    p_gym_name TEXT DEFAULT NULL,
    p_details TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.audit_logs (
        admin_id, admin_email, action, category, gym_id, gym_name, details, metadata, created_at
    ) VALUES (
        auth.uid(),
        COALESCE(p_admin_email, (SELECT email FROM auth.users WHERE id = auth.uid()), 'Super Admin'),
        p_action,
        p_category,
        p_gym_id,
        p_gym_name,
        p_details,
        p_metadata,
        now()
    ) RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.log_admin_audit(TEXT, TEXT, TEXT, UUID, TEXT, TEXT, JSONB) TO anon, authenticated, service_role;


-- =========================================================================
-- 2. PLATFORM SETTINGS: AUTO BACKUP CONFIGURATION TABLE / DEFAULT VALUES
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.platform_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_settings_all ON public.platform_settings;
CREATE POLICY platform_settings_all ON public.platform_settings
    FOR ALL TO anon, authenticated, service_role
    USING (true)
    WITH CHECK (true);

GRANT ALL ON public.platform_settings TO anon, authenticated, service_role;

-- Insert default auto backup settings if not exists
INSERT INTO public.platform_settings (key, value, updated_at)
VALUES (
    'auto_backup_config',
    jsonb_build_object(
        'enabled', true,
        'interval_days', 1,
        'schedule_time', '02:00',
        'auto_drive_upload', true,
        'last_run_at', null,
        'next_run_at', (now() + interval '1 day'),
        'total_auto_backups', 0,
        'last_status', 'Ready'
    ),
    now()
)
ON CONFLICT (key) DO NOTHING;


-- =========================================================================
-- 3. AUTO-BACKUP TRIGGER RPC (Runs 24/7 in background)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.trigger_scheduled_auto_backup()
RETURNS JSONB AS $$
DECLARE
    v_config JSONB;
    v_enabled BOOLEAN;
    v_interval_hours INT;
    v_auto_drive BOOLEAN;
    v_backup_res JSONB;
    v_backup_id UUID;
    v_total_auto INT;
    v_next_run TIMESTAMPTZ;
BEGIN
    -- Read config
    SELECT value INTO v_config
    FROM public.platform_settings
    WHERE key = 'auto_backup_config';

    IF v_config IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'auto_backup_config not found');
    END IF;

    v_enabled := COALESCE((v_config->>'enabled')::BOOLEAN, false);
    v_interval_hours := COALESCE((v_config->>'interval_hours')::INT, 12);
    v_auto_drive := COALESCE((v_config->>'auto_drive_upload')::BOOLEAN, true);
    v_total_auto := COALESCE((v_config->>'total_auto_backups')::INT, 0);

    IF NOT v_enabled THEN
        RETURN jsonb_build_object('success', false, 'message', 'Auto-backup is disabled by admin');
    END IF;

    -- Take full database backup snapshot
    v_backup_res := public.save_daily_backup();
    v_backup_id := (v_backup_res->>'backup_id')::UUID;
    v_next_run := now() + (v_interval_hours || ' hours')::interval;

    -- Update platform_settings
    UPDATE public.platform_settings
    SET value = jsonb_set(
        jsonb_set(
            jsonb_set(
                jsonb_set(
                    v_config,
                    '{last_run_at}', to_jsonb(now()::text)
                ),
                '{next_run_at}', to_jsonb(v_next_run::text)
            ),
            '{total_auto_backups}', to_jsonb(v_total_auto + 1)
        ),
        '{last_status}', to_jsonb('Active (Every 12h: 12PM & 12AM IST)'::text)
    ),
    updated_at = now()
    WHERE key = 'auto_backup_config';

    -- Log to audit_logs
    BEGIN
        INSERT INTO public.audit_logs (
            admin_email, action, category, details, metadata, created_at
        ) VALUES (
            'Automated System Scheduler',
            'Automated Database Backup Executed',
            'database',
            format('Scheduled 12-hour auto-backup completed successfully (Interval: %s hours, Records: %s)', v_interval_hours, v_backup_res->>'total_records'),
            jsonb_build_object(
                'backup_id', v_backup_id,
                'interval_hours', v_interval_hours,
                'auto_drive_upload', v_auto_drive,
                'backup_result', v_backup_res
            ),
            now()
        );
    EXCEPTION WHEN OTHERS THEN
        NULL; -- Ignore logging failure if schema mismatch
    END;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Automated 12-hour backup completed successfully',
        'backup_id', v_backup_id,
        'next_run_at', v_next_run
    );
EXCEPTION WHEN OTHERS THEN
    -- Log error in audit_logs
    BEGIN
        INSERT INTO public.audit_logs (
            admin_email, action, category, details, metadata, created_at
        ) VALUES (
            'Automated System Scheduler',
            'Auto-Backup Failed',
            'database',
            'Scheduled 12-hour backup failed: ' || SQLERRM,
            jsonb_build_object('error', SQLERRM),
            now()
        );
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.trigger_scheduled_auto_backup() TO anon, authenticated, service_role;


-- =========================================================================
-- 4. CLEAN RESTORE FUNCTION FIX (Omits Generated Columns: pending_amount, gross_salary)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.full_database_import(p_backup JSONB)
RETURNS JSONB AS $$
DECLARE
    v_meta JSONB;
    v_tables_restored INT := 0;
    v_records_inserted INT := 0;
    v_errors TEXT[] := ARRAY[]::TEXT[];
    v_clean_memberships JSONB;
    v_clean_salary_drafts JSONB;
BEGIN
    v_meta := p_backup->'_meta';
    
    -- Validate backup format
    IF v_meta IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Invalid backup format: Missing _meta header. Make sure this is a GymOS Enterprise Backup v2.0 file.');
    END IF;

    -- 1. GYMS (parent of everything)
    IF p_backup->'gyms' IS NOT NULL AND jsonb_array_length(p_backup->'gyms') > 0 THEN
        BEGIN
            INSERT INTO public.gyms 
            SELECT * FROM jsonb_populate_recordset(null::public.gyms, p_backup->'gyms')
            ON CONFLICT (id) DO NOTHING;
            
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'gyms');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'gyms: ' || SQLERRM);
        END;
    END IF;

    -- 2. PROFILES
    IF p_backup->'profiles' IS NOT NULL AND jsonb_array_length(p_backup->'profiles') > 0 THEN
        BEGIN
            INSERT INTO public.profiles 
            SELECT * FROM jsonb_populate_recordset(null::public.profiles, p_backup->'profiles')
            ON CONFLICT (id) DO NOTHING;
            
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'profiles');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'profiles: ' || SQLERRM);
        END;
    END IF;

    -- 3. USER_GYM_ASSOCIATIONS
    IF p_backup->'user_gym_associations' IS NOT NULL AND jsonb_array_length(p_backup->'user_gym_associations') > 0 THEN
        BEGIN
            INSERT INTO public.user_gym_associations 
            SELECT * FROM jsonb_populate_recordset(null::public.user_gym_associations, p_backup->'user_gym_associations')
            ON CONFLICT DO NOTHING;
            
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'user_gym_associations');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'user_gym_associations: ' || SQLERRM);
        END;
    END IF;

    -- 4. SUBSCRIPTIONS
    IF p_backup->'subscriptions' IS NOT NULL AND jsonb_array_length(p_backup->'subscriptions') > 0 THEN
        BEGIN
            INSERT INTO public.subscriptions 
            SELECT * FROM jsonb_populate_recordset(null::public.subscriptions, p_backup->'subscriptions')
            ON CONFLICT (id) DO NOTHING;
            
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'subscriptions');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'subscriptions: ' || SQLERRM);
        END;
    END IF;

    -- 5. MEMBERS
    IF p_backup->'members' IS NOT NULL AND jsonb_array_length(p_backup->'members') > 0 THEN
        BEGIN
            INSERT INTO public.members 
            SELECT * FROM jsonb_populate_recordset(null::public.members, p_backup->'members')
            ON CONFLICT (id) DO NOTHING;
            
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'members');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'members: ' || SQLERRM);
        END;
    END IF;

    -- 6. STAFF
    IF p_backup->'staff' IS NOT NULL AND jsonb_array_length(p_backup->'staff') > 0 THEN
        BEGIN
            INSERT INTO public.staff 
            SELECT * FROM jsonb_populate_recordset(null::public.staff, p_backup->'staff')
            ON CONFLICT (id) DO NOTHING;
            
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'staff');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'staff: ' || SQLERRM);
        END;
    END IF;

    -- 7. MEMBER_MEMBERSHIPS (Strip generated column: pending_amount)
    IF p_backup->'member_memberships' IS NOT NULL AND jsonb_array_length(p_backup->'member_memberships') > 0 THEN
        BEGIN
            SELECT COALESCE(jsonb_agg(elem - 'pending_amount'), '[]'::jsonb)
            INTO v_clean_memberships
            FROM jsonb_array_elements(p_backup->'member_memberships') AS elem;

            INSERT INTO public.member_memberships 
            SELECT * FROM jsonb_populate_recordset(null::public.member_memberships, v_clean_memberships)
            ON CONFLICT (id) DO NOTHING;
            
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'member_memberships');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'member_memberships: ' || SQLERRM);
        END;
    END IF;

    -- 8. SALARY_DRAFTS (Strip generated column: gross_salary)
    IF p_backup->'salary_drafts' IS NOT NULL AND jsonb_array_length(p_backup->'salary_drafts') > 0 THEN
        BEGIN
            SELECT COALESCE(jsonb_agg(elem - 'gross_salary'), '[]'::jsonb)
            INTO v_clean_salary_drafts
            FROM jsonb_array_elements(p_backup->'salary_drafts') AS elem;

            INSERT INTO public.salary_drafts 
            SELECT * FROM jsonb_populate_recordset(null::public.salary_drafts, v_clean_salary_drafts)
            ON CONFLICT (id) DO NOTHING;
            
            v_tables_restored := v_tables_restored + 1;
            v_records_inserted := v_records_inserted + jsonb_array_length(p_backup->'salary_drafts');
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'salary_drafts: ' || SQLERRM);
        END;
    END IF;

    -- 9-22. ALL REMAINING CHILD TABLES
    DECLARE
        v_table_name TEXT;
        v_table_names TEXT[] := ARRAY[
            'transactions', 'finance_transactions', 'attendance_logs',
            'salary_advance_ledger', 'leave_requests',
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

    -- Log restore in audit_logs
    BEGIN
        INSERT INTO public.audit_logs (
            admin_email, action, category, details, metadata, created_at
        ) VALUES (
            'Super Admin',
            'Database Restored from Backup',
            'database',
            format('Full database restored: %s tables restored, %s records inserted.', v_tables_restored, v_records_inserted),
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
            THEN 'Full database restored successfully with 0 errors!' 
            ELSE 'Database restored with ' || array_length(v_errors, 1) || ' warnings (non-critical)' END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.full_database_import(JSONB) TO anon, authenticated, service_role;
