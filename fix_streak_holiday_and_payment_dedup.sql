-- =========================================================================
-- GYMOS: STREAK PRESERVATION, HOLIDAY CALENDAR, STAFF OFF-DAY & PAYMENT CLEANUP
-- =========================================================================

-- 1. Helper Function: fn_is_member_excused_day
-- Returns TRUE if the date is a Sunday, a Gym Holiday, or a Workout Plan Rest Day.
CREATE OR REPLACE FUNCTION public.fn_is_member_excused_day(
    p_gym_id UUID,
    p_assigned_workout_id TEXT,
    p_date DATE
)
RETURNS BOOLEAN AS $$
DECLARE
    v_day_name TEXT := TRIM(to_char(p_date, 'Day')); -- e.g. 'Sunday', 'Monday'
    v_is_sunday BOOLEAN := (EXTRACT(DOW FROM p_date) = 0);
    v_is_holiday BOOLEAN := FALSE;
    v_workout_schedule JSONB;
    v_day_list JSONB;
    v_first_title TEXT;
BEGIN
    -- 1. Sundays are always excused / weekly holidays
    IF v_is_sunday THEN
        RETURN TRUE;
    END IF;

    -- 2. Check if gym holiday declared in holidays table
    IF p_gym_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM public.holidays
            WHERE gym_id = p_gym_id
              AND (holiday_date = p_date OR date = p_date)
        ) INTO v_is_holiday;

        IF v_is_holiday THEN
            RETURN TRUE;
        END IF;
    END IF;

    -- 3. Check member's assigned workout plan schedule
    IF p_assigned_workout_id IS NOT NULL AND p_assigned_workout_id <> '' THEN
        SELECT schedule::JSONB INTO v_workout_schedule
        FROM public.workout_plans
        WHERE id::TEXT = p_assigned_workout_id;

        IF v_workout_schedule IS NOT NULL AND jsonb_typeof(v_workout_schedule) = 'object' THEN
            v_day_list := v_workout_schedule -> v_day_name;
            IF v_day_list IS NULL OR jsonb_typeof(v_day_list) != 'array' OR jsonb_array_length(v_day_list) = 0 THEN
                -- If no exercises scheduled for this day, it is a Rest Day
                RETURN TRUE;
            ELSE
                v_first_title := lower(COALESCE((v_day_list -> 0 ->> 'title'), ''));
                IF v_first_title LIKE '%rest%' OR v_first_title LIKE '%holiday%' OR v_first_title LIKE '%off%' THEN
                    RETURN TRUE;
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.fn_is_member_excused_day(UUID, TEXT, DATE) TO anon, authenticated, service_role;


