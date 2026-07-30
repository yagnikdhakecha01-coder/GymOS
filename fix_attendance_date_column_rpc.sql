-- =========================================================================
-- MIGRATION: fix_attendance_date_column_rpc.sql
-- Description: Updated RPC for get_staff_today_attendance_details_v2 with exact status and timestamps
-- =========================================================================

-- 1. Drop old overloaded signatures to prevent ambiguities
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID);
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID, DATE);

-- 2. Re-create the function cleanly
CREATE OR REPLACE FUNCTION public.get_staff_today_attendance_details_v2(
    p_user_id UUID,
    p_gym_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff_id UUID := NULL;
    v_profile_user_id UUID := NULL;
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
BEGIN
    SELECT s.id, s.user_id, COALESCE(NULLIF(ssa.assignment_type, ''), NULLIF(s.shift, ''), 'Single Shift')
    INTO v_staff_id, v_profile_user_id, v_assigned_shift
    FROM public.staff s
    LEFT JOIN public.staff_shift_assignments ssa 
           ON (ssa.staff_id = s.id AND ssa.status = 'Active')
    WHERE (s.user_id = p_user_id OR s.id = p_user_id)
      AND s.gym_id = p_gym_id
    ORDER BY ssa.created_at DESC NULLS LAST
    LIMIT 1;

    IF v_staff_id IS NULL THEN
        SELECT s.id, s.user_id, COALESCE(s.shift, 'Single Shift')
        INTO v_staff_id, v_profile_user_id, v_assigned_shift
        FROM public.staff s
        WHERE (s.user_id = p_user_id OR s.id = p_user_id)
        LIMIT 1;
    END IF;

    WITH today_logs AS (
        SELECT 
            al.id,
            al.check_in,
            al.check_out,
            al.working_minutes,
            al.status,
            ROW_NUMBER() OVER (ORDER BY al.check_in ASC) as log_num
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = p_user_id OR al.user_id = v_staff_id OR al.user_id = v_profile_user_id)
          AND al.check_in::DATE = p_date
    )
    SELECT
        MAX(CASE WHEN log_num = 1 THEN to_char(check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') END),
        MAX(CASE WHEN log_num = 1 THEN CASE WHEN check_out IS NOT NULL THEN to_char(check_out AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') ELSE NULL END END),
        MAX(CASE WHEN log_num = 1 THEN CASE WHEN check_out IS NOT NULL THEN 'Checked Out' ELSE 'Checked In' END END),
        MAX(CASE WHEN log_num = 2 THEN to_char(check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') END),
        MAX(CASE WHEN log_num = 2 THEN CASE WHEN check_out IS NOT NULL THEN to_char(check_out AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') ELSE NULL END END),
        MAX(CASE WHEN log_num = 2 THEN CASE WHEN check_out IS NOT NULL THEN 'Checked Out' ELSE 'Checked In' END END),
        SUM(COALESCE(working_minutes, 0))::INT,
        -- Fix the MAX(uuid) issue by casting id to TEXT inside MAX, then casting the result back to UUID.
        MAX(CASE WHEN check_out IS NULL THEN id::TEXT END)::UUID
    INTO
        v_first_check_in,
        v_first_check_out,
        v_first_shift_status,
        v_second_check_in,
        v_second_check_out,
        v_second_shift_status,
        v_total_working_mins,
        v_open_log_id
    FROM today_logs;

    IF v_open_log_id IS NOT NULL THEN
        v_can_check_in := FALSE;
        v_can_check_out := TRUE;
    ELSE
        v_can_check_in := TRUE;
        v_can_check_out := FALSE;
    END IF;

    v_total_working_mins := COALESCE(v_total_working_mins, 0);
    v_hours := v_total_working_mins / 60;
    v_mins := v_total_working_mins % 60;
    v_working_hours_str := v_hours || 'h ' || lpad(v_mins::text, 2, '0') || 'm';

    RETURN jsonb_build_object(
        'assigned_shift', CASE WHEN v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN 'Two Shifts' ELSE COALESCE(v_assigned_shift, 'Single Shift') END,
        'working_hours_today', v_working_hours_str,
        'can_check_in', v_can_check_in,
        'can_check_out', v_can_check_out,
        'first_shift_name', 'Shift 1',
        'first_shift_check_in', v_first_check_in,
        'first_shift_check_out', v_first_check_out,
        'first_shift_status', COALESCE(v_first_shift_status, 'Not Checked In'),
        'second_shift_name', 'Shift 2',
        'second_shift_check_in', v_second_check_in,
        'second_shift_check_out', v_second_check_out,
        'second_shift_status', COALESCE(v_second_shift_status, 'Not Checked In'),
        'is_checked_in', (v_open_log_id IS NOT NULL OR v_first_check_in IS NOT NULL)
    );
END;
$$;
