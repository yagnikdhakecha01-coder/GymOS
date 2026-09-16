-- =========================================================================
-- GYMOS: STAFF ATTENDANCE STABILITY, OWNER-CONFIGURED SHIFT TIMINGS & AUTO-ABSENT
-- =========================================================================
-- 1. Drop duplicate/ambiguous overloaded get_staff_today_attendance_details_v2 functions.
-- 2. Create single unified, non-destructive get_staff_today_attendance_details_v2.
-- 3. Prioritize owner-configured staff shift timings (shift1_start, shift1_end, etc.).
-- 4. Enforce 5-minute check-out cooldown in process_qr_attendance to prevent instant check-outs.
-- 5. Align cron_auto_mark_absent with owner-configured staff shift times in IST.
-- =========================================================================

-- Step 1: Drop ambiguous overloaded versions
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID, DATE);
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID, UUID, DATE);
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID);

-- Step 2: Create single unified get_staff_today_attendance_details_v2
CREATE OR REPLACE FUNCTION public.get_staff_today_attendance_details_v2(
    p_user_id UUID,
    p_gym_id UUID,
    p_date DATE DEFAULT ((now() AT TIME ZONE 'Asia/Kolkata'))::DATE
)
RETURNS JSONB AS $$
DECLARE
    v_staff_id UUID;
    v_profile_user_id UUID;
    v_staff_status TEXT;
    v_shift TEXT;
    v_shift_type TEXT;
    v_assigned_shift TEXT := 'Single Shift';

    -- Custom shift timings set by owner
    v_s1_start_str TEXT;
    v_s1_end_str TEXT;
    v_s2_start_str TEXT;
    v_s2_end_str TEXT;

    v_s1_start TIME;
    v_s1_end TIME;
    v_s2_start TIME;
    v_s2_end TIME;

    -- Gym fallback shift IDs
    v_morning_shift_id UUID;
    v_evening_shift_id UUID;
    v_single_shift_id UUID;

    -- Status & logs
    v_first_shift_status TEXT := 'Not Checked In';
    v_second_shift_status TEXT := 'Not Checked In';
    v_first_check_in TEXT := NULL;
    v_first_check_out TEXT := NULL;
    v_second_check_in TEXT := NULL;
    v_second_check_out TEXT := NULL;

    v_first_log RECORD;
    v_second_log RECORD;
    v_single_log RECORD;

    v_open_log_id UUID := NULL;
    v_total_working_mins INT := 0;
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    v_date_str TEXT := to_char(p_date, 'dd-MM-yyyy');

    v_can_check_in BOOLEAN := TRUE;
    v_can_check_out BOOLEAN := FALSE;
