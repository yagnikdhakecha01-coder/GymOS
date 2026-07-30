-- =========================================================================
-- DATABASE MIGRATION SCRIPT: REDEPLOY ATTENDANCE & SHIFT FIXES
-- Copy and run this script in your Supabase SQL Editor to apply the fix.
-- =========================================================================

-- 1. DROP & REBUILD: get_staff_today_attendance_details_v2
-- Ensures logs are associated with Morning/Evening shifts by shift_id rather than sequence.
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
    
    -- Helper variables for robust shift mapping
    v_morning_shift_id UUID := NULL;
    v_evening_shift_id UUID := NULL;
    v_morning_log RECORD;
    v_evening_log RECORD;
    v_single_log RECORD;
BEGIN
    -- Resolve Staff Record details
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

    -- Fetch morning shift ID and evening shift ID
    SELECT id INTO v_morning_shift_id FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Morning Shift';
    SELECT id INTO v_evening_shift_id FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Evening Shift';

    -- Fetch logs for today's local date (Asia/Kolkata) and map them
    IF v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN
        -- Morning shift log
        SELECT * INTO v_morning_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
          AND shift_id = v_morning_shift_id
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

        -- Set Morning Shift details
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
        END IF;

        -- Set Evening Shift details
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
        END IF;
    ELSE
        -- Single shift log
        SELECT * INTO v_single_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
        ORDER BY check_in ASC
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
        END IF;
    END IF;

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
        'is_checked_in', (v_open_log_id IS NOT NULL)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_today_attendance_details_v2(UUID, UUID, DATE) TO anon, authenticated, service_role;


-- 2. DROP & REBUILD: cron_auto_mark_absent
-- Prevents time wrap-around bugs and evaluates shift deadlines robustly across today and yesterday.
DROP FUNCTION IF EXISTS public.cron_auto_mark_absent();
CREATE OR REPLACE FUNCTION public.cron_auto_mark_absent()
RETURNS VOID AS $$
DECLARE
    v_local_now TIMESTAMP := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;
    v_local_date DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    
    v_gym RECORD;
    v_staff RECORD;
    v_member RECORD;
    v_shift RECORD;
    v_assignment RECORD;
    v_exists BOOLEAN;
    v_latest_shift_end TIME;
    v_trigger_timestamp TIMESTAMPTZ;
    
    -- Variables for checking both today and yesterday to cover midnight crossovers
    v_check_date DATE;
    v_check_date_str TEXT;
