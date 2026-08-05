-- ====================================================================
-- GYMOS: HALF-DAY LEAVE & IST TIMEZONE ATTENDANCE UPGRADE
-- ====================================================================

-- 1. ADD HALF-DAY LEAVE COLUMNS TO LEAVE_REQUESTS TABLE
ALTER TABLE public.leave_requests 
ADD COLUMN IF NOT EXISTS is_half_day BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS half_day_shift TEXT DEFAULT NULL;


-- 2. UPDATE TRIGGER FUNCTION FOR APPROVED LEAVE
CREATE OR REPLACE FUNCTION public.fn_process_approved_leave()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_curr_date DATE;
    v_date_str TEXT;
    v_check_in TIMESTAMPTZ;
    v_check_out TIMESTAMPTZ;
    v_status TEXT;
BEGIN
    IF NEW.status = 'Approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'Approved') THEN
        SELECT user_id INTO v_user_id
        FROM public.staff
        WHERE id = NEW.staff_id;

        v_curr_date := NEW.start_date;
        WHILE v_curr_date <= NEW.end_date LOOP
            v_date_str := to_char(v_curr_date, 'dd-MM-yyyy');
            v_check_in := (v_curr_date::TEXT || ' 09:00:00')::TIMESTAMPTZ;
            v_check_out := (v_curr_date::TEXT || ' 18:00:00')::TIMESTAMPTZ;
            
            v_status := CASE WHEN NEW.is_half_day IS TRUE THEN 'Half Leave' ELSE 'Leave' END;

            IF EXISTS (
                SELECT 1 FROM public.attendance_logs 
                WHERE (staff_id = NEW.staff_id OR user_id = v_user_id)
                  AND (date = v_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_curr_date)
            ) THEN
                UPDATE public.attendance_logs
                SET status = v_status,
                    shift_status = 'Completed',
                    updated_at = now()
                WHERE (staff_id = NEW.staff_id OR user_id = v_user_id)
                  AND (date = v_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_curr_date);
            ELSE
                INSERT INTO public.attendance_logs (
                    gym_id,
                    user_id,
                    role,
                    user_type,
                    staff_id,
                    date,
                    check_in,
                    check_out,
                    status,
                    shift_status,
                    method
                ) VALUES (
                    NEW.gym_id,
                    v_user_id,
                    'Staff',
                    'Staff',
                    NEW.staff_id,
                    v_date_str,
                    v_check_in,
                    v_check_out,
                    v_status,
                    'Completed',
                    CASE WHEN NEW.is_half_day IS TRUE THEN 'Half Day Leave Approved' ELSE 'Leave Approved' END
                );
            END IF;

            v_curr_date := v_curr_date + INTERVAL '1 day';
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_process_approved_leave ON public.leave_requests;
CREATE TRIGGER trg_process_approved_leave
AFTER INSERT OR UPDATE ON public.leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.fn_process_approved_leave();


