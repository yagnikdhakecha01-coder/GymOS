-- ============================================================================
-- GYMOS V1: DATABASE-LEVEL INDIAN STANDARD TIME (IST) STANDARDIZATION
-- Timezone: Asia/Kolkata (UTC +05:30)
-- Safety: 100% Non-destructive. Zero live data loss.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DATABASE & ROLE-LEVEL TIMEZONE ENFORCEMENT
-- ----------------------------------------------------------------------------
-- Ensures all connections (PostgREST, RPCs, Auth, Admin, Background Workers)
-- execute natively under Indian Standard Time (Asia/Kolkata, UTC+5:30).
ALTER DATABASE postgres SET timezone TO 'Asia/Kolkata';
ALTER ROLE anon SET timezone TO 'Asia/Kolkata';
ALTER ROLE authenticated SET timezone TO 'Asia/Kolkata';
ALTER ROLE authenticator SET timezone TO 'Asia/Kolkata';
ALTER ROLE service_role SET timezone TO 'Asia/Kolkata';
ALTER ROLE postgres SET timezone TO 'Asia/Kolkata';

-- ----------------------------------------------------------------------------
-- 2. STANDARDIZE COLUMN DEFAULTS (Remove timezone('utc', now()) wrappers)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'attendance_audit_log' AND column_name = 'created_at') THEN
        ALTER TABLE public.attendance_audit_log ALTER COLUMN created_at SET DEFAULT now();
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'gym_backups' AND column_name = 'created_at') THEN
        ALTER TABLE public.gym_backups ALTER COLUMN created_at SET DEFAULT now();
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'user_settings' AND column_name = 'updated_at') THEN
        ALTER TABLE public.user_settings ALTER COLUMN updated_at SET DEFAULT now();
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'faqs' AND column_name = 'created_at') THEN
        ALTER TABLE public.faqs ALTER COLUMN created_at SET DEFAULT now();
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'workout_plans' AND column_name = 'created_at') THEN
        ALTER TABLE public.workout_plans ALTER COLUMN created_at SET DEFAULT now();
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. HOTFIX RPC: get_owner_staff_cards_v1
-- Fixes: Removed double AT TIME ZONE conversion that subtracted 5.5 hours.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_owner_staff_cards_v1(p_gym_id uuid, p_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(staff_id uuid, name text, role text, avatar text, status text, salary_pending numeric, present_days integer, leave_days integer, early_exit_count integer, last_check_in text, is_checked_in boolean, current_date_str text, is_salary_paid boolean, paid_amount numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_start_of_month DATE := date_trunc('month', p_date)::DATE;
    v_month_str TEXT := to_char(p_date, 'FMMonth YYYY');
    v_mon_short TEXT := to_char(p_date, 'Mon YYYY');
BEGIN
    RETURN QUERY
    WITH monthly_attendance AS (
        SELECT 
            s.id AS s_id,
            COUNT(DISTINCT al.check_in::DATE)::INT AS month_present,
            COUNT(DISTINCT CASE WHEN al.status IN ('Leave', 'Half Leave', 'On Leave') THEN al.check_in::DATE END)::INT AS month_leave,
            COUNT(CASE WHEN al.status = 'Early Exit' OR COALESCE(al.early_exit_minutes, 0) > 0 THEN 1 END)::INT AS month_early_exit
        FROM public.staff s
        LEFT JOIN public.attendance_logs al 
               ON (al.user_id = s.user_id OR al.user_id = s.id)
              AND al.gym_id = p_gym_id
              AND al.user_type = 'Staff'
              AND al.status IN ('Present', 'Late', 'Half Day', 'Overtime', 'Early Exit')
              AND al.check_in::DATE >= v_start_of_month
              AND al.check_in::DATE <= p_date
        WHERE s.gym_id = p_gym_id
        GROUP BY s.id
    ),
    today_attendance AS (
        SELECT DISTINCT ON (s.id)
            s.id AS s_id,
            al.check_in,
            al.check_out,
            (al.check_out IS NULL) AS checked_in
        FROM public.staff s
        JOIN public.attendance_logs al 
          ON (al.user_id = s.user_id OR al.user_id = s.id)
         AND al.gym_id = p_gym_id
         AND al.user_type = 'Staff'
         AND (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
        WHERE s.gym_id = p_gym_id
        ORDER BY s.id, al.check_in DESC
    ),
    paid_drafts AS (
        SELECT 
            s.id AS s_id,
            TRUE AS is_paid,
            GREATEST(
                COALESCE(sd.gross_salary, 0.0),
                COALESCE(sd.base_salary, s.salary, 0.0) + COALESCE(
                    NULLIF(sd.commission_amount, 0),
                    (SELECT COALESCE(SUM(cl.amount), 0.0) FROM public.commission_ledger cl WHERE cl.salary_payment_id = sd.id OR (cl.staff_id = s.id AND (cl.salary_month = v_month_str OR to_char(cl.created_at, 'FMMonth YYYY') = v_month_str))),
                    0.0
                ) + COALESCE(sd.other_additions, 0.0) - COALESCE(sd.other_deductions, 0.0),
                COALESCE(sd.net_salary, 0.0) + COALESCE(
                    NULLIF(sd.advance_deduction, 0),
                    (SELECT COALESCE(SUM(sa.recovered_amount), 0.0) FROM public.salary_advance_ledger sa WHERE sa.salary_payment_id = sd.id OR (sa.staff_id = s.id AND (sa.salary_month = v_month_str OR to_char(sa.given_date, 'FMMonth YYYY') = v_month_str))),
                    0.0
                ),
                COALESCE(tx.amount, exp.amount, 0.0) + COALESCE(
                    (SELECT COALESCE(SUM(sa.recovered_amount), 0.0) FROM public.salary_advance_ledger sa WHERE sa.staff_id = s.id AND (sa.salary_month = v_month_str OR to_char(sa.given_date, 'FMMonth YYYY') = v_month_str)),
                    0.0
                ),
                COALESCE(sd.net_salary, tx.amount, exp.amount, s.salary, 0.0)
            ) AS amount
        FROM public.staff s
        LEFT JOIN public.salary_drafts sd
               ON sd.staff_id = s.id
              AND (
                trim(lower(sd.salary_month)) = trim(lower(v_month_str))
                OR trim(lower(sd.salary_month)) = trim(lower(v_mon_short))
              )
        LEFT JOIN LATERAL (
            SELECT t.amount, t.date
            FROM public.transactions t
            WHERE t.gym_id = p_gym_id
              AND (t.category ILIKE '%Salaries%' OR t.category ILIKE '%Salary%' OR t.title ILIKE '%Salary%')
              AND t.title ILIKE '%' || s.name || '%'
              AND (to_char(t.date, 'FMMonth YYYY') = trim(v_month_str) OR to_char(t.date, 'Mon YYYY') = trim(v_mon_short))
            LIMIT 1
        ) tx ON TRUE
        LEFT JOIN LATERAL (
            SELECT e.amount, e.date
            FROM public.expenses e
            WHERE e.gym_id = p_gym_id
              AND (e.category ILIKE '%Salaries%' OR e.category ILIKE '%Salary%' OR e.title ILIKE '%Salary%')
              AND e.title ILIKE '%' || s.name || '%'
              AND (to_char(e.date, 'FMMonth YYYY') = trim(v_month_str) OR to_char(e.date, 'Mon YYYY') = trim(v_mon_short))
            LIMIT 1
        ) exp ON TRUE
        WHERE s.gym_id = p_gym_id
          AND (
            lower(sd.status::TEXT) = 'paid'
            OR sd.paid_transaction_id IS NOT NULL
            OR tx.amount IS NOT NULL
            OR exp.amount IS NOT NULL
          )
    )
    SELECT 
        s.id AS staff_id,
        s.name,
        s.role,
        COALESCE(s.avatar, '') AS avatar,
        s.status,
        CASE 
            WHEN COALESCE(pd.is_paid, FALSE) = TRUE THEN 0.0
            ELSE GREATEST(0.0, COALESCE(s.salary, 0.0) - COALESCE((
                SELECT SUM(sa.remaining_amount) 
                FROM public.salary_advance_ledger sa 
                WHERE sa.staff_id = s.id 
                  AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
                  AND (
                    trim(lower(sa.salary_month)) = trim(lower(v_month_str))
                    OR (
                      (sa.salary_month IS NULL OR sa.salary_month = '') 
                      AND to_char(sa.given_date, 'FMMonth YYYY') = trim(v_month_str)
                    )
                  )
            ), 0.0))
        END::NUMERIC AS salary_pending,
        COALESCE(ma.month_present, 0)::INT AS present_days,
        COALESCE(ma.month_leave, 0)::INT AS leave_days,
        COALESCE(ma.month_early_exit, 0)::INT AS early_exit_count,
        CASE 
            WHEN ta.check_in IS NOT NULL THEN to_char(ta.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')
            ELSE 'N/A'
        END AS last_check_in,
        COALESCE(ta.checked_in, FALSE) AS is_checked_in,
        to_char(p_date, 'DD Mon YYYY') AS current_date_str,
        COALESCE(pd.is_paid, FALSE) AS is_salary_paid,
        COALESCE(pd.amount, 0.0)::NUMERIC AS paid_amount
    FROM public.staff s
    LEFT JOIN monthly_attendance ma ON s.id = ma.s_id
    LEFT JOIN today_attendance ta ON s.id = ta.s_id
    LEFT JOIN paid_drafts pd ON s.id = pd.s_id
    WHERE s.gym_id = p_gym_id
    ORDER BY s.created_at DESC;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 4. HOTFIX RPC: process_scan_attendance
-- Fixes: Replaces 'hh:mm a' (which printed month instead of minutes) with 'HH12:MI AM'.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_scan_attendance(
    p_gym_id uuid,
    p_user_id uuid,
    p_method text,
    p_token text DEFAULT NULL::text,
    p_ssid text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_gym_id UUID;
    v_user_type TEXT;
    v_user_name TEXT;
    v_settings RECORD;
    v_token_record RECORD;
    v_today_start TIMESTAMPTZ;
    v_existing_log RECORD;
    v_status TEXT := 'Present';
    v_work_hours NUMERIC(5,2);
    v_display_id UUID;
BEGIN
    -- Get user details
    SELECT gym_id, 'Member', name INTO v_gym_id, v_user_type, v_user_name
    FROM public.members WHERE user_id = p_user_id;

    IF v_gym_id IS NULL THEN
        SELECT gym_id, 'Staff', name INTO v_gym_id, v_user_type, v_user_name
        FROM public.staff WHERE user_id = p_user_id;
    END IF;

    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User profile not linked to any Gym');
    END IF;

    -- Load Settings
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_gym_id;
    IF NOT COALESCE(v_settings.is_enabled, TRUE) THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is disabled by the owner');
    END IF;

    -- 1. WiFi check if rule matches
    IF v_settings.method IN ('WiFi Only', 'QR + WiFi', 'Static QR + WiFi') THEN
        IF p_ssid IS NULL OR p_ssid <> v_settings.wifi_ssid THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'You must be connected to the Gym WiFi (' || v_settings.wifi_ssid || ')');
        END IF;
    END IF;

    -- 2. Token validation based on method
    IF p_method = 'Dynamic QR' THEN
        SELECT * INTO v_token_record FROM public.attendance_qr_tokens WHERE token = p_token;
        IF v_token_record IS NULL THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid QR Code');
        END IF;
        IF v_token_record.is_used THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'This QR Code has already been used');
        END IF;
        IF v_token_record.expires_at < now() THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code expired. Please scan the refreshed QR.');
        END IF;
        
        v_display_id := v_token_record.display_id;
        
        -- Mark token as used
        UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
    ELSIF p_method = 'Static QR' THEN
        IF p_token <> v_settings.static_qr_token THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid Static QR Code');
        END IF;
    END IF;

    v_today_start := date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata';

    -- 3. User Role based attendance check
    IF v_user_type = 'Member' THEN
        -- Check if already marked today
        SELECT * INTO v_existing_log 
        FROM public.attendance_logs 
        WHERE user_id = p_user_id AND check_in >= v_today_start
        LIMIT 1;

        IF v_existing_log IS NOT NULL THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance already marked for today');
        END IF;

        -- Create Member Attendance (Check-in only)
        INSERT INTO public.attendance_logs (gym_id, user_id, user_type, method, display_id, check_in, status, date)
        VALUES (v_gym_id, p_user_id, 'Member', p_method, v_display_id, now(), 'Present', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'dd-MM-yyyy'));

        RETURN jsonb_build_object(
            'success', TRUE,
            'userName', v_user_name,
            'userType', 'Member',
            'action', 'Check-In',
            'checkInTime', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM'),
            'status', 'Present'
        );
    ELSE
        -- Staff Attendance (Check-in/Check-out support)
        SELECT * INTO v_existing_log 
        FROM public.attendance_logs 
        WHERE user_id = p_user_id AND check_in >= v_today_start AND check_out IS NULL
        LIMIT 1;

        IF v_existing_log IS NOT NULL THEN
            -- Check-Out
            v_work_hours := ROUND((EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 3600.0)::numeric, 2);
            
            UPDATE public.attendance_logs
            SET check_out = now(),
                working_hours = v_work_hours
            WHERE id = v_existing_log.id;

            RETURN jsonb_build_object(
                'success', TRUE,
                'userName', v_user_name,
                'userType', 'Staff',
                'action', 'Check-Out',
                'checkOutTime', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM'),
                'workingHours', v_work_hours,
                'status', v_existing_log.status
            );
        ELSE
            -- Check-In
            DECLARE
                v_limit_time TIME;
                v_current_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::time;
            BEGIN
                v_limit_time := to_timestamp(v_settings.late_time_setting, 'hh:mi AM')::time;
                IF v_current_time > v_limit_time THEN
                    v_status := 'Late';
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_status := 'Present';
            END;

            INSERT INTO public.attendance_logs (gym_id, user_id, user_type, method, display_id, check_in, status, date)
            VALUES (v_gym_id, p_user_id, 'Staff', p_method, v_display_id, now(), v_status, to_char(now() AT TIME ZONE 'Asia/Kolkata', 'dd-MM-yyyy'));

            RETURN jsonb_build_object(
                'success', TRUE,
                'userName', v_user_name,
                'userType', 'Staff',
                'action', 'Check-In',
                'checkInTime', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM'),
                'status', v_status
            );
        END IF;
    END IF;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 5. HOTFIX RPC: process_daily_absences_and_leaves
-- Fixes: Creates explicit IST timestamps for zero-hour entries instead of unzoned.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_daily_absences_and_leaves()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_staff RECORD;
    v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    v_today_str TEXT := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'DD-MM-YYYY');
    v_logs_count INT;
    v_leave_record RECORD;
    v_status TEXT;
    v_midnight_ist TIMESTAMPTZ := ((v_today::text || ' 00:00:00')::TIMESTAMP AT TIME ZONE 'Asia/Kolkata');
BEGIN
    FOR v_staff IN SELECT * FROM public.staff WHERE status = 'Active' LOOP
        -- Count how many shifts the staff worked today
        SELECT COUNT(*) INTO v_logs_count
        FROM public.attendance_logs
        WHERE staff_id = v_staff.id 
          AND (date = v_today_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_today);

        -- Check if they had an approved leave for today
        SELECT * INTO v_leave_record
        FROM public.leave_requests
        WHERE staff_id = v_staff.id 
          AND status = 'Approved' 
          AND v_today BETWEEN start_date AND end_date
        LIMIT 1;

        v_status := NULL;

        IF v_leave_record IS NOT NULL THEN
            -- Had a leave request
            IF v_logs_count = 1 AND v_staff.shift IN ('Two Shifts', 'Both Shifts') THEN
                v_status := 'Half Leave';
            ELSIF v_logs_count = 0 THEN
                v_status := 'Leave';
            END IF;
        ELSE
            -- No leave request
            IF v_logs_count = 1 AND v_staff.shift IN ('Two Shifts', 'Both Shifts') THEN
                v_status := 'Half Day';
            ELSIF v_logs_count = 0 THEN
                v_status := 'Absent';
            END IF;
        END IF;

        -- Insert the missing log if needed
        IF v_status IS NOT NULL THEN
            INSERT INTO public.attendance_logs (
                id, gym_id, user_id, staff_id, role, user_type, date, check_in, status, check_out, method, working_minutes
            ) VALUES (
                gen_random_uuid(), v_staff.gym_id, v_staff.user_id, v_staff.id, v_staff.role, 'Staff', v_today_str, 
                v_midnight_ist, v_status, v_midnight_ist, 'System Auto', 0
            );
        END IF;
    END LOOP;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 6. HOTFIX RPC: fn_ensure_shift_absent
-- Fixes: Clean constructor for IST TIMESTAMPTZ.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ensure_shift_absent(
    p_gym_id uuid,
    p_user_id uuid,
    p_staff_id uuid,
    p_target_date date,
    p_shift_id uuid DEFAULT NULL::uuid,
    p_shift_index integer DEFAULT 1,
    p_shift_start time without time zone DEFAULT NULL::time without time zone,
    p_shift_end time without time zone DEFAULT NULL::time without time zone
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    v_date_str TEXT := to_char(p_target_date, 'dd-MM-yyyy');
    v_log_id UUID;
    v_start TIME := COALESCE(p_shift_start, p_shift_end, '10:00:00'::TIME);
    v_cutoff TIME;
    v_check_in_ts TIMESTAMPTZ;
    v_check_out_ts TIMESTAMPTZ;
BEGIN
    IF p_shift_start IS NULL AND p_shift_end IS NULL THEN
        RETURN NULL;
    END IF;

    -- Cutoff is 1 hour AFTER shift_start time (e.g. 10:00 AM start -> cutoff 11:00 AM)
    v_cutoff := (v_start + INTERVAL '1 hour')::TIME;

    IF p_target_date = v_local_date THEN
        -- If current local time has NOT passed shift_start + 1hr, DO NOT mark absent!
        IF v_local_time < v_cutoff THEN
            RETURN NULL;
        END IF;
    ELSIF p_target_date > v_local_date THEN
        -- Future date: never mark absent
        RETURN NULL;
    END IF;

    -- Check if log already exists for this date and shift
    SELECT al.id INTO v_log_id
    FROM public.attendance_logs al
    WHERE al.gym_id = p_gym_id
      AND (al.staff_id = p_staff_id OR al.user_id = p_user_id)
      AND (
          (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_target_date
          OR al.date = v_date_str
          OR al.date = to_char(p_target_date, 'YYYY-MM-DD')
      )
      AND (
          (p_shift_id IS NOT NULL AND al.shift_id = p_shift_id)
          OR (p_shift_id IS NULL AND COALESCE(al.shift_index, 1) = COALESCE(p_shift_index, 1))
      )
    ORDER BY al.check_in ASC
    LIMIT 1;

    IF v_log_id IS NOT NULL THEN
        RETURN v_log_id;
    END IF;

    v_check_in_ts := ((p_target_date::TEXT || ' ' || v_start::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata');
    v_check_out_ts := ((p_target_date::TEXT || ' ' || COALESCE(p_shift_end, v_start)::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata');

    -- Insert absent log
    INSERT INTO public.attendance_logs (
        gym_id, user_id, role, user_type, staff_id, shift_id, shift_index,
        date, check_in, check_out, status, shift_status, working_minutes, method, qr_type
    ) VALUES (
        p_gym_id,
        p_user_id,
        'Staff',
        'Staff',
        p_staff_id,
        p_shift_id,
        COALESCE(p_shift_index, 1),
        v_date_str,
        v_check_in_ts,
        v_check_out_ts,
        'Absent',
        'Completed',
        0,
        'Auto-Absent',
        'manual'
    ) RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$function$;

-- ----------------------------------------------------------------------------
-- 7. RESCHEDULE PG_CRON JOBS TO INDIAN STANDARD TIME
-- Note: Supabase pg_cron runs in GMT/UTC.
-- 23:59 IST = 18:29 UTC (29 18 * * *)
-- 06:30 AM & 06:30 PM IST = 01:00 UTC & 13:00 UTC (0 1,13 * * *)
-- ----------------------------------------------------------------------------
SELECT cron.alter_job(1, schedule := '29 18 * * *');
SELECT cron.alter_job(3, schedule := '0 1,13 * * *');

-- ----------------------------------------------------------------------------
-- 8. HOTFIX RPC: get_gym_rule_agreements & submit_member_rule_agreement
-- Fixes: Formats agreed_at and created_at in IST without offset so Flutter DateFormat
-- formats the exact Indian Standard Time instead of falling back to UTC.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_gym_rule_agreements(p_gym_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', id,
                'gym_id', gym_id,
                'member_id', member_id,
                'user_id', user_id,
                'member_name', member_name,
                'member_phone', member_phone,
                'rules_version', rules_version,
                'language', language,
                'agreed', agreed,
                'agreed_at', to_char(agreed_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'device_info', device_info,
                'created_at', to_char(created_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS')
            ) ORDER BY agreed_at DESC
        ),
        '[]'::jsonb
    ) INTO v_result
    FROM public.member_rule_agreements
    WHERE gym_id = p_gym_id;

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_member_rule_agreement(
    p_gym_id uuid,
    p_member_id uuid,
    p_user_id uuid DEFAULT NULL::uuid,
    p_member_name text DEFAULT 'Member'::text,
    p_member_phone text DEFAULT ''::text,
    p_rules_version integer DEFAULT 1,
    p_language text DEFAULT 'en'::text,
    p_device_info text DEFAULT 'Mobile App'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_record RECORD;
    v_uid UUID;
    v_name TEXT;
    v_phone TEXT;
BEGIN
    v_uid := COALESCE(p_user_id, auth.uid());
    
    SELECT name, phone INTO v_name, v_phone FROM public.members WHERE id = p_member_id;
    IF p_member_name IS NULL OR p_member_name = '' OR p_member_name = 'Member' THEN
        p_member_name := COALESCE(v_name, 'Member');
    END IF;
    IF p_member_phone IS NULL OR p_member_phone = '' THEN
        p_member_phone := COALESCE(v_phone, '');
    END IF;

    INSERT INTO public.member_rule_agreements (
        gym_id,
        member_id,
        user_id,
        member_name,
        member_phone,
        rules_version,
        language,
        agreed,
        agreed_at,
        device_info
    ) VALUES (
        p_gym_id,
        p_member_id,
        v_uid,
        p_member_name,
        p_member_phone,
        COALESCE(p_rules_version, 1),
        COALESCE(p_language, 'en'),
        TRUE,
        NOW(),
        COALESCE(p_device_info, 'Mobile App')
    )
    ON CONFLICT (gym_id, member_id, rules_version)
    DO UPDATE SET
        user_id = COALESCE(EXCLUDED.user_id, member_rule_agreements.user_id),
        member_name = EXCLUDED.member_name,
        member_phone = EXCLUDED.member_phone,
        language = EXCLUDED.language,
        agreed = TRUE,
        agreed_at = NOW(),
        device_info = EXCLUDED.device_info
    RETURNING * INTO v_record;

    RETURN jsonb_build_object(
        'id', v_record.id,
        'gym_id', v_record.gym_id,
        'member_id', v_record.member_id,
        'user_id', v_record.user_id,
        'member_name', v_record.member_name,
        'member_phone', v_record.member_phone,
        'rules_version', v_record.rules_version,
        'language', v_record.language,
        'agreed', v_record.agreed,
        'agreed_at', to_char(v_record.agreed_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS'),
        'device_info', v_record.device_info,
        'created_at', to_char(v_record.created_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS')
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_gym_rule_agreements(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_member_rule_agreement(uuid, uuid, uuid, text, text, integer, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_super_admin(uuid) TO anon, authenticated, service_role;

