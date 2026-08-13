-- SQL STEP 4: Half day logic for weekly summary (run after STEP 1-2)
-- Both shift: 1 shift absent = 0.5 (half day), 2 shifts absent = 1.0 full absent

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
    v_start_of_week DATE := date_trunc('week', CURRENT_DATE)::DATE;
    v_end_of_week DATE := CURRENT_DATE;
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
            IF v_absent_shifts >= 2 THEN
                v_absent_count := v_absent_count + 1.0;
            ELSIF v_absent_shifts = 1 THEN
                v_absent_count := v_absent_count + 0.5;
            ELSIF v_half_shifts > 0 THEN
                v_absent_count := v_absent_count + 0.5;
                v_present_count := v_present_count + 0.5;
            END IF;

            IF v_present_shifts >= 2 THEN
                v_present_count := v_present_count + 1.0;
            ELSIF v_present_shifts = 1 AND v_absent_shifts = 0 THEN
                v_present_count := v_present_count + 0.5;
            ELSIF v_present_shifts = 1 AND v_absent_shifts = 1 THEN
                v_present_count := v_present_count + 0.5;
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
