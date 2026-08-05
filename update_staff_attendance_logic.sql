-- =========================================================================
-- GYMOS BACKEND SQL ENGINE: COMPLETE STAFF ATTENDANCE & SHIFT LOGIC MIGRATION
-- =========================================================================
-- Features:
-- 1. Single Shift & Two Shifts Mode settings detection.
-- 2. Staff Activation & Login Check:
--    - Attendance (Present / Absent) ONLY applies to Staff with status = 'Active' AND linked user_id (logged-in app user).
--    - Pending invitations, unlinked accounts, or inactive status will NOT generate attendance or auto-absent logs.
-- 3. Single Shift rules:
--    - Absent = 1.0 absent, Present = 1.0 present.
--    - Check-in after shift midpoint (shift_duration / 2): marked as Half Leave (0.5 present, 0.5 absent).
--    - Early check-out around/near shift midpoint: marked as Half Leave (0.5 present, 0.5 absent).
--    - Entry > 1 hour after shift start time: marked as Late Entry, late minutes counted.
-- 4. Two Shifts Mode rules (Morning & Evening):
--    - Shift Weight: Morning = 0.5, Evening = 0.5.
--    - Morning Auto-Absent: No check-in by Morning end_time + 1hr -> marked Absent (0.5 absent).
--    - Evening Auto-Absent: No check-in by Evening end_time + 1hr -> marked Absent (0.5 absent).
--    - Late Entry: Entry > 1 hour after shift start time -> marked as Late Entry with late minutes.
--    - Scan Isolation: Checking out of Morning shift ONLY checks out Morning shift, NEVER auto checks in Evening shift.
--    - Morning Absent -> Evening Check-in: If Morning is Absent, Evening check-in applies to Evening shift cleanly.
--    - Duplicate Entry Protection: Returns 'already_marked = true' with exact check-in/out timestamp.
-- =========================================================================

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
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    v_local_date_str TEXT := to_char(v_local_now, 'dd-MM-yyyy');

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

    -- User Profile / Member / Staff Identification
    v_resolved_user_type TEXT := NULL;
    v_user_name TEXT;
    v_member_id UUID;
    v_member_status TEXT;
    v_staff_id UUID;
    v_staff_status TEXT;
    v_staff_user_id UUID;

    -- Shift Assignment & Definition Records
    v_shift_assignment RECORD;
    v_assigned_shift_type TEXT;

    -- Single Shift Calculations
    v_single_shift_rec RECORD;
    v_single_start TIME;
    v_single_end TIME;
    v_single_dur INTERVAL;
    v_single_midpoint TIME;

    -- Two Shift Definition Records
    v_morning_shift_rec RECORD;
    v_evening_shift_rec RECORD;
    v_morning_log RECORD;
    v_evening_log RECORD;

    -- Logs & Working Variables
    v_existing_log RECORD;
    v_log_id UUID;
    v_working_mins INT := 0;
    v_late_mins INT := 0;
    v_early_exit_mins INT := 0;
    v_status TEXT := 'Present';
    v_err_msg TEXT;

    -- Check-in / Out Time Strings for Output
    v_formatted_check_in TEXT;
    v_formatted_check_out TEXT;