BEGIN
    -- 1. Resolve Staff Record
    SELECT s.id, s.user_id, s.status,
           s.shift, s.shift_type,
           s.shift1_start, s.shift1_end, s.shift2_start, s.shift2_end
    INTO v_staff_id, v_profile_user_id, v_staff_status,
         v_shift, v_shift_type,
         v_s1_start_str, v_s1_end_str, v_s2_start_str, v_s2_end_str
    FROM public.staff s
    WHERE (s.user_id = p_user_id OR s.id = p_user_id)
      AND s.gym_id = p_gym_id
    LIMIT 1;

    IF v_staff_id IS NULL OR v_staff_status <> 'Active' THEN
        RETURN jsonb_build_object(
            'assigned_shift', 'Single Shift',
            'working_hours_today', '0h 00m',
            'can_check_in', FALSE,
            'can_check_out', FALSE,
            'first_shift_name', 'Morning Shift',
            'first_shift_status', 'Pending Activation',
            'second_shift_name', 'Evening Shift',
            'second_shift_status', 'Pending Activation',
            'is_checked_in', FALSE,
            'is_attendance_completed', FALSE
        );
    END IF;

    -- 2. Determine Shift Mode (Single Shift vs Two Shifts)
    IF lower(COALESCE(v_shift_type, '')) IN ('both', 'two')
       OR lower(COALESCE(v_shift, '')) LIKE '%both%'
       OR lower(COALESCE(v_shift, '')) LIKE '%two%'
       OR lower(COALESCE(v_shift, '')) LIKE '%double%' THEN
        v_assigned_shift := 'Two Shifts';
    ELSE
        v_assigned_shift := 'Single Shift';
    END IF;

    -- Parse owner-configured shift times (fallback to gym defaults)
    v_s1_start := public.fn_parse_12h_time(v_s1_start_str);
    v_s1_end := public.fn_parse_12h_time(v_s1_end_str);
    v_s2_start := public.fn_parse_12h_time(v_s2_start_str);
    v_s2_end := public.fn_parse_12h_time(v_s2_end_str);

    -- Gym shifts lookup for fallbacks & shift IDs
    SELECT id, start_time_24h, end_time_24h INTO v_morning_shift_id, v_s1_start, v_s1_end
    FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Morning Shift' LIMIT 1;

    SELECT id, start_time_24h, end_time_24h INTO v_evening_shift_id, v_s2_start, v_s2_end
    FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Evening Shift' LIMIT 1;

    SELECT id, start_time_24h, end_time_24h INTO v_single_shift_id, v_s1_start, v_s1_end
    FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Single Shift' LIMIT 1;

    -- Prioritize owner-set staff profile timings if available
    v_s1_start := COALESCE(public.fn_parse_12h_time(v_s1_start_str), v_s1_start, '09:00:00'::TIME);
    v_s1_end := COALESCE(public.fn_parse_12h_time(v_s1_end_str), v_s1_end, '18:00:00'::TIME);
    v_s2_start := COALESCE(public.fn_parse_12h_time(v_s2_start_str), v_s2_start, '17:00:00'::TIME);
    v_s2_end := COALESCE(public.fn_parse_12h_time(v_s2_end_str), v_s2_end, '22:00:00'::TIME);

    -- 3. Query Attendance Logs (Pure Read-Only, NEVER mutate during query)
    IF v_assigned_shift = 'Two Shifts' THEN
        -- Query Morning Log
        SELECT * INTO v_first_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.user_id = p_user_id OR al.staff_id = v_staff_id)
          AND (al.date = v_date_str OR (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date)
          AND (
              (v_morning_shift_id IS NOT NULL AND al.shift_id = v_morning_shift_id)
              OR al.shift_index = 1
              OR (al.shift_id IS NULL AND al.check_out IS NULL)
          )
        ORDER BY al.check_in ASC
        LIMIT 1;

        -- Query Evening Log
        SELECT * INTO v_second_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.user_id = p_user_id OR al.staff_id = v_staff_id)
          AND (al.date = v_date_str OR (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date)
          AND (
              (v_evening_shift_id IS NOT NULL AND al.shift_id = v_evening_shift_id)
              OR al.shift_index = 2
          )
        ORDER BY al.check_in ASC
        LIMIT 1;

        -- Morning status
        IF v_first_log.id IS NOT NULL THEN
            IF v_first_log.status = 'Absent' THEN
                v_first_shift_status := 'Absent';
            ELSE
                v_first_check_in := to_char(v_first_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                IF v_first_log.check_out IS NOT NULL THEN
                    v_first_check_out := to_char(v_first_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    v_first_shift_status := 'Checked Out';
                ELSE
                    v_first_shift_status := 'Checked In';
                    v_open_log_id := v_first_log.id;
                END IF;
            END IF;
            v_total_working_mins := v_total_working_mins + COALESCE(v_first_log.working_minutes, 0);
        END IF;

        -- Evening status
        IF v_second_log.id IS NOT NULL THEN
            IF v_second_log.status = 'Absent' THEN
                v_second_shift_status := 'Absent';
            ELSE
                v_second_check_in := to_char(v_second_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                IF v_second_log.check_out IS NOT NULL THEN
                    v_second_check_out := to_char(v_second_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    v_second_shift_status := 'Checked Out';
                ELSE
                    v_second_shift_status := 'Checked In';
                    v_open_log_id := v_second_log.id;
                END IF;
            END IF;
            v_total_working_mins := v_total_working_mins + COALESCE(v_second_log.working_minutes, 0);
        END IF;

    ELSE
        -- Single Shift Log
        SELECT * INTO v_single_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.user_id = p_user_id OR al.staff_id = v_staff_id)
          AND (al.date = v_date_str OR (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date)
        ORDER BY al.check_in ASC
        LIMIT 1;

        IF v_single_log.id IS NOT NULL THEN
            IF v_single_log.status = 'Absent' THEN
                v_first_shift_status := 'Absent';
            ELSE
                v_first_check_in := to_char(v_single_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                IF v_single_log.check_out IS NOT NULL THEN
                    v_first_check_out := to_char(v_single_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    v_first_shift_status := 'Checked Out';
                ELSE
                    v_first_shift_status := 'Checked In';
                    v_open_log_id := v_single_log.id;
                END IF;
            END IF;
            v_total_working_mins := COALESCE(v_single_log.working_minutes, 0);
        END IF;
    END IF;

    -- 4. Calculate can_check_in / can_check_out flags
    IF v_open_log_id IS NOT NULL THEN
        v_can_check_in := FALSE;
        v_can_check_out := TRUE;
    ELSE
        IF v_assigned_shift = 'Two Shifts' THEN
            IF v_first_shift_status IN ('Checked Out', 'Absent') AND v_second_shift_status = 'Not Checked In' THEN
                v_can_check_in := TRUE;
                v_can_check_out := FALSE;
            ELSIF v_first_shift_status IN ('Checked Out', 'Absent') AND v_second_shift_status IN ('Checked Out', 'Absent') THEN
                v_can_check_in := FALSE;
                v_can_check_out := FALSE;
            ELSE
                v_can_check_in := TRUE;
                v_can_check_out := FALSE;
            END IF;
        ELSE
            IF v_first_shift_status IN ('Checked Out', 'Absent') THEN
                v_can_check_in := FALSE;
                v_can_check_out := FALSE;
            ELSE
                v_can_check_in := TRUE;
                v_can_check_out := FALSE;
            END IF;
        END IF;
    END IF;

    -- 5. If currently checked in, compute live in-progress minutes
    IF v_open_log_id IS NOT NULL THEN
        SELECT GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - al.check_in)) / 60)::INT)
        INTO v_total_working_mins
        FROM public.attendance_logs al WHERE al.id = v_open_log_id;
    END IF;

    RETURN jsonb_build_object(
        'assigned_shift', v_assigned_shift,
        'working_hours_today', (COALESCE(v_total_working_mins, 0) / 60)::TEXT || 'h ' || lpad((COALESCE(v_total_working_mins, 0) % 60)::TEXT, 2, '0') || 'm',
        'can_check_in', v_can_check_in,
        'can_check_out', v_can_check_out,
        'open_log_id', v_open_log_id,
        'first_shift_name', 'Morning Shift',
        'first_shift_check_in', v_first_check_in,
        'first_shift_check_out', v_first_check_out,
        'first_shift_status', COALESCE(v_first_shift_status, 'Not Checked In'),
        'second_shift_name', 'Evening Shift',
        'second_shift_check_in', v_second_check_in,
        'second_shift_check_out', v_second_check_out,
        'second_shift_status', COALESCE(v_second_shift_status, 'Not Checked In'),
        'is_checked_in', (v_open_log_id IS NOT NULL),
        'is_attendance_completed', (NOT v_can_check_in AND NOT v_can_check_out),
        'morning_shift_start', to_char(v_s1_start, 'HH12:MI AM'),
        'morning_shift_end', to_char(v_s1_end, 'HH12:MI AM'),
        'evening_shift_start', to_char(v_s2_start, 'HH12:MI AM'),
        'evening_shift_end', to_char(v_s2_end, 'HH12:MI AM'),
        'shift_source', 'owner_configured'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_staff_today_attendance_details_v2(UUID, UUID, DATE) TO anon, authenticated, service_role;


-- -------------------------------------------------------------------------
-- Step 3: Upgrade process_qr_attendance with 5-minute cooldown & owner shift times
-- -------------------------------------------------------------------------
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
    v_staff_user_id UUID;
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
    -- STAFF ATTENDANCE FLOW (Owner-Configured Timings + 5-min Cooldown)
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

                IF v_local_time < v_s1_end THEN
                    v_early_exit_mins := EXTRACT(EPOCH FROM (v_s1_end - v_local_time)) / 60;
                END IF;

                IF v_local_time <= (v_midpoint + INTERVAL '30 minutes')::TIME THEN
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

            IF v_local_time > v_midpoint THEN
                v_status := 'Half Leave';
            ELSIF v_local_time > (v_s1_start + INTERVAL '1 hour')::TIME THEN
                v_status := 'Late';
                v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_s1_start)) / 60;
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
                IF v_local_time > (v_s1_start + INTERVAL '1 hour')::TIME THEN
                    v_status := 'Late';
                    v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_s1_start)) / 60;
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
                IF v_local_time > (v_s2_start + INTERVAL '1 hour')::TIME THEN
                    v_status := 'Late';
                    v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_s2_start)) / 60;
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


