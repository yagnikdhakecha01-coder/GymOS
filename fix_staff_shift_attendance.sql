-- ====================================================
-- GYMOS SQL MIGRATION: FIX STAFF SHIFT ATTENDANCE ENGINE
-- ====================================================
-- This script fixes staff check-in/out issues.
-- 1. Bypasses shift timing restriction on Check-Outs (Staff can check out at any time).
-- 2. Correctly handles normal shifts and overnight night shifts on Check-In.

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
    v_local_date_str TEXT := to_char(v_local_now, 'dd-MM-yyyy'); -- Standardized to dd-MM-yyyy

    -- Identified Gym & Display
    v_gym_id UUID;
    v_display_id UUID;
    v_token_expires TIMESTAMPTZ;
    v_token_used BOOLEAN;
    v_token_valid BOOLEAN := FALSE;
    v_qr_type TEXT := 'Dynamic';

    -- Settings
    v_settings RECORD;

    -- User Profile / Member / Staff Identification
    v_resolved_user_type TEXT := NULL;
    v_user_name TEXT;
    v_member_id UUID;
    v_member_status TEXT;
    v_staff_id UUID;
    v_staff_status TEXT;

    -- Shift variables
    v_shift_assignment RECORD;
    v_shift_record RECORD;
    v_assigned_shift_type TEXT;
    v_shift_start TIME;
    v_shift_end TIME;
    v_late_after TIME;
    v_shift_dur INTERVAL;
    v_midpoint TIME;

    -- Attendance calculations
    v_existing_log RECORD;
    v_log_id UUID;
    v_check_in_time TIMESTAMPTZ;
    v_working_mins INT := 0;
    v_late_mins INT := 0;
    v_early_exit_mins INT := 0;
    v_status TEXT := 'Present';
    v_shift_status TEXT := 'Completed';

    v_formatted_check_in TEXT;
    v_formatted_check_out TEXT;
    v_err_msg TEXT;
