-- =========================================================================
-- DATABASE FUNCTION: get_staff_salary_month_leave_details
-- Copy and run this script in your Supabase SQL Editor to deploy the function.
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_staff_salary_month_leave_details(
    p_staff_id UUID,
    p_salary_month TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_month_start DATE;
    v_month_end DATE;
    v_user_id UUID;
    v_gym_id UUID;
    v_absent_count INT := 0;
    v_late_count INT := 0;
    v_leave_days_count INT := 0;
    v_attendance_logs JSONB;
    v_leave_requests JSONB;
BEGIN
    -- Parse month start and end dates (Format: 'August 2026')
    BEGIN
        v_month_start := to_date(p_salary_month, 'Month YYYY');
        v_month_end := (v_month_start + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'Invalid month format. Expected MMMM YYYY.'
        );
    END;

    -- Get user_id and gym_id for this staff
    SELECT user_id, gym_id INTO v_user_id, v_gym_id
    FROM public.staff
    WHERE id = p_staff_id;

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'Staff member not found.'
        );
    END IF;

    -- 1. Calculate and fetch Absent/Late logs
    -- To be timezone-safe and 100% correct, we query using (check_in AT TIME ZONE 'Asia/Kolkata')::DATE
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'date', to_char(check_in AT TIME ZONE 'Asia/Kolkata', 'dd-MM-yyyy'),
        'status', status,
        'check_in', to_char(check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM'),
        'check_out', to_char(check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')
    ) ORDER BY (check_in AT TIME ZONE 'Asia/Kolkata') ASC), '[]'::JSONB)
    INTO v_attendance_logs
    FROM public.attendance_logs
    WHERE (user_id = v_user_id OR staff_id = p_staff_id)
      AND gym_id = v_gym_id
      AND status IN ('Absent', 'Late')
      AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE >= v_month_start
      AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE <= v_month_end;

    -- Count of absent and late logs
    SELECT COUNT(*)::INT INTO v_absent_count
    FROM public.attendance_logs
    WHERE (user_id = v_user_id OR staff_id = p_staff_id)
      AND gym_id = v_gym_id
      AND status = 'Absent'
      AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE >= v_month_start
      AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE <= v_month_end;

    SELECT COUNT(*)::INT INTO v_late_count
    FROM public.attendance_logs
    WHERE (user_id = v_user_id OR staff_id = p_staff_id)
      AND gym_id = v_gym_id
      AND status = 'Late'
      AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE >= v_month_start
      AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE <= v_month_end;

    -- 2. Fetch approved leave requests that overlap with the target month
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'start_date', to_char(start_date, 'dd-MM-yyyy'),
        'end_date', to_char(end_date, 'dd-MM-yyyy'),
        'leave_type', leave_type,
        'reason', reason
    ) ORDER BY start_date ASC), '[]'::JSONB)
    INTO v_leave_requests
    FROM public.leave_requests
    WHERE staff_id = p_staff_id
      AND gym_id = v_gym_id
      AND status = 'Approved'
      AND start_date <= v_month_end
      AND end_date >= v_month_start;

    -- Calculate total approved leave days in this month (taking overlap into account)
    SELECT COALESCE(SUM(
        LEAST(end_date, v_month_end) - GREATEST(start_date, v_month_start) + 1
    ), 0)::INT INTO v_leave_days_count
    FROM public.leave_requests
    WHERE staff_id = p_staff_id
      AND gym_id = v_gym_id
      AND status = 'Approved'
      AND start_date <= v_month_end
      AND end_date >= v_month_start;

    RETURN jsonb_build_object(
        'success', TRUE,
        'salary_month', p_salary_month,
        'absent_days', v_absent_count,
        'late_days', v_late_count,
        'approved_leave_days', v_leave_days_count,
        'attendance_logs', v_attendance_logs,
        'leave_requests', v_leave_requests
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_salary_month_leave_details(UUID, TEXT) TO anon, authenticated, service_role;