BEGIN
    -- 0. Check Authentication
    IF v_scanner_uid IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User not authenticated. Please log in.');
    END IF;

    -- 1. STEP 1: VALIDATE QR TOKEN (Dynamic vs Static)
    SELECT gym_id, display_id, expires_at, is_used
    INTO v_gym_id, v_display_id, v_token_expires, v_token_used
    FROM public.attendance_qr_tokens
    WHERE token = p_token
    LIMIT 1;

    IF v_gym_id IS NOT NULL THEN
        IF (v_token_expires < now()) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has expired. Please scan the active QR code.');
        END IF;

        IF v_token_used THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has already been scanned.');
        END IF;

        v_token_valid := TRUE;
        v_qr_type := 'Dynamic';

        UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
    ELSE
        SELECT gym_id, is_enabled, method, static_qr_token, late_time_setting
        INTO v_settings
        FROM public.attendance_settings
        WHERE static_qr_token = p_token
        LIMIT 1;

        IF v_settings IS NOT NULL THEN
            v_gym_id := v_settings.gym_id;
            v_token_valid := TRUE;
            v_qr_type := 'Static';
        END IF;
    END IF;

    IF NOT v_token_valid OR v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid or unrecognized QR Code.');
    END IF;

    -- STEP 2: VALIDATE DISPLAY (If Dynamic QR linked to Display TV)
    IF v_display_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.attendance_displays 
            WHERE id = v_display_id AND gym_id = v_gym_id AND is_verified = TRUE AND is_enabled = TRUE
        ) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance display device is unverified or disabled.');
        END IF;
    END IF;

    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_gym_id;
    IF v_settings IS NOT NULL AND NOT COALESCE(v_settings.is_enabled, TRUE) THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is currently disabled by gym administration.');
    END IF;

    -- Fetch Gym Shift Mode setting
    SELECT COALESCE(mode, 'Single Shift') INTO v_gym_shift_mode 
    FROM public.gym_shift_settings 
    WHERE gym_id = v_gym_id;

    -- STEP 3: IDENTIFY USER ROLE (Staff vs Member) WITH ACTIVATION CHECK
    IF p_user_type IS NULL OR p_user_type = 'Staff' THEN
        SELECT id, name, status, user_id INTO v_staff_id, v_user_name, v_staff_status, v_staff_user_id
        FROM public.staff
        WHERE (user_id = v_scanner_uid OR id = v_scanner_uid) AND gym_id = v_gym_id
        LIMIT 1;

        IF v_staff_id IS NOT NULL THEN
            -- Check if staff account is active and logged in
            IF v_staff_status <> 'Active' OR v_staff_user_id IS NULL THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'Staff invitation is pending or account is not activated. Please complete login first.');
            END IF;
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

    IF v_resolved_user_type IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.members WHERE user_id = v_scanner_uid) OR EXISTS (SELECT 1 FROM public.staff WHERE user_id = v_scanner_uid OR id = v_scanner_uid) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'You belong to another gym branch.');
        ELSE
            RETURN jsonb_build_object('success', FALSE, 'reason', 'User record not found for this gym.');
        END IF;
    END IF;

    -- ====================================================
    -- MEMBER ATTENDANCE FLOW
    -- ====================================================
    IF v_resolved_user_type = 'Member' THEN
        IF v_member_status NOT IN ('Active', 'Trial') THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Membership is inactive or expired.');
        END IF;

        SELECT * INTO v_existing_log 
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date);

        IF v_existing_log IS NOT NULL THEN
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
        END IF;

        INSERT INTO public.attendance_logs (
            gym_id, user_id, role, user_type, member_id, date, check_in, status, method, qr_type
        ) VALUES (
            v_gym_id, v_scanner_uid, 'Member', 'Member', v_member_id, v_local_date_str, now(), 'Present', COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
        ) RETURNING id INTO v_log_id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'already_marked', FALSE,
            'user_type', 'Member',
            'user_name', COALESCE(v_user_name, 'Member'),
            'status', 'Present',
            'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM'),
            'attendance_date', v_local_date_str,
            'message', 'Member attendance checked in successfully!'
        );
    END IF;

    -- ====================================================
    -- STAFF ATTENDANCE & SHIFT ENGINE FLOW
    -- ====================================================
    IF v_resolved_user_type = 'Staff' THEN
        -- 1. Fetch Staff Shift Assignment
        SELECT * INTO v_shift_assignment
        FROM public.staff_shift_assignments
        WHERE staff_id = v_staff_id AND gym_id = v_gym_id AND status = 'Active'
        ORDER BY created_at DESC LIMIT 1;

        v_assigned_shift_type := COALESCE(v_shift_assignment.assignment_type, v_gym_shift_mode, 'Single Shift');
        IF v_assigned_shift_type IN ('Two Shifts', 'Both Shifts') THEN
            v_assigned_shift_type := 'Two Shifts';
        END IF;

        -- ----------------------------------------------------
        -- BRANCH A: SINGLE SHIFT MODE
        -- ----------------------------------------------------
        IF v_assigned_shift_type = 'Single Shift' THEN
            -- Fetch Single Shift Definition
            SELECT * INTO v_single_shift_rec 
            FROM public.gym_shifts 
            WHERE gym_id = v_gym_id AND shift_type = 'Single Shift'
            LIMIT 1;

            v_single_start := COALESCE(v_single_shift_rec.start_time_24h, '09:00:00'::TIME);
            v_single_end := COALESCE(v_single_shift_rec.end_time_24h, '19:00:00'::TIME);

            -- Calculate Shift Duration & Midpoint
            v_single_dur := (v_single_end - v_single_start);
            IF v_single_dur < INTERVAL '0' THEN
                v_single_dur := v_single_dur + INTERVAL '24 hours';
            END IF;
            v_single_midpoint := (v_single_start + (v_single_dur / 2))::TIME;

            -- Query existing log for today
            SELECT * INTO v_existing_log
            FROM public.attendance_logs
            WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id)
              AND gym_id = v_gym_id 
              AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
            ORDER BY check_in ASC LIMIT 1;

            -- A1. ACTIVE OPEN LOG EXISTS -> PERFORM CHECK OUT
            IF v_existing_log IS NOT NULL AND v_existing_log.check_out IS NULL THEN
                v_working_mins := EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 60;
                v_early_exit_mins := 0;
                v_status := v_existing_log.status;

                -- Early Exit Calculation from End Time
                IF v_local_time < v_single_end THEN
                    v_early_exit_mins := EXTRACT(EPOCH FROM (v_single_end - v_local_time)) / 60;
                END IF;

                -- Check-out around midpoint / half shift duration rule:
                -- If check-out is before or near midpoint (+30 mins), set status to Half Leave (0.5 present, 0.5 absent)
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

            -- A2. LOG COMPLETED OR ABSENT TODAY -> DUPLICATE SCAN PREVENTION
            IF v_existing_log IS NOT NULL AND (v_existing_log.check_out IS NOT NULL OR v_existing_log.status = 'Absent') THEN
                v_formatted_check_in := CASE 
                    WHEN v_existing_log.check_in IS NOT NULL THEN to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')
                    ELSE 'N/A'
                END;
                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', TRUE,
                    'user_type', 'Staff',
                    'action', 'Completed',
                    'status', v_existing_log.status,
                    'check_in', v_formatted_check_in,
                    'check_out', to_char(v_existing_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM'),
                    'message', 'Attendance already completed for today at ' || v_formatted_check_in || '.'
                );
            END IF;

            -- A3. NO LOG TODAY -> PERFORM CHECK IN
            v_status := 'Present';
            v_late_mins := 0;

            -- Rule 1: Check-in after midpoint (shift_duration / 2) -> Half Leave (0.5 absent, 0.5 present)
            IF v_local_time > v_single_midpoint THEN
                v_status := 'Half Leave';
            -- Rule 2: Entry > 1 hour after shift start time -> Late Entry with late minutes
            ELSIF v_local_time > (v_single_start + INTERVAL '1 hour')::TIME THEN
                v_status := 'Late';
                v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_single_start)) / 60;
            END IF;

            INSERT INTO public.attendance_logs (
                gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
            ) VALUES (
                v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_single_shift_rec.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
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

        -- ----------------------------------------------------
        -- BRANCH B: TWO SHIFTS MODE (Morning & Evening)
        -- ----------------------------------------------------
        ELSE
            -- Fetch Morning & Evening Shift Definitions
            SELECT * INTO v_morning_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Morning Shift' LIMIT 1;
            SELECT * INTO v_evening_shift_rec FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Evening Shift' LIMIT 1;

            -- Query existing Morning & Evening logs today
            SELECT * INTO v_morning_log 
            FROM public.attendance_logs
            WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id)
              AND gym_id = v_gym_id 
              AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
              AND (shift_id = v_morning_shift_rec.id OR shift_id IS NULL)
            ORDER BY check_in ASC LIMIT 1;

            SELECT * INTO v_evening_log 
            FROM public.attendance_logs
            WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id)
              AND gym_id = v_gym_id 
              AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
              AND shift_id = v_evening_shift_rec.id
            ORDER BY check_in ASC LIMIT 1;

            -- AUTO-ABSENT AUTO-EVALUATION (Only for active logged-in staff):
            -- Morning Shift: If no check-in by Morning end_time + 1hr -> mark Morning as Absent
            IF v_morning_log IS NULL AND v_morning_shift_rec.end_time_24h IS NOT NULL THEN
                IF v_local_time > (v_morning_shift_rec.end_time_24h + INTERVAL '1 hour')::TIME THEN
                    INSERT INTO public.attendance_logs (
                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, working_minutes, method, qr_type
                    ) VALUES (
                        v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_morning_shift_rec.id, v_local_date_str, 
                        (v_local_date || ' ' || v_morning_shift_rec.start_time_24h)::TIMESTAMPTZ,
                        (v_local_date || ' ' || v_morning_shift_rec.end_time_24h)::TIMESTAMPTZ,
                        'Absent', 'Completed', 0, 'Auto-System', 'System'
                    ) RETURNING * INTO v_morning_log;
                END IF;
            END IF;

            -- Evening Shift: If no check-in by Evening end_time + 1hr -> mark Evening as Absent
            IF v_evening_log IS NULL AND v_evening_shift_rec.end_time_24h IS NOT NULL THEN
                IF v_local_time > (v_evening_shift_rec.end_time_24h + INTERVAL '1 hour')::TIME THEN
                    INSERT INTO public.attendance_logs (
                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, working_minutes, method, qr_type
                    ) VALUES (
                        v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_evening_shift_rec.id, v_local_date_str,
                        (v_local_date || ' ' || v_evening_shift_rec.start_time_24h)::TIMESTAMPTZ,
                        (v_local_date || ' ' || v_evening_shift_rec.end_time_24h)::TIMESTAMPTZ,
                        'Absent', 'Completed', 0, 'Auto-System', 'System'
                    ) RETURNING * INTO v_evening_log;
                END IF;
            END IF;

            -- B1. CHECK-OUT SCENARIO (Open log exists)
            -- Check if Morning Shift is currently open (check_out IS NULL)
            IF v_morning_log IS NOT NULL AND v_morning_log.check_out IS NULL AND v_morning_log.status <> 'Absent' THEN
                v_working_mins := EXTRACT(EPOCH FROM (now() - v_morning_log.check_in)) / 60;
                v_early_exit_mins := 0;

                IF v_morning_shift_rec.end_time_24h IS NOT NULL AND v_local_time < v_morning_shift_rec.end_time_24h THEN
                    v_early_exit_mins := EXTRACT(EPOCH FROM (v_morning_shift_rec.end_time_24h - v_local_time)) / 60;
                END IF;

                UPDATE public.attendance_logs
                SET check_out = now(),
                    working_minutes = v_working_mins,
                    early_exit_minutes = v_early_exit_mins,
                    shift_status = 'Completed',
                    updated_at = now()
                WHERE id = v_morning_log.id;

                v_formatted_check_in := to_char(v_morning_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                v_formatted_check_out := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');

                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', TRUE,
                    'user_type', 'Staff',
                    'action', 'Check Out',
                    'shift_name', 'Morning Shift',
                    'status', v_morning_log.status,
                    'check_in', v_formatted_check_in,
                    'check_out', v_formatted_check_out,
                    'working_minutes', v_working_mins,
                    'early_exit_minutes', v_early_exit_mins,
                    'shift_status', 'Completed',
                    'message', 'Morning Shift Check Out successful!'
                );
            -- Check if Evening Shift is currently open (check_out IS NULL)
            ELSIF v_evening_log IS NOT NULL AND v_evening_log.check_out IS NULL AND v_evening_log.status <> 'Absent' THEN
                v_working_mins := EXTRACT(EPOCH FROM (now() - v_evening_log.check_in)) / 60;
                v_early_exit_mins := 0;

                IF v_evening_shift_rec.end_time_24h IS NOT NULL AND v_local_time < v_evening_shift_rec.end_time_24h THEN
                    v_early_exit_mins := EXTRACT(EPOCH FROM (v_evening_shift_rec.end_time_24h - v_local_time)) / 60;
                END IF;

                UPDATE public.attendance_logs
                SET check_out = now(),
                    working_minutes = v_working_mins,
                    early_exit_minutes = v_early_exit_mins,
                    shift_status = 'Completed',
                    updated_at = now()
                WHERE id = v_evening_log.id;

                v_formatted_check_in := to_char(v_evening_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                v_formatted_check_out := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');

                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', TRUE,
                    'user_type', 'Staff',
                    'action', 'Check Out',
                    'shift_name', 'Evening Shift',
                    'status', v_evening_log.status,
                    'check_in', v_formatted_check_in,
                    'check_out', v_formatted_check_out,
                    'working_minutes', v_working_mins,
                    'early_exit_minutes', v_early_exit_mins,
                    'shift_status', 'Completed',
                    'message', 'Evening Shift Check Out successful!'
                );
            END IF;

            -- B2. CHECK-IN SCENARIO (No open log)
            -- Decide which shift to check into: Morning vs Evening
            
            -- Can check in Morning if Morning log is NULL and current time is before Morning end_time + 1hr
            IF v_morning_log IS NULL AND (v_morning_shift_rec.end_time_24h IS NULL OR v_local_time <= (v_morning_shift_rec.end_time_24h + INTERVAL '1 hour')::TIME) THEN
                v_status := 'Present';
                v_late_mins := 0;

                -- Late Entry rule: Entry > 1 hour after shift start time
                IF v_morning_shift_rec.start_time_24h IS NOT NULL AND v_local_time > (v_morning_shift_rec.start_time_24h + INTERVAL '1 hour')::TIME THEN
                    v_status := 'Late';
                    v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_morning_shift_rec.start_time_24h)) / 60;
                END IF;

                INSERT INTO public.attendance_logs (
                    gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
                ) VALUES (
                    v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_morning_shift_rec.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
                ) RETURNING id INTO v_log_id;

                v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', FALSE,
                    'user_type', 'Staff',
                    'action', 'Check In',
                    'shift_name', 'Morning Shift',
                    'status', v_status,
                    'check_in', v_formatted_check_in,
                    'late_minutes', v_late_mins,
                    'shift_status', 'Incomplete',
                    'message', 'Morning Shift Check In successful at ' || v_formatted_check_in || '!'
                );

            -- Can check in Evening if Evening log is NULL and current time is before Evening end_time + 1hr
            ELSIF v_evening_log IS NULL AND (v_evening_shift_rec.end_time_24h IS NULL OR v_local_time <= (v_evening_shift_rec.end_time_24h + INTERVAL '1 hour')::TIME) THEN
                v_status := 'Present';
                v_late_mins := 0;

                -- Late Entry rule: Entry > 1 hour after shift start time
                IF v_evening_shift_rec.start_time_24h IS NOT NULL AND v_local_time > (v_evening_shift_rec.start_time_24h + INTERVAL '1 hour')::TIME THEN
                    v_status := 'Late';
                    v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_evening_shift_rec.start_time_24h)) / 60;
                END IF;

                INSERT INTO public.attendance_logs (
                    gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
                ) VALUES (
                    v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_evening_shift_rec.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
                ) RETURNING id INTO v_log_id;

                v_formatted_check_in := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', FALSE,
                    'user_type', 'Staff',
                    'action', 'Check In',
                    'shift_name', 'Evening Shift',
                    'status', v_status,
                    'check_in', v_formatted_check_in,
                    'late_minutes', v_late_mins,
                    'shift_status', 'Incomplete',
                    'message', 'Evening Shift Check In successful at ' || v_formatted_check_in || '!'
                );

            -- B3. DUPLICATE SCAN / EVERYTHING ALREADY DONE TODAY
            ELSE
                v_formatted_check_in := CASE 
                    WHEN v_evening_log.check_in IS NOT NULL THEN to_char(v_evening_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')
                    WHEN v_morning_log.check_in IS NOT NULL THEN to_char(v_morning_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')
                    ELSE 'Today'
                END;

                RETURN jsonb_build_object(
                    'success', TRUE,
                    'already_marked', TRUE,
                    'user_type', 'Staff',
                    'action', 'Completed',
                    'message', 'Attendance already done for today (' || v_formatted_check_in || ').'
                );
            END IF;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', FALSE, 'reason', 'Unable to process attendance request.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.process_qr_attendance(TEXT, TEXT) TO anon, authenticated, service_role;

-- =========================================================================
-- REBUILD get_staff_today_attendance_details_v2 RPC
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_staff_today_attendance_details_v2(
    p_user_id UUID,
    p_gym_id UUID,
    p_date DATE DEFAULT (now() AT TIME ZONE 'Asia/Kolkata')::DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff_id UUID := NULL;
    v_profile_user_id UUID := NULL;
    v_staff_status TEXT := NULL;
    v_assigned_shift TEXT := 'Single Shift';
    v_first_check_in TEXT := NULL;
    v_first_check_out TEXT := NULL;
    v_second_check_in TEXT := NULL;
    v_second_check_out TEXT := NULL;
    v_first_shift_status TEXT := 'Not Checked In';
    v_second_shift_status TEXT := 'Not Checked In';
    v_total_working_mins INT := 0;
    v_can_check_in BOOLEAN := TRUE;
    v_can_check_out BOOLEAN := FALSE;
    v_open_log_id UUID := NULL;
    v_hours INT := 0;
    v_mins INT := 0;
    v_working_hours_str TEXT := '0h 00m';
    
    v_morning_shift_id UUID := NULL;
    v_evening_shift_id UUID := NULL;
    v_morning_shift_end TIME := NULL;
    v_evening_shift_end TIME := NULL;

    v_morning_log RECORD;
    v_evening_log RECORD;
    v_single_log RECORD;

    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
BEGIN
    SELECT s.id, s.user_id, s.status, COALESCE(NULLIF(ssa.assignment_type, ''), NULLIF(s.shift, ''), 'Single Shift')
    INTO v_staff_id, v_profile_user_id, v_staff_status, v_assigned_shift
    FROM public.staff s
    LEFT JOIN public.staff_shift_assignments ssa 
           ON (ssa.staff_id = s.id AND ssa.status = 'Active')
    WHERE (s.user_id = p_user_id OR s.id = p_user_id)
      AND s.gym_id = p_gym_id
    ORDER BY ssa.created_at DESC NULLS LAST
    LIMIT 1;

    IF v_staff_id IS NULL THEN
        SELECT s.id, s.user_id, s.status, COALESCE(s.shift, 'Single Shift')
        INTO v_staff_id, v_profile_user_id, v_staff_status, v_assigned_shift
        FROM public.staff s
        WHERE (s.user_id = p_user_id OR s.id = p_user_id)
        LIMIT 1;
    END IF;

    -- Activation & Login Check: If staff account is pending invitation or not activated, return disabled state
    IF v_staff_id IS NULL OR v_staff_status <> 'Active' OR v_profile_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'assigned_shift', COALESCE(v_assigned_shift, 'Single Shift'),
            'working_hours_today', '0h 00m',
            'can_check_in', FALSE,
            'can_check_out', FALSE,
            'first_shift_name', 'Morning Shift',
            'first_shift_check_in', NULL,
            'first_shift_check_out', NULL,
            'first_shift_status', 'Pending Activation',
            'second_shift_name', 'Evening Shift',
            'second_shift_check_in', NULL,
            'second_shift_check_out', NULL,
            'second_shift_status', 'Pending Activation',
            'is_checked_in', FALSE,
            'is_attendance_completed', FALSE
        );
    END IF;

    SELECT id, end_time_24h INTO v_morning_shift_id, v_morning_shift_end 
    FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Morning Shift';
    
    SELECT id, end_time_24h INTO v_evening_shift_id, v_evening_shift_end 
    FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Evening Shift';

    IF v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN
        -- Morning shift log
        SELECT * INTO v_morning_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
          AND (shift_id = v_morning_shift_id OR shift_id IS NULL)
        ORDER BY check_in ASC
        LIMIT 1;

        -- Evening shift log
        SELECT * INTO v_evening_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
          AND shift_id = v_evening_shift_id
        ORDER BY check_in ASC
        LIMIT 1;

        -- Auto Absent Evaluation if end_time + 1hr passed
        IF v_morning_log.id IS NULL AND v_morning_shift_end IS NOT NULL AND v_local_time > (v_morning_shift_end + INTERVAL '1 hour')::TIME THEN
            v_first_shift_status := 'Absent';
        ELSIF v_morning_log.id IS NOT NULL THEN
            IF v_morning_log.status = 'Absent' THEN
                v_first_shift_status := 'Absent';
            ELSE
                v_first_check_in := to_char(v_morning_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                IF v_morning_log.check_out IS NOT NULL THEN
                    v_first_check_out := to_char(v_morning_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    v_first_shift_status := 'Checked Out';
                ELSE
                    v_first_shift_status := 'Checked In';
                    v_open_log_id := v_morning_log.id;
                END IF;
            END IF;
            v_total_working_mins := v_total_working_mins + COALESCE(v_morning_log.working_minutes, 0);
        END IF;

        IF v_evening_log.id IS NULL AND v_evening_shift_end IS NOT NULL AND v_local_time > (v_evening_shift_end + INTERVAL '1 hour')::TIME THEN
            v_second_shift_status := 'Absent';
        ELSIF v_evening_log.id IS NOT NULL THEN
            IF v_evening_log.status = 'Absent' THEN
                v_second_shift_status := 'Absent';
            ELSE
                v_second_check_in := to_char(v_evening_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                IF v_evening_log.check_out IS NOT NULL THEN
                    v_second_check_out := to_char(v_evening_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    v_second_shift_status := 'Checked Out';
                ELSE
                    v_second_shift_status := 'Checked In';
                    v_open_log_id := v_evening_log.id;
                END IF;
            END IF;
            v_total_working_mins := v_total_working_mins + COALESCE(v_evening_log.working_minutes, 0);
        END IF;
    ELSE
        SELECT * INTO v_single_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
        ORDER BY check_in ASC
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

    IF v_open_log_id IS NOT NULL THEN
        v_can_check_in := FALSE;
        v_can_check_out := TRUE;
    ELSE
        IF (v_assigned_shift IN ('Two Shifts', 'Both Shifts') AND v_first_shift_status IN ('Checked Out', 'Absent') AND v_second_shift_status IN ('Checked Out', 'Absent')) OR
           (v_assigned_shift NOT IN ('Two Shifts', 'Both Shifts') AND v_first_shift_status IN ('Checked Out', 'Absent')) THEN
            v_can_check_in := FALSE;
            v_can_check_out := FALSE;
        ELSE
            v_can_check_in := TRUE;
            v_can_check_out := FALSE;
        END IF;
    END IF;

    v_total_working_mins := COALESCE(v_total_working_mins, 0);
    v_hours := v_total_working_mins / 60;
    v_mins := v_total_working_mins % 60;
    v_working_hours_str := v_hours || 'h ' || lpad(v_mins::text, 2, '0') || 'm';

    RETURN jsonb_build_object(
        'assigned_shift', CASE WHEN v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN 'Two Shifts' ELSE COALESCE(v_assigned_shift, 'Single Shift') END,
        'working_hours_today', v_working_hours_str,
        'can_check_in', v_can_check_in,
        'can_check_out', v_can_check_out,
        'first_shift_name', 'Morning Shift',
        'first_shift_check_in', v_first_check_in,
        'first_shift_check_out', v_first_check_out,
        'first_shift_status', COALESCE(v_first_shift_status, 'Not Checked In'),
        'second_shift_name', 'Evening Shift',
        'second_shift_check_in', v_second_check_in,
        'second_shift_check_out', v_second_check_out,
        'second_shift_status', COALESCE(v_second_shift_status, 'Not Checked In'),
        'is_checked_in', (v_open_log_id IS NOT NULL),
        'is_attendance_completed', NOT v_can_check_in AND NOT v_can_check_out
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_today_attendance_details_v2(UUID, UUID, DATE) TO anon, authenticated, service_role;

-- =========================================================================
-- UPDATE cron_auto_mark_absent FUNCTION
-- =========================================================================
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
    FOR v_gym IN 
        SELECT gym_id 
        FROM public.attendance_settings 
        WHERE auto_mark_absent = TRUE
    LOOP
        -- STAFF AUTO-ABSENT ENGINE (Only Active & Logged-in Staff)
        FOR v_staff IN 
            SELECT id, user_id 
            FROM public.staff 
            WHERE gym_id = v_gym.gym_id AND status = 'Active' AND user_id IS NOT NULL
        LOOP
            SELECT * INTO v_assignment 
            FROM public.staff_shift_assignments 
            WHERE staff_id = v_staff.id AND gym_id = v_gym.gym_id AND status = 'Active'
            LIMIT 1;
            
            IF v_assignment IS NOT NULL THEN
                FOR v_check_date IN SELECT v_local_date UNION SELECT (v_local_date - 1) LOOP
                    v_check_date_str := to_char(v_check_date, 'dd-MM-yyyy');
                    
                    IF v_assignment.assignment_type = 'Both Shifts' THEN
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = 'Morning Shift';
                        IF v_shift IS NOT NULL THEN
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
                        
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = 'Evening Shift';
                        IF v_shift IS NOT NULL THEN
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
                    
                    ELSE
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE id = v_assignment.shift_id;
                        IF v_shift IS NULL THEN
                            SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = v_assignment.assignment_type;
                        END IF;
                        
                        IF v_shift IS NOT NULL THEN
                            IF v_shift.shift_type = 'Single Shift' THEN
                                v_trigger_timestamp := (v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata';
                            ELSE
                                v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            END IF;

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
                END LOOP;
            END IF;
        END LOOP;

        -- MEMBER AUTO-ABSENT ENGINE
        SELECT COALESCE(MAX(end_time_24h), '22:00:00'::TIME) INTO v_latest_shift_end
        FROM public.gym_shifts
        WHERE gym_id = v_gym.gym_id;

        v_trigger_timestamp := ((v_local_date::TEXT || ' ' || v_latest_shift_end::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '2 hours';

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
                      AND date = to_char(v_local_date, 'dd-MM-yyyy') 
                      AND shift_id IS NULL
                ) INTO v_exists;
                
                IF NOT v_exists THEN
                    INSERT INTO public.attendance_logs (
                        gym_id, user_id, role, user_type, member_id, date, check_in, check_out, status, method
                    ) VALUES (
                        v_gym.gym_id, v_member.user_id, 'Member', 'Member', v_member.id, to_char(v_local_date, 'dd-MM-yyyy'), v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'System'
                    );
                END IF;
            END LOOP;
        END IF;
        
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.cron_auto_mark_absent() TO anon, authenticated, service_role;