BEGIN
    -- 0. Check Authentication
    IF v_scanner_uid IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User not authenticated. Please log in.');
    END IF;

    -- 1. STEP 1: VALIDATE QR TOKEN (Identify Gym & Display from Token)
    -- Check Dynamic QR Token first
    SELECT gym_id, display_id, expires_at, is_used
    INTO v_gym_id, v_display_id, v_token_expires, v_token_used
    FROM public.attendance_qr_tokens
    WHERE token = p_token
    LIMIT 1;

    IF v_gym_id IS NOT NULL THEN
        -- Dynamic Token Found
        IF (v_token_expires < now()) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has expired. Please scan the active QR code.');
        END IF;

        IF v_token_used THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has already been scanned.');
        END IF;

        v_token_valid := TRUE;
        v_qr_type := 'Dynamic';

        -- Mark Dynamic Token as Used immediately to prevent reuse
        UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
    ELSE
        -- Check Static QR Token in attendance_settings
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

    -- Invalid QR Token Check
    IF NOT v_token_valid OR v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid or unrecognized QR Code.');
    END IF;

    -- STEP 2: VALIDATE DISPLAY (If dynamic QR linked to a Display TV)
    IF v_display_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.attendance_displays 
            WHERE id = v_display_id AND gym_id = v_gym_id AND is_verified = TRUE AND is_enabled = TRUE
        ) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance display device is unverified or disabled.');
        END IF;
    END IF;

    -- Fetch Gym Attendance Settings
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_gym_id;
    IF v_settings IS NOT NULL AND NOT COALESCE(v_settings.is_enabled, TRUE) THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is currently disabled by gym administration.');
    END IF;

    -- STEP 3: IDENTIFY USER (Member vs Staff) WITH ROLE ISOLATION
    -- If p_user_type is specified, we isolate checks strictly to that role.
    -- Otherwise, check Staff first, then Member.
    
    -- Check if Staff
    IF p_user_type IS NULL OR p_user_type = 'Staff' THEN
        SELECT id, name, status INTO v_staff_id, v_user_name, v_staff_status
        FROM public.staff
        WHERE user_id = v_scanner_uid AND gym_id = v_gym_id
        LIMIT 1;

        IF v_staff_id IS NOT NULL THEN
            v_resolved_user_type := 'Staff';
        END IF;
    END IF;

    -- Check if Member
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

    -- Cross-Gym Isolation Check: User belongs to another gym
    IF v_resolved_user_type IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.members WHERE user_id = v_scanner_uid) OR EXISTS (SELECT 1 FROM public.staff WHERE user_id = v_scanner_uid) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'You are trying to mark attendance in another gym.');
        ELSE
            RETURN jsonb_build_object('success', FALSE, 'reason', 'User record not associated with this Gym.');
        END IF;
    END IF;

    -- ====================================================
    -- MEMBER ATTENDANCE FLOW
    -- ====================================================
    IF v_resolved_user_type = 'Member' THEN
        -- Verify membership status
        IF v_member_status NOT IN ('Active', 'Trial') THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Membership is inactive or expired. Status: ' || COALESCE(v_member_status, 'Expired'));
        END IF;

        -- Check if attendance marked today (Timezone safe comparison)
        SELECT * INTO v_existing_log 
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date);

        IF v_existing_log IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', TRUE,
                'user_type', 'Member',
                'user_name', COALESCE(v_user_name, 'Member'),
                'status', v_existing_log.status,
                'check_in', to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'attendance_date', v_existing_log.date,
                'method', v_existing_log.method,
                'message', 'Attendance already marked for today.'
            );
        END IF;

        -- Create Member Check In
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
            'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
            'attendance_date', v_local_date_str,
            'method', 'QR Code',
            'message', 'Member attendance checked in successfully!'
        );
    END IF;

    -- ====================================================
    -- STAFF ATTENDANCE & SHIFT ENGINE FLOW
    -- ====================================================
    IF v_resolved_user_type = 'Staff' THEN
        -- Resolve Assigned Shift for Staff
        SELECT * INTO v_shift_assignment
        FROM public.staff_shift_assignments
        WHERE staff_id = v_staff_id AND gym_id = v_gym_id AND status = 'Active'
        ORDER BY created_at DESC LIMIT 1;

        v_assigned_shift_type := COALESCE(v_shift_assignment.assignment_type, 'Single Shift');

        -- Lookup Shift Definition Timings
        IF v_assigned_shift_type = 'Morning Shift' THEN
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Morning Shift';
        ELSIF v_assigned_shift_type = 'Evening Shift' THEN
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Evening Shift';
        ELSE
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Single Shift';
        END IF;

        -- Fetch existing staff attendance log for today (Timezone safe comparison)
        SELECT * INTO v_existing_log
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
        ORDER BY check_in DESC LIMIT 1;

        -- SHIFT VALIDATION: Validate shift window if configured (ONLY ON CHECK-IN)
        IF (v_existing_log IS NULL OR v_existing_log.check_out IS NOT NULL) AND v_shift_record IS NOT NULL THEN
            DECLARE
                v_allowed_start TIME := (v_shift_record.start_time_24h - INTERVAL '1 hour')::TIME;
                v_allowed_end TIME := (v_shift_record.end_time_24h + INTERVAL '2 hours')::TIME;
                v_is_outside BOOLEAN := FALSE;
            BEGIN
                IF v_allowed_start <= v_allowed_end THEN
                    -- Normal Shift
                    IF v_local_time < v_allowed_start OR v_local_time > v_allowed_end THEN
                        v_is_outside := TRUE;
                    END IF;
                ELSE
                    -- Overnight Shift
                    IF v_local_time < v_allowed_start AND v_local_time > v_allowed_end THEN
                        v_is_outside := TRUE;
                    END IF;
                END IF;

                IF v_is_outside THEN
                    v_err_msg := 'You are not assigned to this shift. Your shift is ' || 
                                 COALESCE(v_shift_record.shift_type, 'Shift') || ' ' || 
                                 COALESCE(v_shift_record.start_time, '') || ' - ' || COALESCE(v_shift_record.end_time, '') || '.';
                    RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
                END IF;
            END;
        END IF;

        -- NO PREVIOUS LOG TODAY -> CREATE CHECK IN
        IF v_existing_log IS NULL OR v_existing_log.check_out IS NOT NULL THEN
            -- Calculate Late Minutes if configured
            v_status := 'Present';
            v_late_mins := 0;

            IF v_settings IS NOT NULL AND v_settings.late_time_setting IS NOT NULL AND v_settings.late_time_setting <> '' THEN
                BEGIN
                    v_late_after := v_settings.late_time_setting::TIME;
                    IF v_local_time > v_late_after THEN
                        v_status := 'Late';
                        v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_late_after)) / 60;
                    END IF;
                EXCEPTION WHEN OTHERS THEN
                    v_late_mins := 0;
                END;
            END IF;

            -- Check if check-in is past midpoint of the shift (Half Leave)
            IF v_shift_record IS NOT NULL THEN
                v_shift_dur := (v_shift_record.end_time_24h - v_shift_record.start_time_24h);
                IF v_shift_dur < INTERVAL '0' THEN
                    v_shift_dur := v_shift_dur + INTERVAL '24 hours';
                END IF;
                v_midpoint := (v_shift_record.start_time_24h + (v_shift_dur / 2))::TIME;
                
                IF v_shift_record.end_time_24h < v_shift_record.start_time_24h THEN
                    IF (v_local_time >= v_shift_record.start_time_24h AND v_local_time > v_midpoint) OR
                       (v_local_time < v_shift_record.start_time_24h AND (v_local_time + INTERVAL '24 hours')::TIME > v_midpoint) THEN
                        v_status := 'Half Leave';
                    END IF;
                ELSE
                    IF v_local_time > v_midpoint THEN
                        v_status := 'Half Leave';
                    END IF;
                END IF;
            END IF;

            INSERT INTO public.attendance_logs (
                gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
            ) VALUES (
                v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_shift_record.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
            ) RETURNING id INTO v_log_id;

            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', FALSE,
                'user_type', 'Staff',
                'action', 'Check In',
                'status', v_status,
                'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'late_minutes', v_late_mins,
                'shift_status', 'Incomplete',
                'message', 'Staff Check In successful!'
            );
        END IF;

        -- EXISTING LOG WITH NO CHECK OUT -> PERFORM CHECK OUT
        IF v_existing_log IS NOT NULL AND v_existing_log.check_out IS NULL THEN
            v_working_mins := EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 60;
            v_early_exit_mins := 0;

            IF v_shift_record IS NOT NULL AND v_shift_record.end_time_24h IS NOT NULL THEN
                IF v_local_time < v_shift_record.end_time_24h THEN
                    v_early_exit_mins := EXTRACT(EPOCH FROM (v_shift_record.end_time_24h - v_local_time)) / 60;
                END IF;
            END IF;

            UPDATE public.attendance_logs
            SET check_out = now(),
                working_minutes = v_working_mins,
                early_exit_minutes = v_early_exit_mins,
                shift_status = 'Completed',
                updated_at = now()
            WHERE id = v_existing_log.id;

            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', TRUE,
                'user_type', 'Staff',
                'action', 'Check Out',
                'status', v_existing_log.status,
                'check_in', to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'check_out', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'working_minutes', v_working_mins,
                'early_exit_minutes', v_early_exit_mins,
                'shift_status', 'Completed',
                'message', 'Staff Check Out successful!'
            );
        END IF;
    END IF;

    RETURN jsonb_build_object('success', FALSE, 'reason', 'Unable to process attendance request.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.process_qr_attendance(TEXT, TEXT) TO anon, authenticated, service_role;
