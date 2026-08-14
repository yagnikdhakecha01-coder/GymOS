-- =========================================================================
-- FIX OWNER ATTENDANCE, UNIQUE CONSTRAINT 23505 & DISPLAY DEVICE LINK
-- Run this script in Supabase SQL Editor
-- =========================================================================

-- 1. DROP RASH UNIQUE INDEXES & CREATE SAFE MULTI-SHIFT UNIQUE INDEX
DROP INDEX IF EXISTS public.uniq_member_attendance_date;
DROP INDEX IF EXISTS public.uniq_staff_attendance_date_shift;
DROP INDEX IF EXISTS public.uniq_attendance_user_date_shift;

CREATE UNIQUE INDEX uniq_attendance_user_date_shift 
ON public.attendance_logs (user_id, date, COALESCE(shift_index, 1));


-- 2. TABLE GRANTS FOR DISPLAY MANAGEMENT & ATTENDANCE LOGS
GRANT ALL ON TABLE public.attendance_displays TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_display_tokens TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_logs TO anon, authenticated, service_role;


-- 3. FIX DISPLAY CREATION RPC (PRE-VERIFY PRIMARY DISPLAY DEVICE)
CREATE OR REPLACE FUNCTION public.get_or_create_gym_display(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_public_id TEXT;
    v_display_id UUID;
BEGIN
    SELECT id, display_public_id INTO v_display_id, v_public_id
    FROM public.attendance_displays
    WHERE gym_id = p_gym_id
    LIMIT 1;

    IF v_public_id IS NULL THEN
        v_public_id := public.fn_generate_display_public_id();
        INSERT INTO public.attendance_displays (gym_id, display_public_id, device_name, is_verified, is_enabled)
        VALUES (p_gym_id, v_public_id, 'Primary Kiosk Display', TRUE, TRUE)
        RETURNING id INTO v_display_id;
    ELSE
        -- Ensure primary display is verified & active
        UPDATE public.attendance_displays
        SET is_verified = TRUE, is_enabled = TRUE, last_seen = now()
        WHERE id = v_display_id;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'display_public_id', v_public_id,
        'display_id', v_display_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_or_create_gym_display(UUID) TO anon, authenticated, service_role;


-- 4. UPDATE PROCESS QR ATTENDANCE TO SAFELY OVERWRITE AUTO-ABSENT & HANDLE CHECK-OUT
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

    v_gym_id UUID;
    v_display_id UUID;
    v_token_expires TIMESTAMPTZ;
    v_token_used BOOLEAN;
    v_qr_type TEXT := 'Dynamic';

    v_resolved_user_type TEXT := NULL;
    v_user_name TEXT;
    v_member_id UUID;
    v_staff_id UUID;

    v_existing_log RECORD;
    v_log_id UUID;
    v_working_mins INT := 0;
BEGIN
    IF v_scanner_uid IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User not authenticated. Please log in.');
    END IF;

    -- Validate Token
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

        UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
    ELSE
        -- Fallback to Static Token check in gym_settings
        SELECT gym_id INTO v_gym_id
        FROM public.attendance_settings
        WHERE static_qr_token = p_token
        LIMIT 1;

        IF v_gym_id IS NULL THEN
            -- Check user associations for single gym fallback
            SELECT gym_id INTO v_gym_id
            FROM public.user_gym_associations
            WHERE user_id = v_scanner_uid
            LIMIT 1;
        END IF;

        v_qr_type := 'Static';
    END IF;

    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid QR code or Gym association not found.');
    END IF;

    -- Resolve User Profile / Role
    SELECT full_name INTO v_user_name FROM public.profiles WHERE id = v_scanner_uid;

    SELECT id INTO v_staff_id FROM public.staff WHERE user_id = v_scanner_uid AND gym_id = v_gym_id LIMIT 1;
    IF v_staff_id IS NOT NULL THEN
        v_resolved_user_type := 'Staff';
    ELSE
        SELECT id INTO v_member_id FROM public.members WHERE user_id = v_scanner_uid AND gym_id = v_gym_id LIMIT 1;
        IF v_member_id IS NOT NULL THEN
            v_resolved_user_type := 'Member';
        ELSE
            -- Default to Member/User check-in
            v_resolved_user_type := COALESCE(p_user_type, 'Member');
        END IF;
    END IF;

    -- Check for existing log today
    SELECT * INTO v_existing_log
    FROM public.attendance_logs
    WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id OR member_id = v_member_id)
      AND gym_id = v_gym_id
      AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
    ORDER BY check_in DESC
    LIMIT 1;

    -- CASE 1: Open Log -> Perform Check-Out
    IF v_existing_log.id IS NOT NULL AND v_existing_log.check_out IS NULL AND v_existing_log.status != 'Absent' THEN
        v_working_mins := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 60)::INT);

        UPDATE public.attendance_logs
        SET check_out = now(),
            working_minutes = v_working_mins,
            shift_status = 'Completed'
        WHERE id = v_existing_log.id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'action', 'CHECK_OUT',
            'user_type', v_resolved_user_type,
            'user_name', COALESCE(v_user_name, 'User'),
            'status', 'Checked Out',
            'check_out', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
            'working_minutes', v_working_mins,
            'message', 'Attendance checked out successfully!'
        );
    END IF;

    -- CASE 2: Auto-Absent Log Exists -> Overwrite with active Check-In!
    IF v_existing_log.id IS NOT NULL AND (v_existing_log.status = 'Absent' OR v_existing_log.method = 'Auto-Absent') THEN
        UPDATE public.attendance_logs
        SET check_in = now(),
            check_out = NULL,
            status = 'Present',
            method = COALESCE(v_qr_type || ' QR', 'QR Code'),
            working_minutes = 0,
            shift_status = 'In Progress'
        WHERE id = v_existing_log.id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'action', 'CHECK_IN',
            'user_type', v_resolved_user_type,
            'user_name', COALESCE(v_user_name, 'User'),
            'status', 'Present',
            'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
            'attendance_date', v_local_date_str,
            'message', 'Attendance checked in successfully!'
        );
    END IF;

    -- CASE 3: Completed Log Exists for Today (and not absent) -> Already Checked In/Out
    IF v_existing_log.id IS NOT NULL AND v_existing_log.check_out IS NOT NULL AND v_existing_log.status != 'Absent' THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'already_marked', TRUE,
            'action', 'ALREADY_COMPLETED',
            'user_type', v_resolved_user_type,
            'user_name', COALESCE(v_user_name, 'User'),
            'status', v_existing_log.status,
            'check_in', to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
            'check_out', to_char(v_existing_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
            'message', 'Attendance already completed for today!'
        );
    END IF;

    -- CASE 4: New Check-In Insertion (Safe against 23505)
    BEGIN
        INSERT INTO public.attendance_logs (
            gym_id, user_id, role, user_type, staff_id, member_id, date, check_in, status, shift_status, method, qr_type
        ) VALUES (
            v_gym_id, v_scanner_uid, v_resolved_user_type, v_resolved_user_type, v_staff_id, v_member_id, v_local_date_str, now(), 'Present', 'In Progress', COALESCE(v_qr_type || ' QR', 'QR Code'), v_qr_type
        ) RETURNING id INTO v_log_id;
    EXCEPTION WHEN unique_violation THEN
        -- Safely handle race condition / constraint
        SELECT id INTO v_log_id FROM public.attendance_logs
        WHERE (user_id = v_scanner_uid OR staff_id = v_staff_id) AND gym_id = v_gym_id AND date = v_local_date_str
        LIMIT 1;

        UPDATE public.attendance_logs
        SET check_in = now(), status = 'Present', method = COALESCE(v_qr_type || ' QR', 'QR Code')
        WHERE id = v_log_id;
    END;

    RETURN jsonb_build_object(
        'success', TRUE,
        'action', 'CHECK_IN',
        'user_type', v_resolved_user_type,
        'user_name', COALESCE(v_user_name, 'User'),
        'status', 'Present',
        'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
        'attendance_date', v_local_date_str,
        'message', 'Attendance checked in successfully!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.process_qr_attendance(TEXT, TEXT) TO anon, authenticated, service_role;
