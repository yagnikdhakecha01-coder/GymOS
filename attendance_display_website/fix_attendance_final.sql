-- =========================================================================
-- GYMOS ATTENDANCE FINAL SYSTEM REBUILD & FIXES
-- RUN THIS IN SUPABASE SQL EDITOR TO APPLY ALL DATABASE CHANGES
-- =========================================================================

-- 1. CLEAN UP PREVIOUS VERSIONS TO PREVENT ARGUMENT OVERLOADS
DROP FUNCTION IF EXISTS public.process_qr_attendance(TEXT);
DROP FUNCTION IF EXISTS public.process_qr_attendance(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.process_scan_attendance_v3(TEXT, UUID, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.process_scan_attendance_v3(TEXT, UUID, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID);
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID, DATE);

-- 2. CREATE FUNCTION: process_qr_attendance
-- Now fully role-isolated, timezone-consistent, and date-standardized
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

        -- SHIFT VALIDATION: Validate shift window if configured
        IF v_shift_record IS NOT NULL THEN
            v_shift_start := v_shift_record.start_time_24h;
            v_shift_end := v_shift_record.end_time_24h;

            -- If current time is way outside shift window (allow 1 hr buffer before shift start)
            IF v_local_time < (v_shift_start - INTERVAL '1 hour')::TIME OR v_local_time > (v_shift_end + INTERVAL '2 hours')::TIME THEN
                v_err_msg := 'You are not assigned to this shift. Your shift is ' || 
                             COALESCE(v_shift_record.shift_type, 'Shift') || ' ' || 
                             COALESCE(v_shift_record.start_time, '') || ' - ' || COALESCE(v_shift_record.end_time, '') || '.';
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;
        END IF;

        -- Fetch existing staff attendance log for today (Timezone safe comparison)
        SELECT * INTO v_existing_log
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
        ORDER BY check_in DESC LIMIT 1;

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

-- 3. CREATE COMPATIBILITY FUNCTION: process_scan_attendance_v3
CREATE OR REPLACE FUNCTION public.process_scan_attendance_v3(
    p_token TEXT,
    p_user_id UUID DEFAULT NULL,
    p_method TEXT DEFAULT 'QR Code',
    p_ssid TEXT DEFAULT '',
    p_bssid TEXT DEFAULT '',
    p_user_type TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
BEGIN
    RETURN public.process_qr_attendance(p_token, p_user_type);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.process_scan_attendance_v3(TEXT, UUID, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

-- 4. CREATE FUNCTION: get_staff_today_attendance_details_v2
-- 100% database-isolated shift calculations, completely timezone-aware (Asia/Kolkata)
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
    
    -- Helper variables for robust shift mapping
    v_morning_shift_id UUID := NULL;
    v_evening_shift_id UUID := NULL;
    v_morning_log RECORD;
    v_evening_log RECORD;
    v_single_log RECORD;
BEGIN
    -- Resolve Staff Record details
    SELECT s.id, s.user_id, COALESCE(NULLIF(ssa.assignment_type, ''), NULLIF(s.shift, ''), 'Single Shift')
    INTO v_staff_id, v_profile_user_id, v_assigned_shift
    FROM public.staff s
    LEFT JOIN public.staff_shift_assignments ssa 
           ON (ssa.staff_id = s.id AND ssa.status = 'Active')
    WHERE (s.user_id = p_user_id OR s.id = p_user_id)
      AND s.gym_id = p_gym_id
    ORDER BY ssa.created_at DESC NULLS LAST
    LIMIT 1;

    IF v_staff_id IS NULL THEN
        SELECT s.id, s.user_id, COALESCE(s.shift, 'Single Shift')
        INTO v_staff_id, v_profile_user_id, v_assigned_shift
        FROM public.staff s
        WHERE (s.user_id = p_user_id OR s.id = p_user_id)
        LIMIT 1;
    END IF;

    -- Fetch morning shift ID and evening shift ID
    SELECT id INTO v_morning_shift_id FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Morning Shift';
    SELECT id INTO v_evening_shift_id FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Evening Shift';

    -- Fetch logs for today's local date (Asia/Kolkata) and map them
    IF v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN
        -- Morning shift log
        SELECT * INTO v_morning_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
          AND shift_id = v_morning_shift_id
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

        -- Set Morning Shift details
        IF v_morning_log.id IS NOT NULL THEN
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

        -- Set Evening Shift details
        IF v_evening_log.id IS NOT NULL THEN
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
        -- Single shift log
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
        v_can_check_in := TRUE;
        v_can_check_out := FALSE;
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
        'first_shift_name', 'Shift 1',
        'first_shift_check_in', v_first_check_in,
        'first_shift_check_out', v_first_check_out,
        'first_shift_status', COALESCE(v_first_shift_status, 'Not Checked In'),
        'second_shift_name', 'Shift 2',
        'second_shift_check_in', v_second_check_in,
        'second_shift_check_out', v_second_check_out,
        'second_shift_status', COALESCE(v_second_shift_status, 'Not Checked In'),
        'is_checked_in', (v_open_log_id IS NOT NULL)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_today_attendance_details_v2(UUID, UUID, DATE) TO anon, authenticated, service_role;


-- =========================================================================
-- 5. NEW SHIFT-AWARE AUTO-ABSENT LOGIC
-- Marks staff absent 1 hr after shift ends if no check-in exists.
-- Support both single shifts and two separate shifts (Both Shifts).
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
    
    -- Variables for checking both today and yesterday to cover midnight crossovers
    v_check_date DATE;
    v_check_date_str TEXT;
BEGIN
    -- Loop through gyms where auto_mark_absent is enabled
    FOR v_gym IN 
        SELECT gym_id 
        FROM public.attendance_settings 
        WHERE auto_mark_absent = TRUE
    LOOP
        -- ==========================================
        -- 1. STAFF AUTO-ABSENT ENGINE
        -- ==========================================
        FOR v_staff IN 
            SELECT id, user_id 
            FROM public.staff 
            WHERE gym_id = v_gym.gym_id AND status = 'Active'
        LOOP
            -- Get active shift assignment
            SELECT * INTO v_assignment 
            FROM public.staff_shift_assignments 
            WHERE staff_id = v_staff.id AND gym_id = v_gym.gym_id AND status = 'Active'
            LIMIT 1;
            
            IF v_assignment IS NOT NULL THEN
                -- Check both today and yesterday
                FOR v_check_date IN SELECT v_local_date UNION SELECT (v_local_date - 1) LOOP
                    v_check_date_str := to_char(v_check_date, 'dd-MM-yyyy');
                    
                    -- CASE A: Both Shifts Assigned
                    IF v_assignment.assignment_type = 'Both Shifts' THEN
                        -- Check Morning Shift
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
                        
                        -- Check Evening Shift
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
                    
                    -- CASE B: Single/Morning/Evening Shift
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

        -- ==========================================
        -- 2. MEMBER AUTO-ABSENT ENGINE
        -- ==========================================
        -- Fetch the latest shift end time in the gym. Fallback to 10:00 PM if no shifts.
        SELECT COALESCE(MAX(end_time_24h), '22:00:00'::TIME) INTO v_latest_shift_end
        FROM public.gym_shifts
        WHERE gym_id = v_gym.gym_id;

        -- Trigger at 2 hours after latest shift ends
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

-- 5. REBUILD STAFF WEEKLY SUMMARY RPC (WITH DOUBLE/DECIMAL SUPPORT)
DROP FUNCTION IF EXISTS public.get_staff_weekly_summary_v1(UUID, UUID);
CREATE OR REPLACE FUNCTION public.get_staff_weekly_summary_v1(
    p_user_id UUID,
    p_gym_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_of_week DATE := date_trunc('week', CURRENT_DATE)::DATE;
    v_end_of_week DATE := CURRENT_DATE;
    v_present_count NUMERIC := 0.0;
    v_absent_count NUMERIC := 0.0;
    v_late_count NUMERIC := 0.0;
    v_total_days INT := 0;
    v_log RECORD;
    v_shift_type TEXT;
BEGIN
    -- Get staff shift assignment type
    SELECT COALESCE(NULLIF(ssa.assignment_type, ''), NULLIF(s.shift, ''), 'Single Shift')
    INTO v_shift_type
    FROM public.staff s
    LEFT JOIN public.staff_shift_assignments ssa 
           ON (ssa.staff_id = s.id AND ssa.status = 'Active')
    WHERE s.user_id = p_user_id AND s.gym_id = p_gym_id
    LIMIT 1;

    IF v_shift_type IS NULL THEN
        v_shift_type := 'Single Shift';
    END IF;

    -- Count total days of check-in
    SELECT COUNT(DISTINCT check_in::DATE)::INT INTO v_total_days
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id
      AND user_id = p_user_id
      AND user_type = 'Staff'
      AND check_in::DATE >= v_start_of_week
      AND check_in::DATE <= v_end_of_week;

    -- Loop through weekly logs and sum weights
    FOR v_log IN 
        SELECT status, late_minutes, shift_id
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND user_id = p_user_id
          AND user_type = 'Staff'
          AND check_in::DATE >= v_start_of_week
          AND check_in::DATE <= v_end_of_week
    LOOP
        IF v_shift_type IN ('Two Shifts', 'Both Shifts') THEN
            -- Each log is 0.5 weight
            IF v_log.status IN ('Present', 'Overtime', 'Early Exit') THEN
                v_present_count := v_present_count + 0.5;
            ELSIF v_log.status = 'Late' OR COALESCE(v_log.late_minutes, 0) > 0 THEN
                v_present_count := v_present_count + 0.5;
                v_late_count := v_late_count + 0.5;
            ELSIF v_log.status IN ('Absent', 'On Leave', 'Leave') THEN
                v_absent_count := v_absent_count + 0.5;
            END IF;
        ELSE
            -- Single Shift
            IF v_log.status = 'Half Leave' THEN
                v_present_count := v_present_count + 0.5;
                v_absent_count := v_absent_count + 0.5;
            ELSIF v_log.status IN ('Present', 'Overtime', 'Early Exit') THEN
                v_present_count := v_present_count + 1.0;
            ELSIF v_log.status = 'Late' OR COALESCE(v_log.late_minutes, 0) > 0 THEN
                v_present_count := v_present_count + 1.0;
                v_late_count := v_late_count + 1.0;
            ELSIF v_log.status IN ('Absent', 'On Leave', 'Leave') THEN
                v_absent_count := v_absent_count + 1.0;
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'present', COALESCE(v_present_count, 0.0),
        'absent', COALESCE(v_absent_count, 0.0),
        'late', COALESCE(v_late_count, 0.0),
        'total', COALESCE(v_total_days, 0)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_weekly_summary_v1(UUID, UUID) TO anon, authenticated, service_role;

-- 5.2 REBUILD MEMBER ATTENDANCE STREAK & WEEKLY CHECKLIST RPC
DROP FUNCTION IF EXISTS public.get_member_attendance_streak_v1(UUID, UUID);
CREATE OR REPLACE FUNCTION public.get_member_attendance_streak_v1(
    p_user_id UUID,
    p_gym_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_local_now TIMESTAMP := now() AT TIME ZONE 'Asia/Kolkata';
    v_monday DATE := date_trunc('week', v_local_now)::DATE;
    v_date DATE;
    v_date_str TEXT;
    v_week_attendance BOOLEAN[] := ARRAY[]::BOOLEAN[];
    v_week_dates INT[] := ARRAY[]::INT[];
    v_exists BOOLEAN;
    
    -- Streak variables
    v_streak INT := 0;
    v_check_date DATE := v_local_now::DATE;
    v_today_str TEXT := to_char(v_check_date, 'DD-MM-YYYY');
    v_yesterday_str TEXT := to_char(v_check_date - 1, 'DD-MM-YYYY');
    v_has_today BOOLEAN;
    v_has_yesterday BOOLEAN;
BEGIN
    -- 1. Generate Weekly Attendance Checklist (Monday to Sunday)
    FOR i IN 0..6 LOOP
        v_date := v_monday + i;
        v_date_str := to_char(v_date, 'DD-MM-YYYY');
        
        SELECT EXISTS (
            SELECT 1 FROM public.attendance_logs
            WHERE user_id = p_user_id
              AND date = v_date_str
              AND status NOT IN ('Absent', 'On Leave', 'Leave')
        ) INTO v_exists;
        
        v_week_attendance := array_append(v_week_attendance, v_exists);
        v_week_dates := array_append(v_week_dates, extract(day from v_date)::INT);
    END LOOP;

    -- 2. Calculate Streak Dynamically (Skipping Sundays)
    SELECT EXISTS (
        SELECT 1 FROM public.attendance_logs
        WHERE user_id = p_user_id
          AND date = v_today_str
          AND status NOT IN ('Absent', 'On Leave', 'Leave')
    ) INTO v_has_today;
    
    SELECT EXISTS (
        SELECT 1 FROM public.attendance_logs
        WHERE user_id = p_user_id
          AND date = v_yesterday_str
          AND status NOT IN ('Absent', 'On Leave', 'Leave')
    ) INTO v_has_yesterday;
    
    IF v_has_today THEN
        v_streak := 1;
        v_check_date := v_check_date - 1;
        LOOP
            IF extract(isodow from v_check_date) = 7 THEN
                v_check_date := v_check_date - 1;
                CONTINUE;
            END IF;
            
            SELECT EXISTS (
                SELECT 1 FROM public.attendance_logs
                WHERE user_id = p_user_id
                  AND date = to_char(v_check_date, 'DD-MM-YYYY')
                  AND status NOT IN ('Absent', 'On Leave', 'Leave')
            ) INTO v_exists;
            
            IF v_exists THEN
                v_streak := v_streak + 1;
                v_check_date := v_check_date - 1;
            ELSE
                EXIT;
            END IF;
        END LOOP;
    ELSIF v_has_yesterday THEN
        v_streak := 1;
        v_check_date := v_check_date - 2;
        LOOP
            IF extract(isodow from v_check_date) = 7 THEN
                v_check_date := v_check_date - 1;
                CONTINUE;
            END IF;
            
            SELECT EXISTS (
                SELECT 1 FROM public.attendance_logs
                WHERE user_id = p_user_id
                  AND date = to_char(v_check_date, 'DD-MM-YYYY')
                  AND status NOT IN ('Absent', 'On Leave', 'Leave')
            ) INTO v_exists;
            
            IF v_exists THEN
                v_streak := v_streak + 1;
                v_check_date := v_check_date - 1;
            ELSE
                EXIT;
            END IF;
        END LOOP;
    ELSE
        v_streak := 0;
    END IF;

    RETURN jsonb_build_object(
        'current_streak', v_streak,
        'week_attendance', to_jsonb(v_week_attendance),
        'week_dates', to_jsonb(v_week_dates)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_member_attendance_streak_v1(UUID, UUID) TO anon, authenticated, service_role;

-- 6. REGISTER CRON SCHEDULE IN PG_CRON
-- 5.3 ADD DYNAMIC PERMISSIONS TO STAFF TABLE
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS permissions JSONB DEFAULT '{"add_member": true, "scan_attendance": true, "renew_membership": true, "add_income": true, "add_expense": true, "take_payment": true, "send_reminder": true, "broadcast": false}'::jsonb NOT NULL;

-- 5.4 CREATE ACTIVITY LOGS AUDIT TABLE
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE,
    staff_name TEXT NOT NULL,
    staff_role TEXT NOT NULL,
    action TEXT NOT NULL,
    module TEXT NOT NULL,
    target_member TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- RLS for activity_logs
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS activity_logs_isolation_policy ON public.activity_logs;
CREATE POLICY activity_logs_isolation_policy ON public.activity_logs
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

GRANT SELECT, INSERT ON public.activity_logs TO anon, authenticated;

-- Activity logging RPC function
CREATE OR REPLACE FUNCTION public.log_activity(
    p_gym_id UUID,
    p_staff_id UUID,
    p_action TEXT,
    p_module TEXT,
    p_target_member TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff_name TEXT;
    v_staff_role TEXT;
BEGIN
    SELECT name, role INTO v_staff_name, v_staff_role 
    FROM public.staff 
    WHERE id = p_staff_id;

    INSERT INTO public.activity_logs (
        gym_id, staff_id, staff_name, staff_role, action, module, target_member
    ) VALUES (
        p_gym_id, p_staff_id, COALESCE(v_staff_name, 'Unknown'), COALESCE(v_staff_role, 'Staff'), p_action, p_module, p_target_member
    );
END;
$$;

-- 5.5 BACKEND SECURITY: PERMISSIONS ENFORCEMENT FUNCTION
CREATE OR REPLACE FUNCTION public.check_staff_action_permissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_gym_id UUID;
    v_staff RECORD;
    v_has_permission BOOLEAN := TRUE;
    v_action_needed TEXT;
BEGIN
    -- Determine gym_id and action type depending on table
    IF TG_TABLE_NAME = 'members' THEN
        v_gym_id := NEW.gym_id;
        v_action_needed := 'add_member';
    ELSIF TG_TABLE_NAME = 'attendance_logs' THEN
        v_gym_id := NEW.gym_id;
        v_action_needed := 'scan_attendance';
    ELSIF TG_TABLE_NAME = 'member_memberships' THEN
        v_gym_id := NEW.gym_id;
        v_action_needed := 'renew_membership';
    ELSIF TG_TABLE_NAME = 'transactions' THEN
        v_gym_id := NEW.gym_id;
        IF NEW.type = 'Revenue' THEN
            v_action_needed := 'add_income';
        ELSE
            v_action_needed := 'add_expense';
        END IF;
    END IF;

    -- Only apply checks if the user is a staff member
    IF v_user_id IS NOT NULL AND v_gym_id IS NOT NULL THEN
        SELECT * INTO v_staff FROM public.staff WHERE user_id = v_user_id AND gym_id = v_gym_id;
        IF v_staff IS NOT NULL AND LOWER(v_staff.role) IN ('receptionist', 'reception') THEN
            IF v_staff.permissions ? v_action_needed THEN
                v_has_permission := (v_staff.permissions ->> v_action_needed)::BOOLEAN;
            ELSE
                v_has_permission := TRUE; -- default to true if key not present
            END IF;

            IF NOT v_has_permission THEN
                RAISE EXCEPTION '403 Forbidden: Action is restricted by gym owner';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Register Triggers
DROP TRIGGER IF EXISTS trg_check_members_permission ON public.members;
CREATE TRIGGER trg_check_members_permission
BEFORE INSERT OR UPDATE ON public.members
FOR EACH ROW EXECUTE FUNCTION public.check_staff_action_permissions();

DROP TRIGGER IF EXISTS trg_check_attendance_permission ON public.attendance_logs;
CREATE TRIGGER trg_check_attendance_permission
BEFORE INSERT OR UPDATE ON public.attendance_logs
FOR EACH ROW EXECUTE FUNCTION public.check_staff_action_permissions();

DROP TRIGGER IF EXISTS trg_check_memberships_permission ON public.member_memberships;
CREATE TRIGGER trg_check_memberships_permission
BEFORE INSERT OR UPDATE ON public.member_memberships
FOR EACH ROW EXECUTE FUNCTION public.check_staff_action_permissions();

DROP TRIGGER IF EXISTS trg_check_transactions_permission ON public.transactions;
CREATE TRIGGER trg_check_transactions_permission
BEFORE INSERT OR UPDATE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.check_staff_action_permissions();

-- Automatically triggers auto-absent logic every 30 minutes.
-- (Will execute silently if pg_cron is enabled in Supabase, else ignore safely)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
    ) THEN
        PERFORM cron.unschedule('mark_absent_job');
        PERFORM cron.schedule('mark_absent_job', '*/30 * * * *', 'SELECT public.cron_auto_mark_absent()');
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;
