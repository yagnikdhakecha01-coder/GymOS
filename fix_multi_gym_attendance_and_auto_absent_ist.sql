-- =========================================================================
-- GYMOS: ATTENDANCE SECURITY, MULTI-GYM BRANCH ISOLATION & AUTO-ABSENT (IST)
-- =========================================================================
-- 1. Strictly enforces valid QR tokens (Dynamic or Static). No rogue fallbacks.
-- 2. Multi-gym branch isolation: Rejects members/staff scanning at other gym branches.
-- 3. Member flow: Check-in only with idempotency (no accidental check-outs on double tap).
-- 4. Status validation: Inactive/expired memberships are rejected.
-- 5. Auto-absent engine (cron_auto_mark_absent):
--    - Runs strictly in Indian Standard Time (Asia/Kolkata, UTC+5:30).
--    - Skips Sundays (Weekly Off) and declared Gym Holidays (public.holidays).
--    - Staff: Auto-marked absent 1 hour post-shift.
--    - Members: Auto-marked absent 2 hours post-closing.
-- =========================================================================

-- Ensure required columns exist on attendance_logs
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS role TEXT;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS user_type TEXT;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS member_id UUID;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS staff_id UUID;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS shift_id UUID;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS date TEXT;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS qr_type TEXT;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS late_minutes INT DEFAULT 0;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS early_exit_minutes INT DEFAULT 0;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS working_minutes INT DEFAULT 0;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS shift_status TEXT;

-- Ensure auto_mark_absent exists on attendance_settings
ALTER TABLE public.attendance_settings ADD COLUMN IF NOT EXISTS auto_mark_absent BOOLEAN DEFAULT FALSE;

-- Ensure index on attendance_logs for fast multi-gym lookups
CREATE INDEX IF NOT EXISTS idx_att_logs_gym_user_date ON public.attendance_logs (gym_id, user_id, date);
CREATE INDEX IF NOT EXISTS idx_att_logs_gym_staff_date ON public.attendance_logs (gym_id, staff_id, date);
CREATE INDEX IF NOT EXISTS idx_att_logs_gym_member_date ON public.attendance_logs (gym_id, member_id, date);

