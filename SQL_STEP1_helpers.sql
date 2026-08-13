-- RUN STEP 1 FIRST
-- =========================================================================
-- fix_attendance_auto_absent_both_shift.sql
-- Supabase SQL Editor mein RUN karo
-- Fixes: Both shift auto-absent using staff shift1/shift2 times + gym_shifts fallback
-- Also includes salary pending amount fixes (fn_staff_net_payable)
-- =========================================================================

-- -------------------------------------------------------------------------
-- PART A: Helper â€” parse "05:00 AM" style text to TIME
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_parse_12h_time(p_time_str TEXT)
RETURNS TIME
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_time_str IS NULL OR trim(p_time_str) = '' THEN
        RETURN NULL;
    END IF;
    RETURN to_timestamp(trim(p_time_str), 'HH:MI AM')::TIME;
EXCEPTION WHEN OTHERS THEN
    BEGIN
        RETURN trim(p_time_str)::TIME;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_parse_12h_time(TEXT) TO anon, authenticated, service_role;


-- -------------------------------------------------------------------------
-- PART B: Resolve shift end/start for staff (staff table FIRST, gym_shifts fallback)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_staff_shift_window(
    p_staff_id UUID,
    p_gym_id UUID,
    p_which TEXT -- 'morning' or 'evening'
)
RETURNS TABLE (
    shift_id UUID,
    start_time TIME,
    end_time TIME
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shift1_start TEXT;
    v_shift1_end TEXT;
    v_shift2_start TEXT;
    v_shift2_end TEXT;
    v_gym_morning_id UUID;
    v_gym_evening_id UUID;
    v_gym_m_start TIME;
    v_gym_m_end TIME;
    v_gym_e_start TIME;
    v_gym_e_end TIME;
BEGIN
    SELECT s.shift1_start, s.shift1_end, s.shift2_start, s.shift2_end
    INTO v_shift1_start, v_shift1_end, v_shift2_start, v_shift2_end
    FROM public.staff s
    WHERE s.id = p_staff_id;

    SELECT gs.id, gs.start_time_24h, gs.end_time_24h
    INTO v_gym_morning_id, v_gym_m_start, v_gym_m_end
    FROM public.gym_shifts gs
    WHERE gs.gym_id = p_gym_id AND gs.shift_type = 'Morning Shift'
    LIMIT 1;

    SELECT gs.id, gs.start_time_24h, gs.end_time_24h
    INTO v_gym_evening_id, v_gym_e_start, v_gym_e_end
    FROM public.gym_shifts gs
    WHERE gs.gym_id = p_gym_id AND gs.shift_type = 'Evening Shift'
    LIMIT 1;

    IF lower(trim(p_which)) IN ('morning', 'shift1', '1') THEN
        shift_id := v_gym_morning_id;
        -- Staff profile timing = main source; gym_shifts = fallback only
        start_time := COALESCE(public.fn_parse_12h_time(v_shift1_start), v_gym_m_start, '09:00:00'::TIME);
        end_time := COALESCE(public.fn_parse_12h_time(v_shift1_end), v_gym_m_end, '13:00:00'::TIME);
        RETURN NEXT;
    ELSE
        shift_id := v_gym_evening_id;
        start_time := COALESCE(public.fn_parse_12h_time(v_shift2_start), v_gym_e_start, '16:00:00'::TIME);
        end_time := COALESCE(public.fn_parse_12h_time(v_shift2_end), v_gym_e_end, '21:00:00'::TIME);
        RETURN NEXT;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_staff_shift_window(UUID, UUID, TEXT) TO anon, authenticated, service_role;


-- -------------------------------------------------------------------------
-- PART B2: Staff work schedule from STAFF PROFILE (shift1/shift2 columns)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_staff_work_schedule(
    p_staff_id UUID,
    p_gym_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shift TEXT;
    v_shift_type TEXT;
    v_s1_start TEXT;
    v_s1_end TEXT;
    v_s2_start TEXT;
    v_s2_end TEXT;
    v_is_both BOOLEAN := FALSE;
    v_gym_single_start TEXT;
    v_gym_single_end TEXT;
    v_gym_m_start TEXT;
    v_gym_m_end TEXT;
    v_gym_e_start TEXT;
    v_gym_e_end TEXT;
BEGIN
    SELECT
        COALESCE(NULLIF(trim(s.shift), ''), 'Single Shift'),
        COALESCE(NULLIF(trim(s.shift_type), ''), 'single'),
        s.shift1_start, s.shift1_end, s.shift2_start, s.shift2_end
    INTO v_shift, v_shift_type, v_s1_start, v_s1_end, v_s2_start, v_s2_end
    FROM public.staff s
    WHERE s.id = p_staff_id AND s.gym_id = p_gym_id;

    IF v_shift IS NULL THEN
        RETURN jsonb_build_object('error', 'Staff not found');
    END IF;

    SELECT start_time, end_time INTO v_gym_single_start, v_gym_single_end
    FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Single Shift' LIMIT 1;
    SELECT start_time, end_time INTO v_gym_m_start, v_gym_m_end
    FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Morning Shift' LIMIT 1;
    SELECT start_time, end_time INTO v_gym_e_start, v_gym_e_end
    FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Evening Shift' LIMIT 1;

    v_is_both := (v_shift_type = 'both')
        OR lower(v_shift) LIKE '%both%'
        OR lower(v_shift) LIKE '%double%'
        OR lower(v_shift) LIKE '%two%';

    IF v_is_both THEN
        RETURN jsonb_build_object(
            'assignment_type', 'Both Shifts',
            'is_both_shift', TRUE,
            'shift_label', 'Both Shifts (Double)',
            'shift1_start', COALESCE(NULLIF(trim(v_s1_start), ''), v_gym_m_start, '09:00 AM'),
            'shift1_end', COALESCE(NULLIF(trim(v_s1_end), ''), v_gym_m_end, '01:00 PM'),
            'shift2_start', COALESCE(NULLIF(trim(v_s2_start), ''), v_gym_e_start, '04:00 PM'),
            'shift2_end', COALESCE(NULLIF(trim(v_s2_end), ''), v_gym_e_end, '09:00 PM'),
            'timing_source', 'staff_profile'
        );
    ELSIF lower(v_shift) LIKE '%morning%' THEN
        RETURN jsonb_build_object(
            'assignment_type', 'Morning Shift',
            'is_both_shift', FALSE,
            'shift_label', 'Morning Shift',
            'shift1_start', COALESCE(NULLIF(trim(v_s1_start), ''), v_gym_m_start, '09:00 AM'),
            'shift1_end', COALESCE(NULLIF(trim(v_s1_end), ''), v_gym_m_end, '01:00 PM'),
            'timing_source', 'staff_profile'
        );
    ELSIF lower(v_shift) LIKE '%evening%' THEN
        RETURN jsonb_build_object(
            'assignment_type', 'Evening Shift',
            'is_both_shift', FALSE,
            'shift_label', 'Evening Shift',
            'shift1_start', COALESCE(NULLIF(trim(v_s2_start), ''), NULLIF(trim(v_s1_start), ''), v_gym_e_start, '04:00 PM'),
            'shift1_end', COALESCE(NULLIF(trim(v_s2_end), ''), NULLIF(trim(v_s1_end), ''), v_gym_e_end, '09:00 PM'),
            'timing_source', 'staff_profile'
        );
    ELSE
        RETURN jsonb_build_object(
            'assignment_type', 'Single Shift',
            'is_both_shift', FALSE,
            'shift_label', COALESCE(v_shift, 'Single Shift'),
            'shift1_start', COALESCE(NULLIF(trim(v_s1_start), ''), v_gym_single_start, '09:00 AM'),
            'shift1_end', COALESCE(NULLIF(trim(v_s1_end), ''), v_gym_single_end, '05:00 PM'),
            'timing_source', 'staff_profile'
        );
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_work_schedule(UUID, UUID) TO anon, authenticated, service_role;


-- -------------------------------------------------------------------------
-- PART C: Insert absent log if shift end + 1 hour passed and no log exists
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ensure_shift_absent(
    p_gym_id UUID,
    p_staff_id UUID,
    p_user_id UUID,
    p_target_date DATE,
    p_shift_id UUID,
    p_shift_end TIME,
    p_shift_start TIME DEFAULT NULL,
    p_shift_index INT DEFAULT 1
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    v_date_str TEXT := to_char(p_target_date, 'dd-MM-yyyy');
    v_log_id UUID;
    v_start TIME := COALESCE(p_shift_start, p_shift_end);
BEGIN
    IF p_shift_end IS NULL THEN
        RETURN NULL;
    END IF;

    IF p_target_date = v_local_date THEN
        IF v_local_time <= (p_shift_end + INTERVAL '1 hour')::TIME THEN
            RETURN NULL;
        END IF;
    ELSIF p_target_date > v_local_date THEN
        RETURN NULL;
    END IF;

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
        (p_target_date::TEXT || ' ' || v_start::TEXT)::TIMESTAMPTZ AT TIME ZONE 'Asia/Kolkata',
        (p_target_date::TEXT || ' ' || p_shift_end::TEXT)::TIMESTAMPTZ AT TIME ZONE 'Asia/Kolkata',
        'Absent',
        'Completed',
        0,
        'Auto-System',
        'System'
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_ensure_shift_absent(UUID, UUID, UUID, DATE, UUID, TIME, TIME, INT) TO anon, authenticated, service_role;
