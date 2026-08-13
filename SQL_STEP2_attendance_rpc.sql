-- RUN STEP 2 AFTER STEP 1


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
