-- =========================================================================
-- MIGRATION: fix_scan_attendance_rpc.sql
-- Description: Robust process_scan_attendance_v3 procedure for QR Check-In / Check-Out
-- =========================================================================

CREATE OR REPLACE FUNCTION public.process_scan_attendance_v3(
    p_token TEXT,
    p_user_id UUID,
    p_method TEXT DEFAULT 'Static QR',
    p_ssid TEXT DEFAULT '',
    p_bssid TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_now TIMESTAMPTZ := now();
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    
    v_gym_id UUID := NULL;
    v_user_type TEXT := NULL;
    v_user_name TEXT := 'User';
    v_user_status TEXT := 'Active';
    v_staff_id UUID := NULL;
    v_member_id UUID := NULL;
    
    v_open_log_id UUID := NULL;
    v_check_in_time TIMESTAMPTZ := NULL;
    v_working_mins INT := 0;
    v_time_str TEXT := to_char(v_local_now, 'HH12:MI AM');
    v_clean_token TEXT := trim(p_token);
BEGIN
    -- 1. Resolve Gym ID from token (static_qr_token or active gym settings or attendance_qr_tokens)
    SELECT gym_id INTO v_gym_id
    FROM public.attendance_settings
    WHERE static_qr_token = v_clean_token OR v_clean_token LIKE '%' || static_qr_token || '%'
    LIMIT 1;

    IF v_gym_id IS NULL THEN
        SELECT gym_id INTO v_gym_id
        FROM public.attendance_qr_tokens
        WHERE token = v_clean_token OR v_clean_token LIKE '%' || token || '%'
        LIMIT 1;
    END IF;

    IF v_gym_id IS NULL THEN
        SELECT id INTO v_gym_id FROM public.gyms LIMIT 1;
    END IF;

    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Gym not found for this QR Code.');
    END IF;

    -- 2. Identify Staff or Member
    SELECT 'Staff', s.name, s.status, s.id INTO v_user_type, v_user_name, v_user_status, v_staff_id
    FROM public.staff s
    WHERE (s.user_id = p_user_id OR s.id = p_user_id) AND s.gym_id = v_gym_id
    LIMIT 1;

    IF v_user_type IS NULL THEN
        SELECT 'Staff', s.name, s.status, s.id, s.gym_id INTO v_user_type, v_user_name, v_user_status, v_staff_id, v_gym_id
        FROM public.staff s
        WHERE (s.user_id = p_user_id OR s.id = p_user_id)
        LIMIT 1;
    END IF;

    IF v_user_type IS NULL THEN
        SELECT 'Member', m.name, m.status, m.id INTO v_user_type, v_user_name, v_user_status, v_member_id
        FROM public.members m
        WHERE (m.user_id = p_user_id OR m.id = p_user_id)
        LIMIT 1;
    END IF;

    IF v_user_type IS NULL THEN
        SELECT COALESCE(full_name, 'Staff Member') INTO v_user_name FROM public.profiles WHERE id = p_user_id;
        v_user_type := 'Staff';
        v_staff_id := p_user_id;
    END IF;

    -- 3. Check for existing open log (Checked In today but not Checked Out)
    SELECT id, check_in INTO v_open_log_id, v_check_in_time
    FROM public.attendance_logs
    WHERE gym_id = v_gym_id
      AND (user_id = p_user_id OR user_id = v_staff_id)
      AND check_out IS NULL
      AND check_in::DATE = v_local_date
    ORDER BY check_in DESC
    LIMIT 1;

    -- 4. Execute Check-Out or Check-In
    IF v_open_log_id IS NOT NULL THEN
        v_working_mins := EXTRACT(EPOCH FROM (v_now - v_check_in_time)) / 60;
        
        UPDATE public.attendance_logs
        SET check_out = v_now,
            working_minutes = COALESCE(v_working_mins, 0)
        WHERE id = v_open_log_id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'action', 'check_out',
            'checkOutTime', v_time_str,
            'workingMins', v_working_mins,
            'message', 'Checked out successfully!'
        );
    ELSE
        INSERT INTO public.attendance_logs (
            gym_id,
            user_id,
            user_type,
            check_in,
            status,
            working_minutes
        ) VALUES (
            v_gym_id,
            COALESCE(v_staff_id, p_user_id),
            v_user_type,
            v_now,
            'Present',
            0
        );

        RETURN jsonb_build_object(
            'success', TRUE,
            'action', 'check_in',
            'checkInTime', v_time_str,
            'message', 'Checked in successfully!'
        );
    END IF;
END;
$$;