-- -------------------------------------------------------------------------
-- Step 4: Upgrade cron_auto_mark_absent with owner-configured staff shift times
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_auto_mark_absent()
RETURNS VOID AS $$
DECLARE
    v_local_now TIMESTAMP := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;
    v_local_date DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    
    v_gym RECORD;
    v_staff RECORD;
    v_member RECORD;
    v_exists BOOLEAN;
    v_latest_shift_end TIME;
    v_trigger_timestamp TIMESTAMPTZ;
    
    v_check_date DATE;
    v_check_date_str TEXT;

    v_s1_end TIME;
    v_s2_end TIME;
    v_is_both BOOLEAN;
BEGIN
    FOR v_gym IN 
        SELECT gym_id 
        FROM public.attendance_settings 
        WHERE auto_mark_absent = TRUE
    LOOP
        FOR v_check_date IN SELECT v_local_date UNION SELECT (v_local_date - 1) LOOP
            v_check_date_str := to_char(v_check_date, 'dd-MM-yyyy');

            -- 1. SKIP SUNDAYS
            IF EXTRACT(DOW FROM v_check_date) = 0 THEN
                CONTINUE;
            END IF;

            -- 2. SKIP GYM HOLIDAYS
            IF EXISTS (
                SELECT 1 FROM public.holidays 
                WHERE gym_id = v_gym.gym_id 
                  AND (holiday_date = v_check_date OR date = v_check_date)
            ) THEN
                CONTINUE;
            END IF;

            -- ==========================================
            -- A. STAFF AUTO-ABSENT (Owner Shift Timings)
            -- ==========================================
            FOR v_staff IN 
                SELECT id, user_id, shift, shift_type, shift1_end, shift2_end
                FROM public.staff 
                WHERE gym_id = v_gym.gym_id AND status = 'Active'
            LOOP
                v_is_both := (lower(COALESCE(v_staff.shift_type, '')) IN ('both', 'two')
                              OR lower(COALESCE(v_staff.shift, '')) LIKE '%both%'
                              OR lower(COALESCE(v_staff.shift, '')) LIKE '%two%');

                v_s1_end := COALESCE(public.fn_parse_12h_time(v_staff.shift1_end), '18:00:00'::TIME);
                v_s2_end := COALESCE(public.fn_parse_12h_time(v_staff.shift2_end), '22:00:00'::TIME);

                IF v_is_both THEN
                    -- Morning Shift check
                    v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_s1_end::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                    IF now() > v_trigger_timestamp THEN
                        SELECT EXISTS (
                            SELECT 1 FROM public.attendance_logs 
                            WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                              AND gym_id = v_gym.gym_id 
                              AND (date = v_check_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_check_date)
                              AND COALESCE(shift_index, 1) = 1
                        ) INTO v_exists;

                        IF NOT v_exists THEN
                            INSERT INTO public.attendance_logs (
                                gym_id, user_id, role, user_type, staff_id, shift_index, date, check_in, check_out, status, shift_status, method
                            ) VALUES (
                                v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, 1, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                            );
                        END IF;
                    END IF;

                    -- Evening Shift check
                    v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_s2_end::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                    IF now() > v_trigger_timestamp THEN
                        SELECT EXISTS (
                            SELECT 1 FROM public.attendance_logs 
                            WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                              AND gym_id = v_gym.gym_id 
                              AND (date = v_check_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_check_date)
                              AND COALESCE(shift_index, 2) = 2
                        ) INTO v_exists;

                        IF NOT v_exists THEN
                            INSERT INTO public.attendance_logs (
                                gym_id, user_id, role, user_type, staff_id, shift_index, date, check_in, check_out, status, shift_status, method
                            ) VALUES (
                                v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, 2, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                            );
                        END IF;
                    END IF;

                ELSE
                    -- Single Shift check
                    v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_s1_end::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                    IF now() > v_trigger_timestamp THEN
                        SELECT EXISTS (
                            SELECT 1 FROM public.attendance_logs 
                            WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                              AND gym_id = v_gym.gym_id 
                              AND (date = v_check_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_check_date)
                        ) INTO v_exists;

                        IF NOT v_exists THEN
                            INSERT INTO public.attendance_logs (
                                gym_id, user_id, role, user_type, staff_id, date, check_in, check_out, status, shift_status, method
                            ) VALUES (
                                v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                            );
                        END IF;
                    END IF;
                END IF;
            END LOOP;

            -- ==========================================
            -- B. MEMBER AUTO-ABSENT ENGINE
            -- ==========================================
            SELECT COALESCE(MAX(end_time_24h), '22:00:00'::TIME) INTO v_latest_shift_end
            FROM public.gym_shifts
            WHERE gym_id = v_gym.gym_id;

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