-- 3. UPDATE GET_STAFF_TODAY_ATTENDANCE_DETAILS_V2 RPC TO INCLUDE LEAVE CHECKS
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

    v_leave_req RECORD;
    v_is_on_leave BOOLEAN := FALSE;

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
            'is_attendance_completed', FALSE,
            'is_on_leave', FALSE
        );
    END IF;

    -- Check Approved Leave Request covering p_date
    SELECT * INTO v_leave_req
    FROM public.leave_requests
    WHERE staff_id = v_staff_id
      AND status = 'Approved'
      AND p_date >= start_date
      AND p_date <= end_date
    ORDER BY created_at DESC LIMIT 1;

    IF v_leave_req.id IS NOT NULL THEN
        IF v_leave_req.is_half_day IS NOT TRUE THEN
            -- Full Day Approved Leave
            RETURN jsonb_build_object(
                'assigned_shift', COALESCE(v_assigned_shift, 'Single Shift'),
                'working_hours_today', '0h 00m',
                'can_check_in', FALSE,
                'can_check_out', FALSE,
                'first_shift_name', 'Morning Shift',
                'first_shift_check_in', NULL,
                'first_shift_check_out', NULL,
                'first_shift_status', 'Leave',
                'second_shift_name', 'Evening Shift',
                'second_shift_check_in', NULL,
                'second_shift_check_out', NULL,
                'second_shift_status', 'Leave',
                'is_checked_in', FALSE,
                'is_attendance_completed', TRUE,
                'is_on_leave', TRUE,
                'leave_reason', COALESCE(v_leave_req.reason, 'Approved Leave')
            );
        END IF;
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

        IF v_leave_req.id IS NOT NULL AND v_leave_req.is_half_day IS TRUE THEN
            IF v_leave_req.half_day_shift IN ('Morning', 'First Half', 'Morning Shift') THEN
                v_first_shift_status := 'Half Leave';
            ELSIF v_leave_req.half_day_shift IN ('Evening', 'Second Half', 'Evening Shift') THEN
                v_second_shift_status := 'Half Leave';
            END IF;
        END IF;

        IF v_morning_log.id IS NULL AND v_first_shift_status <> 'Half Leave' AND v_morning_shift_end IS NOT NULL AND v_local_time > (v_morning_shift_end + INTERVAL '1 hour')::TIME THEN
            v_first_shift_status := 'Absent';
        ELSIF v_morning_log.id IS NOT NULL THEN
            IF v_morning_log.status = 'Absent' THEN
                v_first_shift_status := 'Absent';
            ELSIF v_morning_log.status = 'Leave' THEN
                v_first_shift_status := 'Leave';
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

        IF v_evening_log.id IS NULL AND v_second_shift_status <> 'Half Leave' AND v_evening_shift_end IS NOT NULL AND v_local_time > (v_evening_shift_end + INTERVAL '1 hour')::TIME THEN
            v_second_shift_status := 'Absent';
        ELSIF v_evening_log.id IS NOT NULL THEN
            IF v_evening_log.status = 'Absent' THEN
                v_second_shift_status := 'Absent';
            ELSIF v_evening_log.status = 'Leave' THEN
                v_second_shift_status := 'Leave';
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

        IF v_leave_req.id IS NOT NULL AND v_leave_req.is_half_day IS TRUE THEN
            v_first_shift_status := 'Half Leave';
        END IF;

        IF v_single_log.id IS NOT NULL THEN
            IF v_single_log.status = 'Absent' THEN
                v_first_shift_status := 'Absent';
            ELSIF v_single_log.status = 'Leave' THEN
                v_first_shift_status := 'Leave';
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
        IF (v_assigned_shift IN ('Two Shifts', 'Both Shifts') AND v_first_shift_status IN ('Checked Out', 'Absent', 'Half Leave', 'Leave') AND v_second_shift_status IN ('Checked Out', 'Absent', 'Half Leave', 'Leave')) OR
           (v_assigned_shift NOT IN ('Two Shifts', 'Both Shifts') AND v_first_shift_status IN ('Checked Out', 'Absent', 'Leave')) THEN
            v_can_check_in := FALSE;
            v_can_check_out := FALSE;
        ELSE
            v_can_check_in := TRUE;
            v_can_check_out := FALSE;
        END IF;
    END IF;

    v_hours := v_total_working_mins / 60;
    v_mins := v_total_working_mins % 60;
    v_working_hours_str := to_char(v_hours, 'FM90') || 'h ' || to_char(v_mins, 'FM00') || 'm';

    RETURN jsonb_build_object(
        'assigned_shift', v_assigned_shift,
        'working_hours_today', v_working_hours_str,
        'can_check_in', v_can_check_in,
        'can_check_out', v_can_check_out,
        'first_shift_name', CASE WHEN v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN 'Morning Shift' ELSE 'Single Shift' END,
        'first_shift_check_in', v_first_check_in,
        'first_shift_check_out', v_first_check_out,
        'first_shift_status', v_first_shift_status,
        'second_shift_name', 'Evening Shift',
        'second_shift_check_in', v_second_shift_in,
        'second_shift_check_out', v_second_check_out,
        'second_shift_status', v_second_shift_status,
        'is_checked_in', (v_open_log_id IS NOT NULL),
        'is_attendance_completed', (v_can_check_in = FALSE AND v_open_log_id IS NULL),
        'is_on_leave', FALSE
    );
END;
$$;
