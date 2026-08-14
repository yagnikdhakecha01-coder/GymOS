-- =========================================================================
-- FIX AUTO ABSENT & HALF DAY RULES MIGRATION
-- Run this script in Supabase SQL Editor
-- =========================================================================

-- 1. Helper function for shift start/end parsing
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


-- 2. Staff Shift Window Helper
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
        start_time := COALESCE(public.fn_parse_12h_time(v_shift1_start), v_gym_m_start, '10:00:00'::TIME);
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


-- 3. Auto-absent helper: ONLY marks absent after shift_start + 1 hour!
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
    v_start TIME := COALESCE(p_shift_start, p_shift_end, '10:00:00'::TIME);
    v_cutoff TIME;
BEGIN
    IF p_shift_start IS NULL AND p_shift_end IS NULL THEN
        RETURN NULL;
    END IF;

    -- Cutoff is 1 hour AFTER shift_start time (e.g. 10:00 AM start -> cutoff 11:00 AM)
    v_cutoff := (v_start + INTERVAL '1 hour')::TIME;

    IF p_target_date = v_local_date THEN
        -- If current local time has NOT passed shift_start + 1hr, DO NOT mark absent!
        IF v_local_time < v_cutoff THEN
            RETURN NULL;
        END IF;
    ELSIF p_target_date > v_local_date THEN
        -- Future date: never mark absent
        RETURN NULL;
    END IF;

    -- Check if log already exists for this date and shift
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

    -- Insert absent log
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
        (p_target_date::TEXT || ' ' || COALESCE(p_shift_end, v_start)::TEXT)::TIMESTAMPTZ AT TIME ZONE 'Asia/Kolkata',
        'Absent',
        'Completed',
        0,
        'Auto-Absent',
        'manual'
    ) RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_ensure_shift_absent(UUID, UUID, UUID, DATE, UUID, TIME, TIME, INT) TO anon, authenticated, service_role;