-- -------------------------------------------------------------------------
-- FUNCTION: process_qr_attendance
-- -------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.process_qr_attendance(TEXT);
DROP FUNCTION IF EXISTS public.process_qr_attendance(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.process_qr_attendance(
    p_token TEXT,
    p_user_type TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_scanner_uid UUID := auth.uid();
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;
    v_local_date DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    v_local_date_str TEXT := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'dd-MM-yyyy');

    v_token_clean TEXT := TRIM(p_token);

    -- Identified Gym & Display
    v_gym_id UUID;
    v_display_id UUID;
    v_token_expires TIMESTAMPTZ;
    v_token_used BOOLEAN;
    v_token_valid BOOLEAN := FALSE;
    v_qr_type TEXT := 'Dynamic';

    -- Gym Settings & Shift Mode
    v_settings RECORD;
    v_gym_shift_mode TEXT := 'Single Shift';

    -- User Role & Info
    v_resolved_user_type TEXT := NULL;
    v_user_name TEXT;
    v_member_id UUID;
    v_member_status TEXT;
    v_staff_id UUID;
    v_staff_status TEXT;
    v_staff_user_id UUID;

    -- Shift variables for staff
    v_shift_assignment RECORD;
    v_assigned_shift_type TEXT;
    v_single_shift_rec RECORD;
    v_single_start TIME;
    v_single_end TIME;
    v_single_dur INTERVAL;
    v_single_midpoint TIME;

    v_morning_shift_rec RECORD;
    v_evening_shift_rec RECORD;
    v_morning_log RECORD;
    v_evening_log RECORD;

    v_existing_log RECORD;
    v_log_id UUID;
    v_working_mins INT := 0;
    v_late_mins INT := 0;
    v_early_exit_mins INT := 0;
    v_status TEXT := 'Present';

    v_formatted_check_in TEXT;
    v_formatted_check_out TEXT;
BEGIN
    -- 0. Authentication Check
    IF v_scanner_uid IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User not authenticated. Please log in.');
    END IF;

    -- Token must not be empty
    IF v_token_clean IS NULL OR v_token_clean = '' THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid QR code. QR code content is empty.');
    END IF;

    -- 1. Validate QR Token (Dynamic QR from attendance_qr_tokens OR Static QR from attendance_settings)
    SELECT gym_id, display_id, expires_at, is_used
    INTO v_gym_id, v_display_id, v_token_expires, v_token_used
    FROM public.attendance_qr_tokens
    WHERE token = v_token_clean
    LIMIT 1;

    IF v_gym_id IS NOT NULL THEN
        IF (v_token_expires < now()) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has expired. Please scan the active QR code.');
        END IF;

        IF v_token_used THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has already been used. Please scan the newly generated QR code.');
        END IF;

        v_token_valid := TRUE;
        v_qr_type := 'Dynamic';

        -- Mark token used immediately to prevent reuse
        UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = v_token_clean;
    ELSE
        -- Check if it matches a static QR token in attendance_settings
        SELECT gym_id, is_enabled, method, static_qr_token, late_time_setting
        INTO v_settings
        FROM public.attendance_settings
        WHERE static_qr_token = v_token_clean
        LIMIT 1;

        IF v_settings IS NOT NULL AND v_settings.gym_id IS NOT NULL THEN
            v_gym_id := v_settings.gym_id;
            v_token_valid := TRUE;
            v_qr_type := 'Static';
        END IF;
    END IF;

    -- STRICT SECURITY: Reject completely if token does not match any gym
    IF NOT v_token_valid OR v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid or unrecognized QR Code. Please scan the official Gym QR code.');
    END IF;

    -- Check if attendance is enabled for this gym
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_gym_id;
    IF v_settings IS NOT NULL AND NOT COALESCE(v_settings.is_enabled, TRUE) THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is currently disabled by gym administration.');
    END IF;

    -- 2. Multi-Gym Branch Verification & Role Resolution
    -- If user specified 'Staff' or NULL, test staff membership first
    IF p_user_type IS NULL OR p_user_type = 'Staff' THEN
        SELECT id, name, status, user_id INTO v_staff_id, v_user_name, v_staff_status, v_staff_user_id
        FROM public.staff
        WHERE (user_id = v_scanner_uid OR id = v_scanner_uid) AND gym_id = v_gym_id
        LIMIT 1;

        IF v_staff_id IS NOT NULL THEN
            IF v_staff_status <> 'Active' THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'Staff account is inactive or invitation pending. Please contact management.');
            END IF;
            v_resolved_user_type := 'Staff';
        END IF;
    END IF;

    -- If not staff, test member membership for this specific gym branch
    IF v_resolved_user_type IS NULL AND (p_user_type IS NULL OR p_user_type = 'Member') THEN
        SELECT id, status INTO v_member_id, v_member_status
        FROM public.members
        WHERE user_id = v_scanner_uid AND gym_id = v_gym_id
        LIMIT 1;

        IF v_member_id IS NOT NULL THEN
            v_resolved_user_type := 'Member';
            SELECT COALESCE(full_name, 'Member') INTO v_user_name FROM public.profiles WHERE id = v_scanner_uid;
        END IF;
    END IF;

    -- If user was not found in THIS gym branch, check if they belong to any other gym
    IF v_resolved_user_type IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.members WHERE user_id = v_scanner_uid) OR
           EXISTS (SELECT 1 FROM public.staff WHERE user_id = v_scanner_uid OR id = v_scanner_uid) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'You are registered with another gym branch. Attendance can only be marked at your registered branch.');
        ELSE
            RETURN jsonb_build_object('success', FALSE, 'reason', 'No active membership or staff record found for this gym branch.');
        END IF;
    END IF;

    -- =========================================================================
    -- MEMBER ATTENDANCE FLOW
    -- =========================================================================
    IF v_resolved_user_type = 'Member' THEN
        -- Check membership validity
        IF v_member_status NOT IN ('Active', 'Trial') THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Membership is inactive or expired. Please contact gym reception.');
        END IF;

        -- Check if already marked today (in IST)
        SELECT * INTO v_existing_log 
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
        ORDER BY check_in DESC
        LIMIT 1;

        IF v_existing_log IS NOT NULL THEN
            -- If already marked Present/Late/etc, return already_marked = TRUE (DO NOT change to check_out!)
            IF v_existing_log.status != 'Absent' THEN
                v_formatted_check_in := to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', TRUE,
                    'user_type', 'Member',
                    'user_name', COALESCE(v_user_name, 'Member'),
                    'status', v_existing_log.status,
                    'check_in', v_formatted_check_in,
                    'attendance_date', v_existing_log.date,
                    'message', 'Attendance already marked for today at ' || v_formatted_check_in || '.'
                );
            ELSE
                -- If was marked Absent by system, update to Present upon live scan
                UPDATE public.attendance_logs
                SET check_in = now(),
                    check_out = NULL,
                    status = 'Present',
                    method = COALESCE(v_qr_type || ' QR', 'Live QR'),
                    qr_type = v_qr_type,
                    updated_at = now()
                WHERE id = v_existing_log.id;

                v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', FALSE,
                    'user_type', 'Member',
                    'user_name', COALESCE(v_user_name, 'Member'),
                    'status', 'Present',
                    'check_in', v_formatted_check_in,
                    'attendance_date', v_local_date_str,
                    'message', 'Attendance marked successfully!'
                );
            END IF;
        END IF;

        -- Insert clean Member check-in
        INSERT INTO public.attendance_logs (
            gym_id, user_id, role, user_type, member_id, date, check_in, status, method, qr_type
        ) VALUES (
            v_gym_id, v_scanner_uid, 'Member', 'Member', v_member_id, v_local_date_str, now(), 'Present', COALESCE(v_qr_type || ' QR', 'Live QR'), v_qr_type
        ) RETURNING id INTO v_log_id;

        v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
        RETURN jsonb_build_object(
            'success', TRUE,
            'already_marked', FALSE,
            'user_type', 'Member',
            'user_name', COALESCE(v_user_name, 'Member'),
            'status', 'Present',
            'check_in', v_formatted_check_in,
            'attendance_date', v_local_date_str,
            'message', 'Member attendance checked in successfully!'
        );
    END IF;

    -- =========================================================================
    -- STAFF ATTENDANCE FLOW (Single Shift & Two Shifts)
    -- =========================================================================
    IF v_resolved_user_type = 'Staff' THEN
        SELECT COALESCE(mode, 'Single Shift') INTO v_gym_shift_mode 
        FROM public.gym_shift_settings 
        WHERE gym_id = v_gym_id;

        SELECT * INTO v_shift_assignment
        FROM public.staff_shift_assignments
        WHERE staff_id = v_staff_id AND gym_id = v_gym_id AND status = 'Active'
        ORDER BY created_at DESC LIMIT 1;

        v_assigned_shift_type := COALESCE(v_shift_assignment.assignment_type, v_gym_shift_mode, 'Single Shift');
        IF v_assigned_shift_type IN ('Two Shifts', 'Both Shifts') THEN
            v_assigned_shift_type := 'Two Shifts';
        END IF;

        -- BRANCH A: SINGLE SHIFT MODE
        IF v_assigned_shift_type = 'Single Shift' THEN
            SELECT * INTO v_single_shift_rec 
            FROM public.gym_shifts 
            WHERE gym_id = v_gym_id AND shift_type = 'Single Shift'
            LIMIT 1;

            v_single_start := COALESCE(v_single_shift_rec.start_time_24h, '09:00:00'::TIME);
            v_single_end := COALESCE(v_single_shift_rec.end_time_24h, '19:00:00'::TIME);

            v_single_dur := (v_single_end - v_single_start);
            IF v_single_dur < INTERVAL '0' THEN
                v_single_dur := v_single_dur + INTERVAL '24 hours';
            END IF;
            v_single_midpoint := (v_single_start + (v_single_dur / 2))::TIME;

            SELECT * INTO v_existing_log
            FROM public.attendance_logs
            WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id)
              AND gym_id = v_gym_id 
              AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
            ORDER BY check_in ASC LIMIT 1;

            -- Check out if currently checked in
            IF v_existing_log IS NOT NULL AND v_existing_log.check_out IS NULL AND v_existing_log.status != 'Absent' THEN
                v_working_mins := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 60)::INT);
                v_early_exit_mins := 0;
                v_status := v_existing_log.status;

                IF v_local_time < v_single_end THEN
                    v_early_exit_mins := EXTRACT(EPOCH FROM (v_single_end - v_local_time)) / 60;
                END IF;

                IF v_local_time <= (v_single_midpoint + INTERVAL '30 minutes')::TIME THEN
                    v_status := 'Half Leave';
                END IF;

                UPDATE public.attendance_logs
                SET check_out = now(),
                    working_minutes = v_working_mins,
                    early_exit_minutes = v_early_exit_mins,
                    status = v_status,
                    shift_status = 'Completed',
                    updated_at = now()
                WHERE id = v_existing_log.id;

                v_formatted_check_in := to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                v_formatted_check_out := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');

                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', TRUE,
                    'user_type', 'Staff',
                    'action', 'Check Out',
                    'status', v_status,
                    'check_in', v_formatted_check_in,
                    'check_out', v_formatted_check_out,
                    'working_minutes', v_working_mins,
                    'early_exit_minutes', v_early_exit_mins,
                    'shift_status', 'Completed',
                    'message', 'Staff Check Out successful!'
                );
            END IF;

            -- Log completed already today
            IF v_existing_log IS NOT NULL AND v_existing_log.check_out IS NOT NULL THEN
                v_formatted_check_in := to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', TRUE,
                    'user_type', 'Staff',
                    'action', 'Completed',
                    'status', v_existing_log.status,
                    'check_in', v_formatted_check_in,
                    'check_out', to_char(v_existing_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM'),
                    'message', 'Staff attendance already completed for today at ' || v_formatted_check_in || '.'
                );
            END IF;

            -- New Check In for Single Shift
            v_status := 'Present';
            v_late_mins := 0;

            IF v_local_time > v_single_midpoint THEN
                v_status := 'Half Leave';
            ELSIF v_local_time > (v_single_start + INTERVAL '1 hour')::TIME THEN
                v_status := 'Late';
                v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_single_start)) / 60;
            END IF;

            INSERT INTO public.attendance_logs (
                gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
            ) VALUES (
                v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_single_shift_rec.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Live QR'), v_qr_type
            ) RETURNING id INTO v_log_id;

            v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', FALSE,
                'user_type', 'Staff',
                'action', 'Check In',
                'status', v_status,
                'check_in', v_formatted_check_in,
                'late_minutes', v_late_mins,
                'shift_status', 'Incomplete',
                'message', 'Staff Check In successful at ' || v_formatted_check_in || '!'
            );
        END IF;

        -- BRANCH B: TWO SHIFTS MODE
        IF v_assigned_shift_type = 'Two Shifts' THEN
            SELECT * INTO v_morning_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Morning Shift' LIMIT 1;
            SELECT * INTO v_evening_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Evening Shift' LIMIT 1;

            SELECT * INTO v_morning_log FROM public.attendance_logs
            WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id) AND gym_id = v_gym_id AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date) AND shift_id = v_morning_shift_rec.id LIMIT 1;

            SELECT * INTO v_evening_log FROM public.attendance_logs
            WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id) AND gym_id = v_gym_id AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date) AND shift_id = v_evening_shift_rec.id LIMIT 1;

            -- Check out active morning shift
            IF v_morning_log IS NOT NULL AND v_morning_log.check_out IS NULL AND v_morning_log.status != 'Absent' THEN
                v_working_mins := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - v_morning_log.check_in)) / 60)::INT);
                UPDATE public.attendance_logs SET check_out = now(), working_minutes = v_working_mins, shift_status = 'Completed', updated_at = now() WHERE id = v_morning_log.id;
                RETURN jsonb_build_object('success', TRUE, 'user_type', 'Staff', 'action', 'Check Out', 'shift_name', 'Morning Shift', 'message', 'Morning Shift Check Out successful!');
            END IF;

            -- Check out active evening shift
            IF v_evening_log IS NOT NULL AND v_evening_log.check_out IS NULL AND v_evening_log.status != 'Absent' THEN
                v_working_mins := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - v_evening_log.check_in)) / 60)::INT);
                UPDATE public.attendance_logs SET check_out = now(), working_minutes = v_working_mins, shift_status = 'Completed', updated_at = now() WHERE id = v_evening_log.id;
                RETURN jsonb_build_object('success', TRUE, 'user_type', 'Staff', 'action', 'Check Out', 'shift_name', 'Evening Shift', 'message', 'Evening Shift Check Out successful!');
            END IF;

            -- Morning shift check in
            IF v_morning_log IS NULL AND (v_morning_shift_rec.end_time_24h IS NULL OR v_local_time <= (v_morning_shift_rec.end_time_24h + INTERVAL '1 hour')::TIME) THEN
                v_status := 'Present';
                v_late_mins := 0;
                IF v_morning_shift_rec.start_time_24h IS NOT NULL AND v_local_time > (v_morning_shift_rec.start_time_24h + INTERVAL '1 hour')::TIME THEN
                    v_status := 'Late';
                    v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_morning_shift_rec.start_time_24h)) / 60;
                END IF;

                INSERT INTO public.attendance_logs (
                    gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
                ) VALUES (
                    v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_morning_shift_rec.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Live QR'), v_qr_type
                );

                v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object('success', TRUE, 'already_marked', FALSE, 'user_type', 'Staff', 'action', 'Check In', 'shift_name', 'Morning Shift', 'check_in', v_formatted_check_in, 'message', 'Morning Shift Check In successful!');
            END IF;

            -- Evening shift check in
            IF v_evening_log IS NULL AND (v_evening_shift_rec.end_time_24h IS NULL OR v_local_time <= (v_evening_shift_rec.end_time_24h + INTERVAL '1 hour')::TIME) THEN
                v_status := 'Present';
                v_late_mins := 0;
                IF v_evening_shift_rec.start_time_24h IS NOT NULL AND v_local_time > (v_evening_shift_rec.start_time_24h + INTERVAL '1 hour')::TIME THEN
                    v_status := 'Late';
                    v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_evening_shift_rec.start_time_24h)) / 60;
                END IF;

                INSERT INTO public.attendance_logs (
                    gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
                ) VALUES (
                    v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_evening_shift_rec.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Live QR'), v_qr_type
                );

                v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object('success', TRUE, 'already_marked', FALSE, 'user_type', 'Staff', 'action', 'Check In', 'shift_name', 'Evening Shift', 'check_in', v_formatted_check_in, 'message', 'Evening Shift Check In successful!');
            END IF;

            RETURN jsonb_build_object('success', TRUE, 'already_marked', TRUE, 'user_type', 'Staff', 'message', 'Staff attendance already recorded for today.');
        END IF;
    END IF;

    RETURN jsonb_build_object('success', FALSE, 'reason', 'Unable to process attendance request.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.process_qr_attendance(TEXT, TEXT) TO anon, authenticated, service_role;


-- -------------------------------------------------------------------------
-- FUNCTION: cron_auto_mark_absent
-- -------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.cron_auto_mark_absent();

CREATE OR REPLACE FUNCTION public.cron_auto_mark_absent()
RETURNS VOID AS $$
DECLARE
    v_local_now TIMESTAMP := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;
    v_local_date DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    
    v_gym RECORD;
    v_staff RECORD;
    v_member RECORD;
    v_shift RECORD;
    v_assignment RECORD;
    v_exists BOOLEAN;
    v_latest_shift_end TIME;
    v_trigger_timestamp TIMESTAMPTZ;
    
    v_check_date DATE;
    v_check_date_str TEXT;
BEGIN
    -- Loop through gyms where auto_mark_absent is enabled
    FOR v_gym IN 
        SELECT gym_id 
        FROM public.attendance_settings 
        WHERE auto_mark_absent = TRUE
    LOOP
        -- Check both today and yesterday to cover midnight crossovers
        FOR v_check_date IN SELECT v_local_date UNION SELECT (v_local_date - 1) LOOP
            v_check_date_str := to_char(v_check_date, 'dd-MM-yyyy');

            -- 1. SKIP SUNDAY (Weekly Off in Indian context)
            IF EXTRACT(DOW FROM v_check_date) = 0 THEN
                CONTINUE;
            END IF;

            -- 2. SKIP DECLARED GYM HOLIDAYS
            IF EXISTS (
                SELECT 1 FROM public.holidays 
                WHERE gym_id = v_gym.gym_id 
                  AND (holiday_date = v_check_date OR date = v_check_date)
            ) THEN
                CONTINUE;
            END IF;

            -- ==========================================
            -- A. STAFF AUTO-ABSENT ENGINE
            -- ==========================================
            FOR v_staff IN 
                SELECT id, user_id 
                FROM public.staff 
                WHERE gym_id = v_gym.gym_id AND status = 'Active'
            LOOP
                SELECT * INTO v_assignment 
                FROM public.staff_shift_assignments 
                WHERE staff_id = v_staff.id AND gym_id = v_gym.gym_id AND status = 'Active'
                LIMIT 1;
                
                IF v_assignment IS NOT NULL THEN
                    -- CASE A1: Both Shifts Assigned
                    IF v_assignment.assignment_type IN ('Both Shifts', 'Two Shifts') THEN
                        -- Morning Shift check
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = 'Morning Shift';
                        IF v_shift IS NOT NULL AND v_shift.end_time_24h IS NOT NULL THEN
                            v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            
                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;
                        
                        -- Evening Shift check
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = 'Evening Shift';
                        IF v_shift IS NOT NULL AND v_shift.end_time_24h IS NOT NULL THEN
                            v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            
                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;

                    -- CASE A2: Single Shift
                    ELSE
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE id = v_assignment.shift_id;
                        IF v_shift IS NULL THEN
                            SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = v_assignment.assignment_type;
                        END IF;
                        
                        IF v_shift IS NOT NULL AND v_shift.end_time_24h IS NOT NULL THEN
                            v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';

                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;
                    END IF;
                END IF;
            END LOOP;

            -- ==========================================
            -- B. MEMBER AUTO-ABSENT ENGINE
            -- ==========================================
            -- Closing time: maximum shift end time in gym, or 22:00 (10 PM IST)
            SELECT COALESCE(MAX(end_time_24h), '22:00:00'::TIME) INTO v_latest_shift_end
            FROM public.gym_shifts
            WHERE gym_id = v_gym.gym_id;

            -- Trigger at 2 hours after gym closes
            v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_latest_shift_end::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '2 hours';

            IF now() > v_trigger_timestamp THEN
                FOR v_member IN 
                    SELECT id, user_id 
                    FROM public.members 
                    WHERE gym_id = v_gym.gym_id AND status IN ('Active', 'Trial')
                LOOP
                    SELECT EXISTS (
                        SELECT 1 FROM public.attendance_logs 
                        WHERE user_id = v_member.user_id 
                          AND gym_id = v_gym.gym_id 
                          AND (date = v_check_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_check_date)
                    ) INTO v_exists;
                    
                    IF NOT v_exists THEN
                        INSERT INTO public.attendance_logs (
                            gym_id, user_id, role, user_type, member_id, date, check_in, check_out, status, method
                        ) VALUES (
                            v_gym.gym_id, v_member.user_id, 'Member', 'Member', v_member.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'System'
                        );
                    END IF;
                END LOOP;
            END IF;

        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.cron_auto_mark_absent() TO anon, authenticated, service_role;

-- Schedule cron job to run every 30 minutes if pg_cron is enabled
DO $$
BEGIN
    PERFORM cron.unschedule('mark_absent_job');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    PERFORM cron.schedule('mark_absent_job', '*/30 * * * *', 'SELECT public.cron_auto_mark_absent()');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
