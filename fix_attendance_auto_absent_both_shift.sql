-- =========================================================================
-- fix_attendance_auto_absent_both_shift.sql
-- Supabase SQL Editor mein RUN karo
-- Fixes: Both shift auto-absent using staff shift1/shift2 times + gym_shifts fallback
-- Also includes salary pending amount fixes (fn_staff_net_payable)
-- =========================================================================

-- -------------------------------------------------------------------------
-- PART A: Helper — parse "05:00 AM" style text to TIME
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


-- -------------------------------------------------------------------------
-- PART D: Rebuild get_staff_today_attendance_details_v2 (auto-absent + staff shift times)
-- -------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID);
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID, DATE);

CREATE OR REPLACE FUNCTION public.get_staff_today_attendance_details_v2(
    p_user_id UUID,
    p_gym_id UUID,
    p_date DATE DEFAULT (now() AT TIME ZONE 'Asia/Kolkata')::DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_staff_id UUID;
    v_profile_user_id UUID;
    v_staff_status TEXT;
    v_shift_type TEXT;
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

    v_morning_shift_id UUID;
    v_evening_shift_id UUID;
    v_morning_start TIME;
    v_morning_end TIME;
    v_evening_start TIME;
    v_evening_end TIME;

    v_morning_log RECORD;
    v_evening_log RECORD;
    v_single_log RECORD;

    v_local_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;
    v_date_str TEXT := to_char(p_date, 'dd-MM-yyyy');
    v_absent_log_id UUID;
BEGIN
    SELECT s.id, s.user_id, s.status,
           COALESCE(NULLIF(trim(s.shift), ''), 'Single Shift'),
           COALESCE(NULLIF(trim(s.shift_type), ''), 'single')
    INTO v_staff_id, v_profile_user_id, v_staff_status, v_assigned_shift, v_shift_type
    FROM public.staff s
    WHERE (s.user_id = p_user_id OR s.id = p_user_id)
      AND s.gym_id = p_gym_id
    LIMIT 1;

    -- Both shift from staff profile (shift_type / shift label)
    IF v_shift_type = 'both'
        OR lower(v_assigned_shift) LIKE '%both%'
        OR lower(v_assigned_shift) LIKE '%double%'
        OR lower(v_assigned_shift) LIKE '%two%' THEN
        v_assigned_shift := 'Two Shifts';
        v_shift_type := 'both';
    ELSIF lower(v_assigned_shift) LIKE '%morning%' THEN
        v_shift_type := 'morning';
    ELSIF lower(v_assigned_shift) LIKE '%evening%' THEN
        v_shift_type := 'evening';
    ELSE
        v_shift_type := 'single';
    END IF;

    IF v_staff_id IS NULL OR v_staff_status <> 'Active' OR v_profile_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'assigned_shift', COALESCE(v_assigned_shift, 'Single Shift'),
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

    IF v_assigned_shift = 'Two Shifts' OR v_shift_type = 'both' THEN
        v_assigned_shift := 'Two Shifts';

        SELECT sw.shift_id, sw.start_time, sw.end_time
        INTO v_morning_shift_id, v_morning_start, v_morning_end
        FROM public.fn_staff_shift_window(v_staff_id, p_gym_id, 'morning') sw;

        SELECT sw.shift_id, sw.start_time, sw.end_time
        INTO v_evening_shift_id, v_evening_start, v_evening_end
        FROM public.fn_staff_shift_window(v_staff_id, p_gym_id, 'evening') sw;

        -- Auto-mark absent in DB if window passed
        v_absent_log_id := public.fn_ensure_shift_absent(
            p_gym_id, v_staff_id, v_profile_user_id, p_date,
            v_morning_shift_id, v_morning_end, v_morning_start, 1
        );
        v_absent_log_id := public.fn_ensure_shift_absent(
            p_gym_id, v_staff_id, v_profile_user_id, p_date,
            v_evening_shift_id, v_evening_end, v_evening_start, 2
        );

        SELECT * INTO v_morning_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.staff_id = v_staff_id)
          AND (
              (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
              OR al.date = v_date_str
              OR al.date = to_char(p_date, 'YYYY-MM-DD')
          )
          AND (
              (v_morning_shift_id IS NOT NULL AND al.shift_id = v_morning_shift_id)
              OR (v_morning_shift_id IS NULL AND (al.shift_id IS NULL OR al.shift_index = 1))
          )
        ORDER BY al.check_in ASC
        LIMIT 1;

        SELECT * INTO v_evening_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.staff_id = v_staff_id)
          AND (
              (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
              OR al.date = v_date_str
              OR al.date = to_char(p_date, 'YYYY-MM-DD')
          )
          AND (
              (v_evening_shift_id IS NOT NULL AND al.shift_id = v_evening_shift_id)
              OR al.shift_index = 2
          )
        ORDER BY al.check_in ASC
        LIMIT 1;

        -- Morning status
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
        ELSIF v_morning_end IS NOT NULL AND (
            p_date < (now() AT TIME ZONE 'Asia/Kolkata')::DATE
            OR v_local_time > (v_morning_end + INTERVAL '1 hour')::TIME
        ) THEN
            v_first_shift_status := 'Absent';
        END IF;

        -- Evening status
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
        ELSIF v_evening_end IS NOT NULL AND (
            p_date < (now() AT TIME ZONE 'Asia/Kolkata')::DATE
            OR v_local_time > (v_evening_end + INTERVAL '1 hour')::TIME
        ) THEN
            v_second_shift_status := 'Absent';
        END IF;

    ELSIF v_shift_type = 'morning' THEN
        SELECT sw.shift_id, sw.start_time, sw.end_time
        INTO v_morning_shift_id, v_morning_start, v_morning_end
        FROM public.fn_staff_shift_window(v_staff_id, p_gym_id, 'morning') sw;

        v_absent_log_id := public.fn_ensure_shift_absent(
            p_gym_id, v_staff_id, v_profile_user_id, p_date,
            v_morning_shift_id, v_morning_end, v_morning_start, 1
        );

        SELECT * INTO v_single_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.staff_id = v_staff_id)
          AND (
              (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
              OR al.date = v_date_str
          )
          AND (v_morning_shift_id IS NULL OR al.shift_id = v_morning_shift_id OR al.shift_id IS NULL)
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
        ELSIF v_morning_end IS NOT NULL AND v_local_time > (v_morning_end + INTERVAL '1 hour')::TIME THEN
            v_first_shift_status := 'Absent';
        END IF;

    ELSIF v_shift_type = 'evening' THEN
        SELECT sw.shift_id, sw.start_time, sw.end_time
        INTO v_evening_shift_id, v_evening_start, v_evening_end
        FROM public.fn_staff_shift_window(v_staff_id, p_gym_id, 'evening') sw;

        v_absent_log_id := public.fn_ensure_shift_absent(
            p_gym_id, v_staff_id, v_profile_user_id, p_date,
            v_evening_shift_id, v_evening_end, v_evening_start, 2
        );

        SELECT * INTO v_single_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.staff_id = v_staff_id)
          AND (
              (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
              OR al.date = v_date_str
          )
          AND (v_evening_shift_id IS NULL OR al.shift_id = v_evening_shift_id)
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
        ELSIF v_evening_end IS NOT NULL AND v_local_time > (v_evening_end + INTERVAL '1 hour')::TIME THEN
            v_first_shift_status := 'Absent';
        END IF;

    ELSE
        -- Single shift: staff profile timing via fn_staff_shift_window
        SELECT sw.shift_id, sw.start_time, sw.end_time
        INTO v_morning_shift_id, v_morning_start, v_morning_end
        FROM public.fn_staff_shift_window(v_staff_id, p_gym_id, 'morning') sw;

        IF v_morning_end IS NULL THEN
            SELECT gs.id, gs.start_time_24h, gs.end_time_24h
            INTO v_morning_shift_id, v_morning_start, v_morning_end
            FROM public.gym_shifts gs
            WHERE gs.gym_id = p_gym_id AND gs.shift_type = 'Single Shift'
            LIMIT 1;
        END IF;

        v_absent_log_id := public.fn_ensure_shift_absent(
            p_gym_id, v_staff_id, v_profile_user_id, p_date,
            v_morning_shift_id, v_morning_end, v_morning_start, 1
        );

        SELECT * INTO v_single_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.staff_id = v_staff_id)
          AND (
              (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
              OR al.date = v_date_str
          )
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
        ELSIF v_morning_end IS NOT NULL AND v_local_time > (v_morning_end + INTERVAL '1 hour')::TIME THEN
            v_first_shift_status := 'Absent';
        END IF;
    END IF;

    -- Can check in/out logic
    IF v_open_log_id IS NOT NULL THEN
        v_can_check_in := FALSE;
        v_can_check_out := TRUE;
    ELSE
        IF v_assigned_shift = 'Two Shifts' THEN
            -- Evening still open if morning done/absent
            IF v_first_shift_status IN ('Checked Out', 'Absent') AND v_second_shift_status = 'Not Checked In' THEN
                v_can_check_in := TRUE;
                v_can_check_out := FALSE;
            ELSIF v_first_shift_status IN ('Checked Out', 'Absent') AND v_second_shift_status IN ('Checked Out', 'Absent') THEN
                v_can_check_in := FALSE;
                v_can_check_out := FALSE;
            ELSIF v_first_shift_status = 'Not Checked In' THEN
                v_can_check_in := TRUE;
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

    RETURN jsonb_build_object(
        'assigned_shift', CASE WHEN v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN 'Two Shifts' ELSE 'Single Shift' END,
        'working_hours_today', (COALESCE(v_total_working_mins, 0) / 60)::TEXT || 'h ' || lpad((COALESCE(v_total_working_mins, 0) % 60)::TEXT, 2, '0') || 'm',
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
        'is_attendance_completed', (NOT v_can_check_in AND NOT v_can_check_out),
        'morning_shift_end', to_char(v_morning_end, 'HH12:MI AM'),
        'evening_shift_end', to_char(v_evening_end, 'HH12:MI AM'),
        'morning_shift_start', to_char(v_morning_start, 'HH12:MI AM'),
        'evening_shift_start', to_char(v_evening_start, 'HH12:MI AM'),
        'shift_source', 'staff_profile'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_today_attendance_details_v2(UUID, UUID, DATE) TO anon, authenticated, service_role;


-- -------------------------------------------------------------------------
-- PART E: Update cron_auto_mark_absent to use staff shift times
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_auto_mark_absent()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_gym RECORD;
    v_staff RECORD;
    v_local_date DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    v_morning RECORD;
    v_evening RECORD;
BEGIN
    FOR v_gym IN
        SELECT gym_id FROM public.attendance_settings WHERE auto_mark_absent = TRUE
    LOOP
        FOR v_staff IN
            SELECT s.id, s.user_id
            FROM public.staff s
            WHERE s.gym_id = v_gym.gym_id
              AND s.status = 'Active'
              AND s.user_id IS NOT NULL
        LOOP
            SELECT * INTO v_morning FROM public.fn_staff_shift_window(v_staff.id, v_gym.gym_id, 'morning');
            SELECT * INTO v_evening FROM public.fn_staff_shift_window(v_staff.id, v_gym.gym_id, 'evening');

            PERFORM public.fn_ensure_shift_absent(
                v_gym.gym_id, v_staff.id, v_staff.user_id, v_local_date,
                v_morning.shift_id, v_morning.end_time, v_morning.start_time, 1
            );
            PERFORM public.fn_ensure_shift_absent(
                v_gym.gym_id, v_staff.id, v_staff.user_id, v_local_date,
                v_evening.shift_id, v_evening.end_time, v_evening.start_time, 2
            );
        END LOOP;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cron_auto_mark_absent() TO anon, authenticated, service_role;


-- -------------------------------------------------------------------------
-- PART F: SALARY — same pending payable formula as Pay Salary screen
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_staff_net_payable(
    p_staff_id UUID,
    p_salary_month TEXT
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_month TEXT := trim(COALESCE(p_salary_month, to_char(CURRENT_DATE, 'FMMonth YYYY')));
    v_base NUMERIC(12,2) := 0;
    v_commission NUMERIC(12,2) := 0;
    v_advances NUMERIC(12,2) := 0;
    v_additions NUMERIC(12,2) := 0;
    v_deductions NUMERIC(12,2) := 0;
    v_draft_id UUID;
    v_gym_id UUID;
    s_name TEXT;
BEGIN
    SELECT COALESCE(s.salary, 0), s.gym_id, s.name
    INTO v_base, v_gym_id, s_name
    FROM public.staff s WHERE s.id = p_staff_id;
    IF s_name IS NULL THEN RETURN 0; END IF;

    IF EXISTS (
        SELECT 1 FROM public.salary_drafts sd
        WHERE sd.staff_id = p_staff_id AND trim(sd.salary_month) = v_month
          AND sd.status = 'Paid'::public.draft_status
    ) OR EXISTS (
        SELECT 1 FROM public.expenses e
        WHERE e.gym_id = v_gym_id AND e.category = 'Salaries'
          AND e.title LIKE '%' || s_name || '%'
          AND to_char(e.date, 'FMMonth YYYY') = v_month
    ) OR EXISTS (
        SELECT 1 FROM public.finance_transactions ft
        WHERE ft.gym_id = v_gym_id AND ft.category = 'Salary' AND ft.type = 'Expense'
          AND ft.title LIKE '%' || s_name || '%'
          AND to_char(ft.transaction_date, 'FMMonth YYYY') = v_month
          AND ft.notes NOT ILIKE '%advance%'
    ) THEN RETURN 0; END IF;

    SELECT sd.id INTO v_draft_id FROM public.salary_drafts sd
    WHERE sd.staff_id = p_staff_id AND trim(sd.salary_month) = v_month LIMIT 1;

    SELECT COALESCE(SUM(cl.amount), 0) INTO v_commission
    FROM public.commission_ledger cl
    WHERE cl.staff_id = p_staff_id AND cl.status = 'Pending'::public.commission_status;

    SELECT COALESCE(SUM(sa.remaining_amount), 0) INTO v_advances
    FROM public.salary_advance_ledger sa
    WHERE sa.staff_id = p_staff_id
      AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
      AND (trim(sa.salary_month) = v_month OR (
          (sa.salary_month IS NULL OR sa.salary_month = '')
          AND to_char(sa.given_date, 'FMMonth YYYY') = v_month
      ));

    IF v_draft_id IS NOT NULL THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_additions FROM public.salary_adjustments
        WHERE salary_draft_id = v_draft_id AND type = 'Addition'::public.adjustment_type;
        SELECT COALESCE(SUM(amount), 0) INTO v_deductions FROM public.salary_adjustments
        WHERE salary_draft_id = v_draft_id AND type = 'Deduction'::public.adjustment_type;
    END IF;

    RETURN GREATEST(0, (v_base + v_commission + v_additions - v_deductions) - v_advances);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_staff_net_payable(UUID, TEXT) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_staff_pending_salary(p_staff_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN RETURN public.fn_staff_net_payable(p_staff_id, to_char(CURRENT_DATE, 'FMMonth YYYY')); END; $$;
GRANT EXECUTE ON FUNCTION public.get_staff_pending_salary(UUID) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_staff_pending_salary_for_month(p_staff_id UUID, p_salary_month TEXT)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN RETURN public.fn_staff_net_payable(p_staff_id, p_salary_month); END; $$;
GRANT EXECUTE ON FUNCTION public.get_staff_pending_salary_for_month(UUID, TEXT) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_total_salary_due(p_gym_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_month TEXT := to_char(CURRENT_DATE, 'FMMonth YYYY'); v_total NUMERIC(12,2) := 0; r RECORD;
BEGIN
    FOR r IN SELECT id FROM public.staff WHERE gym_id = p_gym_id AND status = 'Active'
    LOOP v_total := v_total + public.fn_staff_net_payable(r.id, v_month); END LOOP;
    RETURN GREATEST(0, v_total);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_total_salary_due(UUID) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_gym_member_pending_total(p_gym_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN COALESCE((SELECT SUM(GREATEST(0, m.pending_amount)) FROM public.members m
        WHERE m.gym_id = p_gym_id AND COALESCE(m.pending_amount, 0) > 0), 0);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_gym_member_pending_total(UUID) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reconcile_member_pending_amounts(p_gym_id UUID DEFAULT NULL)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count INTEGER := 0;
BEGIN
    UPDATE public.members m SET
        total_received_amount = COALESCE(sub.received, m.total_received_amount),
        pending_amount = GREATEST(0, COALESCE(sub.total_due, 0) - COALESCE(sub.received, 0)),
        payment_status = CASE
            WHEN GREATEST(0, COALESCE(sub.total_due, 0) - COALESCE(sub.received, 0)) <= 0 THEN 'Paid'
            WHEN COALESCE(sub.received, 0) > 0 THEN 'Partial'
            ELSE 'Pending'
        END
    FROM (
        SELECT mm.member_id,
            COALESCE(SUM(mm.total_amount), 0) AS total_due,
            COALESCE(SUM(mm.paid_amount), 0) AS received
        FROM public.member_memberships mm GROUP BY mm.member_id
    ) sub
    WHERE m.id = sub.member_id AND (p_gym_id IS NULL OR m.gym_id = p_gym_id);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END; $$;
GRANT EXECUTE ON FUNCTION public.reconcile_member_pending_amounts(UUID) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_owner_staff_cards_v1(p_gym_id UUID, p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    staff_id UUID, name TEXT, role TEXT, avatar TEXT, status TEXT,
    salary_pending NUMERIC, present_days INT, leave_days INT, early_exit_count INT,
    last_check_in TEXT, is_checked_in BOOLEAN, current_date_str TEXT,
    is_salary_paid BOOLEAN, paid_amount NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_start_of_month DATE := date_trunc('month', p_date)::DATE;
        v_month_str TEXT := to_char(p_date, 'FMMonth YYYY');
BEGIN
    RETURN QUERY
    WITH monthly_attendance AS (
        SELECT s.id AS s_id,
            COUNT(DISTINCT al.check_in::DATE)::INT AS month_present,
            COUNT(DISTINCT CASE WHEN al.status IN ('Leave', 'Half Leave', 'On Leave') THEN al.check_in::DATE END)::INT AS month_leave,
            COUNT(CASE WHEN al.status = 'Early Exit' OR COALESCE(al.early_exit_minutes, 0) > 0 THEN 1 END)::INT AS month_early_exit
        FROM public.staff s
        LEFT JOIN public.attendance_logs al ON (al.user_id = s.user_id OR al.user_id = s.id)
            AND al.gym_id = p_gym_id AND al.user_type = 'Staff'
            AND al.status IN ('Present', 'Late', 'Half Day', 'Overtime', 'Early Exit')
            AND al.check_in::DATE >= v_start_of_month AND al.check_in::DATE <= p_date
        WHERE s.gym_id = p_gym_id GROUP BY s.id
    ),
    today_attendance AS (
        SELECT DISTINCT ON (s.id) s.id AS s_id, al.check_in, al.check_out, (al.check_out IS NULL) AS checked_in
        FROM public.staff s
        JOIN public.attendance_logs al ON (al.user_id = s.user_id OR al.user_id = s.id)
            AND al.gym_id = p_gym_id AND al.user_type = 'Staff' AND al.check_in::DATE = p_date
        WHERE s.gym_id = p_gym_id ORDER BY s.id, al.check_in DESC
    ),
    paid_drafts AS (
        SELECT s.id AS s_id, TRUE AS is_paid, COALESCE(sd.net_salary, s.salary, 0.0) AS amount
        FROM public.staff s
        LEFT JOIN public.salary_drafts sd ON sd.staff_id = s.id
            AND trim(sd.salary_month) = trim(v_month_str) AND sd.status = 'Paid'::public.draft_status
        WHERE s.gym_id = p_gym_id AND (
            sd.id IS NOT NULL OR EXISTS (
                SELECT 1 FROM public.expenses e WHERE e.gym_id = p_gym_id AND e.category = 'Salaries'
                    AND e.title LIKE '%' || s.name || '%' AND to_char(e.date, 'FMMonth YYYY') = trim(v_month_str)
            )
        )
    )
    SELECT s.id, s.name, s.role, COALESCE(s.avatar, ''), s.status,
        CASE WHEN COALESCE(pd.is_paid, FALSE) THEN 0.0 ELSE public.fn_staff_net_payable(s.id, v_month_str) END,
        COALESCE(ma.month_present, 0)::INT, COALESCE(ma.month_leave, 0)::INT, COALESCE(ma.month_early_exit, 0)::INT,
        CASE WHEN ta.check_in IS NOT NULL THEN to_char(ta.check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') ELSE 'N/A' END,
        COALESCE(ta.checked_in, FALSE), to_char(p_date, 'DD Mon YYYY'),
        COALESCE(pd.is_paid, FALSE), COALESCE(pd.amount, 0.0)::NUMERIC
    FROM public.staff s
    LEFT JOIN monthly_attendance ma ON s.id = ma.s_id
    LEFT JOIN today_attendance ta ON s.id = ta.s_id
    LEFT JOIN paid_drafts pd ON s.id = pd.s_id
    WHERE s.gym_id = p_gym_id ORDER BY s.created_at DESC;
END; $$;
GRANT EXECUTE ON FUNCTION public.get_owner_staff_cards_v1(UUID, DATE) TO anon, authenticated, service_role;

-- One-time reconcile (safe to re-run)
SELECT public.reconcile_member_pending_amounts(NULL);