-- 2. Upgrade get_member_attendance_streak_v1
-- Preserves streak across Sundays, Gym Holidays, and Workout Plan Rest Days.
-- Does NOT reset streak to 0 while today is currently in progress.
CREATE OR REPLACE FUNCTION public.get_member_attendance_streak_v1(
    p_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_local_now TIMESTAMP := now() AT TIME ZONE 'Asia/Kolkata';
    v_today DATE := v_local_now::DATE;
    v_today_str TEXT := to_char(v_today, 'DD-MM-YYYY');
    v_monday DATE := date_trunc('week', v_local_now)::DATE;
    v_date DATE;
    v_date_str TEXT;
    v_week_attendance BOOLEAN[] := ARRAY[]::BOOLEAN[];
    v_week_dates INT[] := ARRAY[]::INT[];
    v_exists BOOLEAN;

    v_member_id UUID;
    v_gym_id UUID;
    v_assigned_workout_id TEXT;

    v_streak INT := 0;
    v_last_streak INT := 0;
    v_check_date DATE;
    v_check_date_str TEXT;
    v_has_today BOOLEAN := FALSE;
    v_today_excused BOOLEAN := FALSE;
    v_is_excused BOOLEAN := FALSE;
BEGIN
    -- Resolve Member Record
    SELECT id, gym_id, assigned_workout_id
    INTO v_member_id, v_gym_id, v_assigned_workout_id
    FROM public.members
    WHERE user_id = p_user_id OR id = p_user_id
    LIMIT 1;

    -- 1. Generate Weekly Attendance Checklist (Monday to Sunday)
    FOR i IN 0..6 LOOP
        v_date := v_monday + i;
        v_date_str := to_char(v_date, 'DD-MM-YYYY');

        SELECT EXISTS (
            SELECT 1 FROM public.attendance_logs
            WHERE (user_id = p_user_id OR member_id = v_member_id)
              AND (date = v_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_date)
              AND status NOT IN ('Absent', 'On Leave', 'Leave')
        ) INTO v_exists;

        v_week_attendance := array_append(v_week_attendance, v_exists);
        v_week_dates := array_append(v_week_dates, extract(day from v_date)::INT);
    END LOOP;

    -- 2. Check if member checked in today
    SELECT EXISTS (
        SELECT 1 FROM public.attendance_logs
        WHERE (user_id = p_user_id OR member_id = v_member_id)
          AND (date = v_today_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_today)
          AND status NOT IN ('Absent', 'On Leave', 'Leave')
    ) INTO v_has_today;

    -- Check if today is an excused day (Sunday, Gym Holiday, or Rest Day)
    v_today_excused := public.fn_is_member_excused_day(v_gym_id, v_assigned_workout_id, v_today);

    IF v_has_today THEN
        v_streak := 1;
        v_check_date := v_today - 1;
    ELSE
        -- Member has not checked in today yet.
        -- We do NOT zero out the streak; we check consecutive days backward starting from yesterday!
        v_streak := 0;
        v_check_date := v_today - 1;
    END IF;

    -- 3. Accumulate Streak Backward (Up to 365 Days)
    LOOP
        IF v_check_date < (v_today - 365) THEN
            EXIT;
        END IF;

        v_check_date_str := to_char(v_check_date, 'DD-MM-YYYY');
        v_is_excused := public.fn_is_member_excused_day(v_gym_id, v_assigned_workout_id, v_check_date);

        SELECT EXISTS (
            SELECT 1 FROM public.attendance_logs
            WHERE (user_id = p_user_id OR member_id = v_member_id)
              AND (date = v_check_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_check_date)
              AND status NOT IN ('Absent', 'On Leave', 'Leave')
        ) INTO v_exists;

        IF v_exists THEN
            v_streak := v_streak + 1;
            v_check_date := v_check_date - 1;
        ELSIF v_is_excused THEN
            -- Off-day (Sunday, Holiday, or Workout Plan Rest Day) skipped without breaking streak!
            v_check_date := v_check_date - 1;
        ELSE
            -- Normal workout day was missed! Streak stops here.
            EXIT;
        END IF;
    END LOOP;

    -- Fetch last_streak from member_achievements
    IF v_member_id IS NOT NULL THEN
        SELECT COALESCE(last_streak, 0) INTO v_last_streak
        FROM public.member_achievements
        WHERE member_id = v_member_id;

        -- Update achievements table
        UPDATE public.member_achievements
        SET consecutive_attendance = v_streak,
            never_miss_streak = CASE WHEN v_streak > COALESCE(never_miss_streak, 0) THEN v_streak ELSE never_miss_streak END,
            updated_at = now()
        WHERE member_id = v_member_id;
    END IF;

    RETURN jsonb_build_object(
        'current_streak', v_streak,
        'last_streak', COALESCE(v_last_streak, 0),
        'week_attendance', to_jsonb(v_week_attendance),
        'week_dates', to_jsonb(v_week_dates)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_member_attendance_streak_v1(UUID) TO anon, authenticated, service_role;


-- 3. Upgrade process_qr_attendance with Sunday & Holiday Off-Day Protection
-- On Sundays or declared Gym Holidays, staff scans are ALWAYS marked 'Present' with late_minutes = 0.
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

    -- User Role & Info
    v_resolved_user_type TEXT := NULL;
    v_user_name TEXT;
    v_member_id UUID;
    v_member_status TEXT;
    v_staff_id UUID;
    v_staff_status TEXT;
    v_staff_rec RECORD;

    -- Shift variables for staff
    v_assigned_shift_type TEXT := 'Single Shift';
    v_s1_start TIME;
    v_s1_end TIME;
    v_s2_start TIME;
    v_s2_end TIME;
    v_midpoint TIME;
    v_dur INTERVAL;

    v_morning_shift_rec RECORD;
    v_evening_shift_rec RECORD;
    v_single_shift_rec RECORD;

    v_existing_log RECORD;
    v_log_id UUID;
    v_working_mins INT := 0;
    v_late_mins INT := 0;
    v_early_exit_mins INT := 0;
    v_status TEXT := 'Present';

    v_formatted_check_in TEXT;
    v_formatted_check_out TEXT;
    v_mins_since_check_in NUMERIC;

    v_is_sunday BOOLEAN := (EXTRACT(DOW FROM v_local_date) = 0);
    v_is_holiday BOOLEAN := FALSE;
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

    -- Check if today is a gym holiday
    SELECT EXISTS (
        SELECT 1 FROM public.holidays 
        WHERE gym_id = v_gym_id 
          AND (holiday_date = v_local_date OR date = v_local_date)
    ) INTO v_is_holiday;

    -- Check if attendance is enabled for this gym
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_gym_id;
    IF v_settings IS NOT NULL AND NOT COALESCE(v_settings.is_enabled, TRUE) THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is currently disabled by gym administration.');
    END IF;

    -- 2. Multi-Gym Branch Verification & Role Resolution
    IF p_user_type IS NULL OR p_user_type = 'Staff' THEN
        SELECT s.* INTO v_staff_rec
        FROM public.staff s
        WHERE (s.user_id = v_scanner_uid OR s.id = v_scanner_uid) AND s.gym_id = v_gym_id
        LIMIT 1;

        IF v_staff_rec.id IS NOT NULL THEN
            IF v_staff_rec.status <> 'Active' THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'Staff account is inactive or invitation pending. Please contact management.');
            END IF;
            v_staff_id := v_staff_rec.id;
            v_user_name := v_staff_rec.name;
            v_resolved_user_type := 'Staff';
        END IF;
    END IF;

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
    -- MEMBER ATTENDANCE FLOW (Idempotent Check-in)
    -- =========================================================================
    IF v_resolved_user_type = 'Member' THEN
        IF v_member_status NOT IN ('Active', 'Trial') THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Membership is inactive or expired. Please contact gym reception.');
        END IF;

        SELECT * INTO v_existing_log 
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
        ORDER BY check_in DESC
        LIMIT 1;

        IF v_existing_log IS NOT NULL THEN
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
    -- STAFF ATTENDANCE FLOW (Owner-Configured Timings + 5-min Cooldown + Sunday/Holiday Protection)
    -- =========================================================================
    IF v_resolved_user_type = 'Staff' THEN
        -- Shift mode from staff profile
        IF lower(COALESCE(v_staff_rec.shift_type, '')) IN ('both', 'two')
           OR lower(COALESCE(v_staff_rec.shift, '')) LIKE '%both%'
           OR lower(COALESCE(v_staff_rec.shift, '')) LIKE '%two%' THEN
            v_assigned_shift_type := 'Two Shifts';
        ELSE
            v_assigned_shift_type := 'Single Shift';
        END IF;

        -- Parse owner-configured shift times
        v_s1_start := public.fn_parse_12h_time(v_staff_rec.shift1_start);
        v_s1_end := public.fn_parse_12h_time(v_staff_rec.shift1_end);
        v_s2_start := public.fn_parse_12h_time(v_staff_rec.shift2_start);
        v_s2_end := public.fn_parse_12h_time(v_staff_rec.shift2_end);

        -- Lookup gym shifts for fallback IDs and times
        SELECT * INTO v_single_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Single Shift' LIMIT 1;
        SELECT * INTO v_morning_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Morning Shift' LIMIT 1;
        SELECT * INTO v_evening_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Evening Shift' LIMIT 1;

        -- Prioritize staff profile custom timings
        v_s1_start := COALESCE(v_s1_start, v_single_shift_rec.start_time_24h, '09:00:00'::TIME);
        v_s1_end := COALESCE(v_s1_end, v_single_shift_rec.end_time_24h, '18:00:00'::TIME);
        v_s2_start := COALESCE(v_s2_start, v_evening_shift_rec.start_time_24h, '17:00:00'::TIME);
        v_s2_end := COALESCE(v_s2_end, v_evening_shift_rec.end_time_24h, '22:00:00'::TIME);

        -- ---------------------------------------------------------------------
        -- BRANCH A: SINGLE SHIFT MODE
        -- ---------------------------------------------------------------------
        IF v_assigned_shift_type = 'Single Shift' THEN
            v_dur := (v_s1_end - v_s1_start);
            IF v_dur < INTERVAL '0' THEN v_dur := v_dur + INTERVAL '24 hours'; END IF;
            v_midpoint := (v_s1_start + (v_dur / 2))::TIME;

            SELECT * INTO v_existing_log
            FROM public.attendance_logs
            WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id)
              AND gym_id = v_gym_id 
              AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
            ORDER BY check_in ASC LIMIT 1;

            -- Active check-in exists: CHECK OUT with 5-minute cooldown
            IF v_existing_log IS NOT NULL AND v_existing_log.check_out IS NULL AND v_existing_log.status != 'Absent' THEN
                v_mins_since_check_in := EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 60;

                -- COOLDOWN PROTECTION: If scanned within 5 minutes of check-in, do NOT check out!
                IF v_mins_since_check_in < 5 THEN
                    v_formatted_check_in := to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    RETURN jsonb_build_object(
                        'success', TRUE,
                        'already_marked', TRUE,
                        'user_type', 'Staff',
                        'action', 'Check In',
                        'status', v_existing_log.status,
                        'check_in', v_formatted_check_in,
                        'message', 'You already checked in at ' || v_formatted_check_in || '. Check-out is available after your shift.'
                    );
                END IF;

                -- Perform Legitimate Check Out
                v_working_mins := GREATEST(0, FLOOR(v_mins_since_check_in)::INT);
                v_early_exit_mins := 0;
                v_status := v_existing_log.status;

                -- On Sundays or Gym Holidays, never mark early exit or penalty
                IF NOT v_is_sunday AND NOT v_is_holiday THEN
                    IF v_local_time < v_s1_end THEN
                        v_early_exit_mins := EXTRACT(EPOCH FROM (v_s1_end - v_local_time)) / 60;
                    END IF;

                    IF v_local_time <= (v_midpoint + INTERVAL '30 minutes')::TIME THEN
                        v_status := 'Half Leave';
                    END IF;
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

            -- On Sundays or Gym Holidays, staff is ALWAYS 'Present' with 0 late minutes!
            IF NOT v_is_sunday AND NOT v_is_holiday THEN
                IF v_local_time > v_midpoint THEN
                    v_status := 'Half Leave';
                ELSIF v_local_time > (v_s1_start + INTERVAL '1 hour')::TIME THEN
                    v_status := 'Late';
                    v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_s1_start)) / 60;
                END IF;
            END IF;

            INSERT INTO public.attendance_logs (
                gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
            ) VALUES (
                v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, COALESCE(v_single_shift_rec.id, gen_random_uuid()), v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Live QR'), v_qr_type
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

        -- ---------------------------------------------------------------------
        -- BRANCH B: TWO SHIFTS MODE
        -- ---------------------------------------------------------------------
        IF v_assigned_shift_type = 'Two Shifts' THEN
            SELECT * INTO v_morning_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Morning Shift' LIMIT 1;
            SELECT * INTO v_evening_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Evening Shift' LIMIT 1;

            SELECT * INTO v_existing_log FROM public.attendance_logs
            WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id) AND gym_id = v_gym_id
              AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
              AND check_out IS NULL AND status != 'Absent'
            LIMIT 1;

            -- Check Out open shift with 5-minute cooldown
            IF v_existing_log IS NOT NULL THEN
                v_mins_since_check_in := EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 60;
                IF v_mins_since_check_in < 5 THEN
                    v_formatted_check_in := to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    RETURN jsonb_build_object(
                        'success', TRUE,
                        'already_marked', TRUE,
                        'user_type', 'Staff',
                        'action', 'Check In',
                        'status', v_existing_log.status,
                        'check_in', v_formatted_check_in,
                        'message', 'You already checked in at ' || v_formatted_check_in || '. Check-out is available after your shift.'
                    );
                END IF;

                v_working_mins := GREATEST(0, FLOOR(v_mins_since_check_in)::INT);
                UPDATE public.attendance_logs
                SET check_out = now(), working_minutes = v_working_mins, shift_status = 'Completed', updated_at = now()
                WHERE id = v_existing_log.id;

                RETURN jsonb_build_object('success', TRUE, 'user_type', 'Staff', 'action', 'Check Out', 'message', 'Shift Check Out successful!');
            END IF;

            -- Morning shift check in (before morning shift end + 1 hr)
            IF v_local_time <= (v_s1_end + INTERVAL '1 hour')::TIME THEN
                v_status := 'Present';
                v_late_mins := 0;
                IF NOT v_is_sunday AND NOT v_is_holiday THEN
                    IF v_local_time > (v_s1_start + INTERVAL '1 hour')::TIME THEN
                        v_status := 'Late';
                        v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_s1_start)) / 60;
                    END IF;
                END IF;

                INSERT INTO public.attendance_logs (
                    gym_id, user_id, role, user_type, staff_id, shift_id, shift_index, date, check_in, status, shift_status, late_minutes, method, qr_type
                ) VALUES (
                    v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, COALESCE(v_morning_shift_rec.id, gen_random_uuid()), 1, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Live QR'), v_qr_type
                );

                v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object('success', TRUE, 'already_marked', FALSE, 'user_type', 'Staff', 'action', 'Check In', 'shift_name', 'Morning Shift', 'check_in', v_formatted_check_in, 'message', 'Morning Shift Check In successful!');
            ELSE
                -- Evening shift check in
                v_status := 'Present';
                v_late_mins := 0;
                IF NOT v_is_sunday AND NOT v_is_holiday THEN
                    IF v_local_time > (v_s2_start + INTERVAL '1 hour')::TIME THEN
                        v_status := 'Late';
                        v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_s2_start)) / 60;
                    END IF;
                END IF;

                INSERT INTO public.attendance_logs (
                    gym_id, user_id, role, user_type, staff_id, shift_id, shift_index, date, check_in, status, shift_status, late_minutes, method, qr_type
                ) VALUES (
                    v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, COALESCE(v_evening_shift_rec.id, gen_random_uuid()), 2, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Live QR'), v_qr_type
                );

                v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object('success', TRUE, 'already_marked', FALSE, 'user_type', 'Staff', 'action', 'Check In', 'shift_name', 'Evening Shift', 'check_in', v_formatted_check_in, 'message', 'Evening Shift Check In successful!');
            END IF;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', FALSE, 'reason', 'Unable to process attendance request.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.process_qr_attendance(TEXT, TEXT) TO anon, authenticated, service_role;


-- 4. Clean up duplicate membership_payments
-- Delete duplicate rows where (member_membership_id, amount, payment_date) are identical, keeping the earliest created row.
DELETE FROM public.membership_payments
WHERE id IN (
    SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY member_membership_id, amount, payment_date 
                   ORDER BY created_at ASC, id ASC
               ) as rnum
        FROM public.membership_payments
    ) t
    WHERE t.rnum > 1
);
