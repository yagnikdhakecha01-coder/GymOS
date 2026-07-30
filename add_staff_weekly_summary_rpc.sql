-- =========================================================================
-- MIGRATION: add_staff_weekly_summary_rpc.sql
-- Description: RPC to get weekly staff attendance summary directly from DB (with decimal support)
-- =========================================================================

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