-- 4. Today Attendance Details RPC
CREATE OR REPLACE FUNCTION public.get_staff_today_attendance_details_v2(
    p_gym_id UUID,
    p_staff_id UUID,
    p_user_id UUID DEFAULT NULL,
    p_date DATE DEFAULT (now() AT TIME ZONE 'Asia/Kolkata')::DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile_user_id UUID := p_user_id;
    v_shift TEXT;
    v_shift_type TEXT;
    v_assigned_shift TEXT := 'Single Shift';

    v_morning_shift_id UUID;
    v_morning_start TIME;
    v_morning_end TIME;
    v_evening_shift_id UUID;
    v_evening_start TIME;
    v_evening_end TIME;

    v_first_shift_status TEXT := 'Pending Activation';
    v_second_shift_status TEXT := 'Pending Activation';
    v_first_check_in TEXT;
    v_first_check_out TEXT;
    v_second_check_in TEXT;
    v_second_check_out TEXT;

    v_morning_log RECORD;
    v_evening_log RECORD;
    v_single_log RECORD;

    v_open_log_id UUID;
    v_total_working_mins INT := 0;
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    v_date_str TEXT := to_char(p_date, 'dd-MM-yyyy');
    v_absent_log_id UUID;
BEGIN
    IF v_profile_user_id IS NULL THEN
        SELECT s.user_id INTO v_profile_user_id
        FROM public.staff s WHERE s.id = p_staff_id;
    END IF;

    SELECT
        COALESCE(NULLIF(trim(s.shift), ''), 'Single Shift'),
        COALESCE(NULLIF(trim(s.shift_type), ''), 'single')
    INTO v_shift, v_shift_type
    FROM public.staff s
    WHERE s.id = p_staff_id AND s.gym_id = p_gym_id;

    IF v_shift IS NULL THEN
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

    IF v_shift_type = 'both' OR lower(v_shift) LIKE '%both%' OR lower(v_shift) LIKE '%double%' OR lower(v_shift) LIKE '%two%' THEN
        v_assigned_shift := 'Two Shifts';

        SELECT sw.shift_id, sw.start_time, sw.end_time
        INTO v_morning_shift_id, v_morning_start, v_morning_end
        FROM public.fn_staff_shift_window(p_staff_id, p_gym_id, 'morning') sw;

        SELECT sw.shift_id, sw.start_time, sw.end_time
        INTO v_evening_shift_id, v_evening_start, v_evening_end
        FROM public.fn_staff_shift_window(p_staff_id, p_gym_id, 'evening') sw;

        -- Auto-mark absent in DB ONLY IF shift_start + 1 hour has passed
        v_absent_log_id := public.fn_ensure_shift_absent(
            p_gym_id, p_staff_id, v_profile_user_id, p_date,
            v_morning_shift_id, v_morning_end, v_morning_start, 1
        );
        v_absent_log_id := public.fn_ensure_shift_absent(
            p_gym_id, p_staff_id, v_profile_user_id, p_date,
            v_evening_shift_id, v_evening_end, v_evening_start, 2
        );

        -- Fetch logs
        SELECT * INTO v_morning_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.staff_id = p_staff_id)
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
          AND (al.user_id = v_profile_user_id OR al.staff_id = p_staff_id)
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
        ELSIF v_morning_start IS NOT NULL AND (
            p_date < v_local_date
            OR (p_date = v_local_date AND v_local_time >= (v_morning_start + INTERVAL '1 hour')::TIME)
        ) THEN
            v_first_shift_status := 'Absent';
        ELSE
            v_first_shift_status := 'Pending Activation';
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
        ELSIF v_evening_start IS NOT NULL AND (
            p_date < v_local_date
            OR (p_date = v_local_date AND v_local_time >= (v_evening_start + INTERVAL '1 hour')::TIME)
        ) THEN
            v_second_shift_status := 'Absent';
        ELSE
            v_second_shift_status := 'Pending Activation';
        END IF;

    ELSE
        -- Single Shift handling
        SELECT sw.shift_id, sw.start_time, sw.end_time
        INTO v_morning_shift_id, v_morning_start, v_morning_end
        FROM public.fn_staff_shift_window(p_staff_id, p_gym_id, 'morning') sw;

        v_absent_log_id := public.fn_ensure_shift_absent(
            p_gym_id, p_staff_id, v_profile_user_id, p_date,
            v_morning_shift_id, v_morning_end, v_morning_start, 1
        );

        SELECT * INTO v_single_log
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = v_profile_user_id OR al.staff_id = p_staff_id)
          AND (
              (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
              OR al.date = v_date_str
              OR al.date = to_char(p_date, 'YYYY-MM-DD')
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
        ELSIF v_morning_start IS NOT NULL AND (
            p_date < v_local_date
            OR (p_date = v_local_date AND v_local_time >= (v_morning_start + INTERVAL '1 hour')::TIME)
        ) THEN
            v_first_shift_status := 'Absent';
        ELSE
            v_first_shift_status := 'Pending Activation';
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'assigned_shift', v_assigned_shift,
        'working_hours_today', to_char(v_total_working_mins / 60, 'FM990') || 'h ' || to_char(v_total_working_mins % 60, 'FM00') || 'm',
        'can_check_in', (v_open_log_id IS NULL AND v_first_shift_status != 'Absent' AND v_second_shift_status != 'Absent'),
        'can_check_out', (v_open_log_id IS NOT NULL),
        'open_log_id', v_open_log_id,
        'first_shift_name', 'Morning Shift',
        'first_shift_status', v_first_shift_status,
        'first_check_in', v_first_check_in,
        'first_check_out', v_first_check_out,
        'second_shift_name', 'Evening Shift',
        'second_shift_status', v_second_shift_status,
        'second_check_in', v_second_check_in,
        'second_check_out', v_second_check_out,
        'is_checked_in', (v_open_log_id IS NOT NULL),
        'is_attendance_completed', (v_first_shift_status IN ('Checked Out', 'Absent') AND (v_assigned_shift != 'Two Shifts' OR v_second_shift_status IN ('Checked Out', 'Absent')))
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_today_attendance_details_v2(UUID, UUID, UUID, DATE) TO anon, authenticated, service_role;


-- 5. Staff Weekly Summary RPC
CREATE OR REPLACE FUNCTION public.get_staff_weekly_summary_v1(
    p_user_id UUID,
    p_gym_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_today DATE := v_local_now::DATE;
    v_start_of_week DATE := date_trunc('week', v_today)::DATE;
    v_end_of_week DATE := v_today;
    v_present_count NUMERIC := 0.0;
    v_absent_count NUMERIC := 0.0;
    v_late_count NUMERIC := 0.0;
    v_total_days INT := 0;
    v_shift_type TEXT := 'single';
    v_shift_label TEXT := 'Single Shift';
    v_is_both BOOLEAN := FALSE;
    v_day RECORD;
    v_log RECORD;
    v_absent_shifts INT;
    v_present_shifts INT;
    v_half_shifts INT;
BEGIN
    SELECT COALESCE(NULLIF(trim(s.shift_type), ''), 'single'),
           COALESCE(NULLIF(trim(s.shift), ''), 'Single Shift')
    INTO v_shift_type, v_shift_label
    FROM public.staff s
    WHERE (s.user_id = p_user_id OR s.id = p_user_id) AND s.gym_id = p_gym_id
    LIMIT 1;

    v_is_both := (v_shift_type = 'both')
        OR lower(COALESCE(v_shift_label, '')) LIKE '%both%'
        OR lower(COALESCE(v_shift_label, '')) LIKE '%double%'
        OR lower(COALESCE(v_shift_label, '')) LIKE '%two%';

    SELECT COUNT(DISTINCT (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE)::INT
    INTO v_total_days
    FROM public.attendance_logs al
    WHERE al.gym_id = p_gym_id
      AND al.user_type = 'Staff'
      AND (al.user_id = p_user_id OR al.staff_id IN (
          SELECT id FROM public.staff WHERE user_id = p_user_id AND gym_id = p_gym_id
      ))
      AND (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE >= v_start_of_week
      AND (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE <= v_end_of_week;

    FOR v_day IN
        SELECT DISTINCT (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE AS log_date
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND al.user_type = 'Staff'
          AND (al.user_id = p_user_id OR al.staff_id IN (
              SELECT id FROM public.staff WHERE user_id = p_user_id AND gym_id = p_gym_id
          ))
          AND (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE >= v_start_of_week
          AND (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE <= v_end_of_week
    LOOP
        v_absent_shifts := 0;
        v_present_shifts := 0;
        v_half_shifts := 0;

        FOR v_log IN
            SELECT al.status, al.late_minutes
            FROM public.attendance_logs al
            WHERE al.gym_id = p_gym_id
              AND al.user_type = 'Staff'
              AND (al.user_id = p_user_id OR al.staff_id IN (
                  SELECT id FROM public.staff WHERE user_id = p_user_id AND gym_id = p_gym_id
              ))
              AND (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_day.log_date
        LOOP
            IF v_log.status IN ('Present', 'Overtime', 'Early Exit') THEN
                v_present_shifts := v_present_shifts + 1;
            ELSIF v_log.status = 'Late' OR COALESCE(v_log.late_minutes, 0) > 0 THEN
                v_present_shifts := v_present_shifts + 1;
                IF v_is_both THEN v_late_count := v_late_count + 0.5;
                ELSE v_late_count := v_late_count + 1.0; END IF;
            ELSIF v_log.status IN ('Half Day', 'Half Leave') THEN
                v_half_shifts := v_half_shifts + 1;
            ELSIF v_log.status IN ('Absent', 'On Leave', 'Leave') THEN
                v_absent_shifts := v_absent_shifts + 1;
            END IF;
        END LOOP;

        IF v_is_both THEN
            IF v_half_shifts > 0 THEN
                v_present_count := v_present_count + 0.5;
                v_absent_count := v_absent_count + 0.5;
            ELSIF v_absent_shifts >= 2 THEN
                v_absent_count := v_absent_count + 1.0;
            ELSIF v_absent_shifts >= 1 AND v_present_shifts >= 1 THEN
                -- 1 shift worked, 1 shift missed = Half Day
                v_absent_count := v_absent_count + 0.5;
                v_present_count := v_present_count + 0.5;
            ELSIF v_present_shifts >= 1 AND v_absent_shifts = 0 THEN
                v_present_count := v_present_count + 1.0;
            ELSIF v_absent_shifts >= 1 AND v_present_shifts = 0 THEN
                -- 0 shifts worked, missed shift(s) = Full Absent (1.0)
                v_absent_count := v_absent_count + 1.0;
            END IF;
        ELSE
            IF v_half_shifts > 0 THEN
                v_present_count := v_present_count + 0.5;
                v_absent_count := v_absent_count + 0.5;
            ELSIF v_absent_shifts > 0 THEN
                v_absent_count := v_absent_count + 1.0;
            ELSIF v_present_shifts > 0 THEN
                v_present_count := v_present_count + 1.0;
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


-- 6. Cron Auto Mark Absent
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

-- 7. Cleanup premature Auto-Absent logs inserted today before shift_start + 1hr
DELETE FROM public.attendance_logs al
WHERE al.method = 'Auto-Absent'
  AND (al.check_in AT TIME ZONE 'Asia/Kolkata')::DATE = (now() AT TIME ZONE 'Asia/Kolkata')::DATE
  AND (now() AT TIME ZONE 'Asia/Kolkata')::TIME < (
      COALESCE(
          (SELECT fn.start_time FROM public.fn_staff_shift_window(al.staff_id, al.gym_id, CASE WHEN al.shift_index = 2 THEN 'evening' ELSE 'morning' END) fn),
          '10:00:00'::TIME
      ) + INTERVAL '1 hour'
  )::TIME;