BEGIN
    -- Loop through gyms where auto_mark_absent is enabled
    FOR v_gym IN 
        SELECT gym_id 
        FROM public.attendance_settings 
        WHERE auto_mark_absent = TRUE
    LOOP
        -- ==========================================
        -- 1. STAFF AUTO-ABSENT ENGINE
        -- ==========================================
        FOR v_staff IN 
            SELECT id, user_id 
            FROM public.staff 
            WHERE gym_id = v_gym.gym_id AND status = 'Active'
        LOOP
            -- Get active shift assignment
            SELECT * INTO v_assignment 
            FROM public.staff_shift_assignments 
            WHERE staff_id = v_staff.id AND gym_id = v_gym.gym_id AND status = 'Active'
            LIMIT 1;
            
            IF v_assignment IS NOT NULL THEN
                -- Check both today and yesterday
                FOR v_check_date IN SELECT v_local_date UNION SELECT (v_local_date - 1) LOOP
                    v_check_date_str := to_char(v_check_date, 'dd-MM-yyyy');
                    
                    -- CASE A: Both Shifts Assigned
                    IF v_assignment.assignment_type = 'Both Shifts' THEN
                        -- Check Morning Shift
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = 'Morning Shift';
                        IF v_shift IS NOT NULL THEN
                            v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            
                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;
                        
                        -- Check Evening Shift
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = 'Evening Shift';
                        IF v_shift IS NOT NULL THEN
                            v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            
                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;
                    
                    -- CASE B: Single/Morning/Evening Shift
                    ELSE
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE id = v_assignment.shift_id;
                        IF v_shift IS NULL THEN
                            SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = v_assignment.assignment_type;
                        END IF;
                        
                        IF v_shift IS NOT NULL THEN
                            IF v_shift.shift_type = 'Single Shift' THEN
                                v_trigger_timestamp := (v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata';
                            ELSE
                                v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            END IF;

                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;
                    END IF;
                END LOOP;
            END IF;
        END LOOP;

        -- ==========================================
        -- 2. MEMBER AUTO-ABSENT ENGINE
        -- ==========================================
        -- Fetch the latest shift end time in the gym. Fallback to 10:00 PM if no shifts.
        SELECT COALESCE(MAX(end_time_24h), '22:00:00'::TIME) INTO v_latest_shift_end
        FROM public.gym_shifts
        WHERE gym_id = v_gym.gym_id;

        -- Trigger at 2 hours after latest shift ends
        v_trigger_timestamp := ((v_local_date::TEXT || ' ' || v_latest_shift_end::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '2 hours';

        IF now() > v_trigger_timestamp THEN
            FOR v_member IN 
                SELECT id, user_id 
                FROM public.members 
                WHERE gym_id = v_gym.gym_id AND status IN ('Active', 'Trial')
            LOOP
                SELECT EXISTS (
                    SELECT 1 FROM public.attendance_logs 
                    WHERE user_id = v_member.user_id 
                      AND gym_id = v_gym.gym_id 
                      AND date = to_char(v_local_date, 'dd-MM-yyyy') 
                      AND shift_id IS NULL
                ) INTO v_exists;
                
                IF NOT v_exists THEN
                    INSERT INTO public.attendance_logs (
                        gym_id, user_id, role, user_type, member_id, date, check_in, check_out, status, method
                    ) VALUES (
                        v_gym.gym_id, v_member.user_id, 'Member', 'Member', v_member.id, to_char(v_local_date, 'dd-MM-yyyy'), v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'System'
                    );
                END IF;
            END LOOP;
        END IF;
        
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.cron_auto_mark_absent() TO anon, authenticated, service_role;


-- 3. DROP & REBUILD: generate_dynamic_qr_token
-- Automatically cleans up expired (older than 5 minutes) or used tokens to prevent database storage bloating.
CREATE OR REPLACE FUNCTION public.generate_dynamic_qr_token(p_gym_id UUID, p_display_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_token TEXT;
    v_nonce TEXT;
    v_expires_at TIMESTAMPTZ;
    v_validity_secs INT;
    v_is_verified BOOLEAN;
BEGIN
    -- Check if display session exists and is verified
    SELECT is_verified INTO v_is_verified 
    FROM public.attendance_display_sessions 
    WHERE display_id = p_display_id;

    IF v_is_verified IS NULL OR NOT v_is_verified THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display not verified or offline');
    END IF;

    SELECT qr_validity_seconds INTO v_validity_secs 
    FROM public.attendance_settings 
    WHERE gym_id = p_gym_id;

    v_nonce := gen_random_uuid()::text;
    v_expires_at := now() + (v_validity_secs || ' seconds')::INTERVAL;
    v_token := encode(digest(p_gym_id::text || v_nonce || v_expires_at::text, 'sha256'), 'hex');

    -- Clean up expired or used tokens for this display to save database storage
    DELETE FROM public.attendance_qr_tokens 
    WHERE display_id = p_display_id 
      AND (expires_at < now() - INTERVAL '5 minutes' OR is_used = TRUE);

    INSERT INTO public.attendance_qr_tokens (token, gym_id, display_id, nonce, expires_at)
    VALUES (v_token, p_gym_id, p_display_id, v_nonce, v_expires_at);

    RETURN jsonb_build_object(
        'success', TRUE,
        'token', v_token,
        'expires_at', v_expires_at,
        'validity', v_validity_secs
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.generate_dynamic_qr_token(UUID, UUID) TO anon, authenticated, service_role;

