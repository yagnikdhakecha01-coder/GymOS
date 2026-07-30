-- ====================================================
-- GYMOS - ENTERPRISE ATTENDANCE SYSTEM V2 MIGRATION
-- ====================================================

-- 1. Schema Extensions

-- Extend attendance_settings
ALTER TABLE public.attendance_settings 
ADD COLUMN IF NOT EXISTS auto_mark_absent BOOLEAN DEFAULT FALSE NOT NULL,
ADD COLUMN IF NOT EXISTS auto_close_shift BOOLEAN DEFAULT FALSE NOT NULL;

-- Extend gym_shifts
ALTER TABLE public.gym_shifts 
ADD COLUMN IF NOT EXISTS late_after_24h TIME;

-- Extend leave_requests
ALTER TABLE public.leave_requests 
ADD COLUMN IF NOT EXISTS leave_duration TEXT DEFAULT 'Full Day' CHECK (leave_duration IN ('Full Day', 'Morning', 'Evening'));

-- Adjust attendance_logs columns
DO $$
BEGIN
    -- Drop old status check constraint if it exists
    ALTER TABLE public.attendance_logs DROP CONSTRAINT IF EXISTS attendance_logs_status_check;
    ALTER TABLE public.attendance_logs DROP CONSTRAINT IF EXISTS chk_attendance_status;
END
$$;

ALTER TABLE public.attendance_logs
ADD COLUMN IF NOT EXISTS shift_id UUID REFERENCES public.gym_shifts(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS working_minutes INT DEFAULT 0 NOT NULL,
ADD COLUMN IF NOT EXISTS late_minutes INT DEFAULT 0 NOT NULL,
ADD COLUMN IF NOT EXISTS early_exit_minutes INT DEFAULT 0 NOT NULL,
ADD COLUMN IF NOT EXISTS overtime_minutes INT DEFAULT 0 NOT NULL,
ADD COLUMN IF NOT EXISTS shift_status TEXT,
ADD COLUMN IF NOT EXISTS qr_type TEXT,
ADD COLUMN IF NOT EXISTS qr_token_id TEXT,
ADD COLUMN IF NOT EXISTS rule_version INT DEFAULT 1 NOT NULL,
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now() NOT NULL;

-- Add updated status check constraint
ALTER TABLE public.attendance_logs
ADD CONSTRAINT chk_attendance_status 
CHECK (status IN ('Present', 'Absent', 'Half Day', 'Late', 'Early Exit', 'Overtime', 'Leave', 'Half Leave', 'Incomplete Attendance'));

-- Create Attendance Alerts table
CREATE TABLE IF NOT EXISTS public.attendance_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    alert_type TEXT NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb NOT NULL,
    is_read BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_att_alerts_lookup ON public.attendance_alerts(gym_id, is_read, created_at DESC);

-- Create Attendance Correction Requests table
CREATE TABLE IF NOT EXISTS public.attendance_correction_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    attendance_log_id UUID REFERENCES public.attendance_logs(id) ON DELETE SET NULL,
    request_date DATE NOT NULL,
    requested_check_in TIMESTAMPTZ NOT NULL,
    requested_check_out TIMESTAMPTZ,
    reason TEXT,
    status TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending', 'Approved', 'Rejected')),
    reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_att_corrections_lookup ON public.attendance_correction_requests(gym_id, status);

-- Enable RLS
ALTER TABLE public.attendance_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_correction_requests ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS alerts_isolation ON public.attendance_alerts;
CREATE POLICY alerts_isolation ON public.attendance_alerts
    FOR ALL TO authenticated
    USING (gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    ));

DROP POLICY IF EXISTS corrections_isolation ON public.attendance_correction_requests;
CREATE POLICY corrections_isolation ON public.attendance_correction_requests
    FOR ALL TO authenticated
    USING (gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    ));

-- Grant permissions
GRANT ALL ON TABLE public.attendance_alerts TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_correction_requests TO anon, authenticated, service_role;

-- ====================================================
-- 2. Core RPC: Process Attendance Scan V3
-- ====================================================

-- Forward declaration of helper function
CREATE OR REPLACE FUNCTION public.log_attendance_alert(
    p_gym_id UUID,
    p_alert_type TEXT,
    p_message TEXT,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.attendance_alerts (gym_id, alert_type, message, metadata, is_read, created_at)
    VALUES (p_gym_id, p_alert_type, p_message, p_metadata, FALSE, now());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.process_scan_attendance_v3(
    p_token TEXT,
    p_user_id UUID,
    p_method TEXT,
    p_ssid TEXT DEFAULT '',
    p_bssid TEXT DEFAULT ''
)
RETURNS JSONB AS $$
DECLARE
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    v_local_date_str TEXT := to_char(v_local_date, 'dd-MM-yyyy');

    v_gym_id UUID;
    v_user_type TEXT;
    v_user_name TEXT;
    v_user_status TEXT;
    v_member_id UUID;
    v_staff_id UUID;
    
    -- Token validation variables
    v_token_valid BOOLEAN := FALSE;
    v_token_expires TIMESTAMPTZ;
    v_token_used BOOLEAN;
    v_token_gym_id UUID;
    v_display_id UUID;
    v_display_verified BOOLEAN := FALSE;
    v_qr_type TEXT := 'Dynamic';
    
    -- Shift settings & definitions
    v_settings RECORD;
    v_assigned_shift_type TEXT;
    v_assigned_shift_id UUID;
    v_matched_shift_id UUID;
    v_matched_shift_start TIME;
    v_matched_shift_end TIME;
    v_late_after TIME;
    
    -- Working calculations
    v_last_log RECORD;
    v_log_id UUID;
    v_working_mins INT := 0;
    v_late_mins INT := 0;
    v_early_exit_mins INT := 0;
    v_overtime_mins INT := 0;
    v_status TEXT := 'Present';
    v_shift_status TEXT := 'Incomplete';
    v_leave_id UUID;
    v_leave_duration TEXT;
    
    v_err_msg TEXT;
BEGIN
    -- 1. Resolve token info (Static vs Dynamic)
    -- Check if token is Static QR token matching active settings
    SELECT gym_id, is_enabled, method, static_qr_token, static_qr_locked, late_time_setting, auto_mark_absent, auto_close_shift
    INTO v_settings
    FROM public.attendance_settings
    WHERE static_qr_token = p_token
    LIMIT 1;

    IF v_settings IS NOT NULL THEN
        v_token_valid := TRUE;
        v_token_gym_id := v_settings.gym_id;
        v_qr_type := 'Static';
        
        IF NOT v_settings.is_enabled THEN
            v_err_msg := 'Attendance marking is currently disabled.';
            PERFORM public.log_attendance_alert(v_token_gym_id, 'Rejected QR', v_err_msg, jsonb_build_object('user_id', p_user_id, 'token', p_token));
            RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
        END IF;

        IF v_settings.method NOT IN ('Static QR', 'Static QR + WiFi') THEN
            v_err_msg := 'Static QR attendance is not currently active.';
            PERFORM public.log_attendance_alert(v_token_gym_id, 'Rejected QR', v_err_msg, jsonb_build_object('user_id', p_user_id, 'token', p_token));
            RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
        END IF;
    ELSE
        -- Verify if it's dynamic token in attendance_qr_tokens
        SELECT gym_id, display_id, expires_at, is_used 
        INTO v_token_gym_id, v_display_id, v_token_expires, v_token_used
        FROM public.attendance_qr_tokens
        WHERE token = p_token
        LIMIT 1;

        IF v_token_gym_id IS NOT NULL THEN
            IF v_token_expires < now() THEN
                v_err_msg := 'QR Code has expired.';
                PERFORM public.log_attendance_alert(v_token_gym_id, 'QR Expired', v_err_msg, jsonb_build_object('user_id', p_user_id, 'token', p_token));
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;

            IF v_token_used THEN
                v_err_msg := 'QR Code has already been scanned.';
                PERFORM public.log_attendance_alert(v_token_gym_id, 'Duplicate Check In', v_err_msg, jsonb_build_object('user_id', p_user_id, 'token', p_token));
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;

            v_token_valid := TRUE;
            v_qr_type := 'Dynamic';

            -- Check active settings for dynamic verification method
            SELECT is_enabled, method, late_time_setting, auto_mark_absent, auto_close_shift
            INTO v_settings
            FROM public.attendance_settings
            WHERE gym_id = v_token_gym_id;

            IF NOT v_settings.is_enabled THEN
                v_err_msg := 'Attendance marking is currently disabled.';
                PERFORM public.log_attendance_alert(v_token_gym_id, 'Rejected QR', v_err_msg, jsonb_build_object('user_id', p_user_id, 'token', p_token));
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;

            IF v_settings.method NOT IN ('Dynamic QR', 'Dynamic QR + WiFi', 'QR Only', 'QR + WiFi') THEN
                v_err_msg := 'Dynamic QR attendance is not active.';
                PERFORM public.log_attendance_alert(v_token_gym_id, 'Rejected QR', v_err_msg, jsonb_build_object('user_id', p_user_id, 'token', p_token));
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;

            -- Check Display Validation
            IF v_display_id IS NOT NULL THEN
                SELECT is_verified INTO v_display_verified
                FROM public.attendance_display_sessions
                WHERE display_id = v_display_id AND gym_id = v_token_gym_id;

                IF NOT COALESCE(v_display_verified, FALSE) THEN
                    v_err_msg := 'Display is not verified or active.';
                    PERFORM public.log_attendance_alert(v_token_gym_id, 'Display Not Verified', v_err_msg, jsonb_build_object('user_id', p_user_id, 'display_id', v_display_id));
                    RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
                END IF;
            END IF;
        END IF;
    END IF;

    IF NOT v_token_valid THEN
        v_err_msg := 'Invalid or unrecognized QR Code.';
        RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
    END IF;

    -- 2. Identify User Type & Gym Membership
    SELECT 'Staff', name, status, id INTO v_user_type, v_user_name, v_user_status, v_staff_id
    FROM public.staff 
    WHERE user_id = p_user_id AND gym_id = v_token_gym_id
    LIMIT 1;

    IF v_user_type IS NULL THEN
        SELECT 'Member', name, status, id INTO v_user_type, v_user_name, v_user_status, v_member_id
        FROM public.members
        WHERE user_id = p_user_id AND gym_id = v_token_gym_id
        LIMIT 1;
    END IF;

    -- Reject if user belongs to another gym
    IF v_user_type IS NULL THEN
        -- Find if user is in profiles
        SELECT full_name INTO v_user_name FROM public.profiles WHERE id = p_user_id;
        v_err_msg := 'This QR belongs to another gym.';
        PERFORM public.log_attendance_alert(v_token_gym_id, 'Wrong Gym QR', COALESCE(v_user_name, 'Unknown') || ' scanned wrong Gym QR code.', jsonb_build_object('user_id', p_user_id, 'token', p_token));
        RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
    END IF;

    -- 3. Block disabled status
    IF v_user_status = 'Inactive' THEN
        v_err_msg := 'Account is disabled. Please contact the administrator.';
        PERFORM public.log_attendance_alert(v_token_gym_id, 'Rejected QR', v_user_name || ' (' || v_user_type || ') scanning attempted but account is disabled.', jsonb_build_object('user_id', p_user_id));
        RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
    END IF;

    -- 4. Check Gym Closed (Holidays)
    IF EXISTS (
        SELECT 1 FROM public.holidays 
        WHERE gym_id = v_token_gym_id AND date = v_local_date
    ) THEN
        v_err_msg := 'Gym is closed today for holiday.';
        RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
    END IF;

    -- 5. WiFi Verification
    IF v_settings.method IN ('Static QR + WiFi', 'Dynamic QR + WiFi', 'QR + WiFi') THEN
        IF p_ssid <> '' AND p_ssid <> v_settings.wifi_ssid THEN
            v_err_msg := 'Please connect to the Gym WiFi network to scan.';
            RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
        END IF;
    END IF;

    -- ====================================================
    -- MEMBER ATTENDANCE LOGIC
    -- ====================================================
    IF v_user_type = 'Member' THEN
        -- Verify Membership Expiry
        IF NOT EXISTS (
            SELECT 1 FROM public.member_memberships
            WHERE member_id = v_member_id AND v_local_date <= end_date
        ) THEN
            v_err_msg := 'Membership has expired.';
            PERFORM public.log_attendance_alert(v_token_gym_id, 'Rejected QR', 'Expired membership member (' || v_user_name || ') scanned QR.', jsonb_build_object('member_id', v_member_id));
            RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
        END IF;

        -- Unique check-in per day
        IF EXISTS (
            SELECT 1 FROM public.attendance_logs
            WHERE user_id = p_user_id AND gym_id = v_token_gym_id AND date = v_local_date_str
        ) THEN
            v_err_msg := 'Attendance already marked for today.';
            RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
        END IF;

        -- Insert Member Attendance
        INSERT INTO public.attendance_logs (
            gym_id, user_id, user_type, check_in, date, status, method, display_id, qr_token_id, qr_type
        )
        VALUES (
            v_token_gym_id, p_user_id, 'Member', v_local_now, v_local_date_str, 'Present', p_method, v_display_id, p_token, v_qr_type
        )
        RETURNING id INTO v_log_id;

        -- Mark token as used if dynamic
        IF v_qr_type = 'Dynamic' THEN
            UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
        END IF;

        RETURN jsonb_build_object(
            'success', TRUE,
            'logId', v_log_id,
            'userName', v_user_name,
            'userType', 'Member',
            'action', 'Check-In',
            'status', 'Present',
            'checkInTime', to_char(v_local_now, 'hh:mi AM')
        );

    -- ====================================================
    -- STAFF ATTENDANCE LOGIC (WITH SHIFTS, LATE, EARLY EXIT, OVERTIME, HALF DAY)
    -- ====================================================
    ELSE
        -- 1. Retrieve Active Shift Assignment
        SELECT assignment_type, shift_id INTO v_assigned_shift_type, v_assigned_shift_id
        FROM public.staff_shift_assignments
        WHERE staff_id = v_staff_id AND status = 'Active'
        LIMIT 1;

        IF v_assigned_shift_type IS NULL THEN
            v_err_msg := 'Staff is not assigned to any shift.';
            RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
        END IF;

        -- Determine matched shift
        IF v_assigned_shift_type = 'Both Shifts' THEN
            -- Cut-off time is 02:00 PM (14:00) to distinguish Morning and Evening Shift
            IF v_local_time < '14:00:00'::TIME THEN
                SELECT id, start_time_24h, end_time_24h, late_after_24h INTO v_matched_shift_id, v_matched_shift_start, v_matched_shift_end, v_late_after
                FROM public.gym_shifts WHERE gym_id = v_token_gym_id AND shift_type = 'Morning Shift';
            ELSE
                SELECT id, start_time_24h, end_time_24h, late_after_24h INTO v_matched_shift_id, v_matched_shift_start, v_matched_shift_end, v_late_after
                FROM public.gym_shifts WHERE gym_id = v_token_gym_id AND shift_type = 'Evening Shift';
            END IF;
        ELSE
            SELECT id, start_time_24h, end_time_24h, late_after_24h INTO v_matched_shift_id, v_matched_shift_start, v_matched_shift_end, v_late_after
            FROM public.gym_shifts WHERE id = v_assigned_shift_id;
        END IF;

        IF v_matched_shift_id IS NULL THEN
            v_err_msg := 'Gym shifts are not defined or shift assignment is invalid.';
            RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
        END IF;

        -- Check if staff is checking in for the wrong shift
        IF v_assigned_shift_type IN ('Morning Shift', 'Evening Shift') THEN
            -- Verify current local time matched shift
            IF (v_assigned_shift_type = 'Morning Shift' AND v_local_time >= '14:00:00'::TIME) OR
               (v_assigned_shift_type = 'Evening Shift' AND v_local_time < '14:00:00'::TIME) THEN
                v_err_msg := 'You are scanning during the wrong shift window.';
                PERFORM public.log_attendance_alert(v_token_gym_id, 'Wrong Shift', v_user_name || ' tried checking in for wrong shift.', jsonb_build_object('staff_id', v_staff_id));
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;
        END IF;

        -- Check approved leave
        SELECT id, leave_duration INTO v_leave_id, v_leave_duration
        FROM public.leave_requests
        WHERE staff_id = v_staff_id AND status = 'Approved' AND v_local_date BETWEEN start_date AND end_date
        LIMIT 1;

        IF v_leave_id IS NOT NULL THEN
            -- If on Full Leave or leave matches the current shift
            IF v_leave_duration = 'Full Day' OR
               (v_leave_duration = 'Morning' AND v_local_time < '14:00:00'::TIME) OR
               (v_leave_duration = 'Evening' AND v_local_time >= '14:00:00'::TIME) THEN
                v_err_msg := 'You are on approved leave for this shift.';
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;
        END IF;

        -- Find most recent open check-in log for staff for this shift today
        SELECT * INTO v_last_log
        FROM public.attendance_logs
        WHERE user_id = p_user_id
          AND gym_id = v_token_gym_id
          AND user_type = 'Staff'
          AND shift_id = v_matched_shift_id
          AND date = v_local_date_str
        ORDER BY check_in DESC
        LIMIT 1;

        IF v_last_log IS NULL THEN
            -- CHECK-IN ACTION
            
            -- Check late threshold
            v_late_after := COALESCE(v_late_after, v_matched_shift_start);
            IF v_local_time > v_late_after THEN
                v_status := 'Late';
                -- Calculate late minutes
                v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_matched_shift_start)) / 60;
                IF v_late_mins < 0 THEN v_late_mins := 0; END IF;
                PERFORM public.log_attendance_alert(v_token_gym_id, 'Late Entry', v_user_name || ' checked in late by ' || v_late_mins || ' mins.', jsonb_build_object('staff_id', v_staff_id, 'late_minutes', v_late_mins));
            END IF;

            INSERT INTO public.attendance_logs (
                gym_id, user_id, user_type, shift_id, check_in, date, status, shift_status, method, display_id, qr_token_id, qr_type, late_minutes
            )
            VALUES (
                v_token_gym_id, p_user_id, 'Staff', v_matched_shift_id, v_local_now, v_local_date_str, v_status, 'Incomplete', p_method, v_display_id, p_token, v_qr_type, v_late_mins
            )
            RETURNING id INTO v_log_id;

            -- Mark token as used if dynamic
            IF v_qr_type = 'Dynamic' THEN
                UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
            END IF;

            -- Process other shifts for Half Day / Both Shifts updates
            PERFORM public.recalculate_staff_daily_status(p_user_id, v_token_gym_id, v_local_date_str, v_assigned_shift_type);

            RETURN jsonb_build_object(
                'success', TRUE,
                'logId', v_log_id,
                'userName', v_user_name,
                'userType', 'Staff',
                'action', 'Check-In',
                'status', v_status,
                'checkInTime', to_char(v_local_now, 'hh:mi AM')
            );

        ELSE
            -- CHECK-OUT ACTION
            IF v_last_log.check_out IS NOT NULL THEN
                v_err_msg := 'Already checked out for this shift today.';
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;

            -- Calculate working minutes
            v_working_mins := EXTRACT(EPOCH FROM (v_local_now - v_last_log.check_in)) / 60;
            
            -- Early exit check
            IF v_local_time < v_matched_shift_end THEN
                v_status := 'Early Exit';
                v_early_exit_mins := EXTRACT(EPOCH FROM (v_matched_shift_end - v_local_time)) / 60;
                IF v_early_exit_mins < 0 THEN v_early_exit_mins := 0; END IF;
                PERFORM public.log_attendance_alert(v_token_gym_id, 'Early Exit', v_user_name || ' checked out early by ' || v_early_exit_mins || ' mins.', jsonb_build_object('staff_id', v_staff_id, 'early_exit_minutes', v_early_exit_mins));
            ELSE
                v_status := v_last_log.status; -- Keep Present or Late
            END IF;

            -- Overtime check
            IF v_local_time > v_matched_shift_end THEN
                v_overtime_mins := EXTRACT(EPOCH FROM (v_local_time - v_matched_shift_end)) / 60;
                IF v_overtime_mins < 0 THEN v_overtime_mins := 0; END IF;
                -- If they worked past shift, keep status and append Overtime
                v_status := 'Overtime';
            END IF;

            UPDATE public.attendance_logs
            SET check_out = v_local_now,
                working_minutes = v_working_mins,
                early_exit_minutes = v_early_exit_mins,
                overtime_minutes = v_overtime_mins,
                status = v_status,
                shift_status = 'Completed',
                updated_at = now()
            WHERE id = v_last_log.id;

            -- Mark token as used if dynamic
            IF v_qr_type = 'Dynamic' THEN
                UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
            END IF;

            -- Process daily status recalculation
            PERFORM public.recalculate_staff_daily_status(p_user_id, v_token_gym_id, v_local_date_str, v_assigned_shift_type);

            RETURN jsonb_build_object(
                'success', TRUE,
                'logId', v_last_log.id,
                'userName', v_user_name,
                'userType', 'Staff',
                'action', 'Check-Out',
                'status', v_status,
                'checkOutTime', to_char(v_local_now, 'hh:mi AM'),
                'workingMins', v_working_mins
            );
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ====================================================
-- 3. Recalculate Staff Daily Status (Both Shifts & Half Days)
-- ====================================================

CREATE OR REPLACE FUNCTION public.recalculate_staff_daily_status(
    p_user_id UUID,
    p_gym_id UUID,
    p_date_str TEXT,
    p_assignment_type TEXT
)
RETURNS VOID AS $$
DECLARE
    v_morning_log RECORD;
    v_evening_log RECORD;
    v_morning_shift_id UUID;
    v_evening_shift_id UUID;
    v_final_status TEXT;
    v_staff_id UUID;
BEGIN
    SELECT id INTO v_staff_id FROM public.staff WHERE user_id = p_user_id AND gym_id = p_gym_id LIMIT 1;
    
    IF p_assignment_type = 'Both Shifts' THEN
        -- Get shift IDs
        SELECT id INTO v_morning_shift_id FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Morning Shift';
        SELECT id INTO v_evening_shift_id FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Evening Shift';

        -- Get today's logs for Morning & Evening
        SELECT * INTO v_morning_log FROM public.attendance_logs 
        WHERE user_id = p_user_id AND gym_id = p_gym_id AND date = p_date_str AND shift_id = v_morning_shift_id;
        
        SELECT * INTO v_evening_log FROM public.attendance_logs 
        WHERE user_id = p_user_id AND gym_id = p_gym_id AND date = p_date_str AND shift_id = v_evening_shift_id;

        -- Resolve daily overall status:
        IF v_morning_log.id IS NOT NULL AND v_evening_log.id IS NOT NULL THEN
            IF v_morning_log.status = 'Late' OR v_evening_log.status = 'Late' THEN
                v_final_status := 'Late';
            ELSIF v_morning_log.status = 'Early Exit' OR v_evening_log.status = 'Early Exit' THEN
                v_final_status := 'Early Exit';
            ELSIF v_morning_log.status = 'Overtime' OR v_evening_log.status = 'Overtime' THEN
                v_final_status := 'Overtime';
            ELSE
                v_final_status := 'Present';
            END IF;
        ELSIF v_morning_log.id IS NOT NULL AND v_evening_log.id IS NULL THEN
            IF EXISTS (
                SELECT 1 FROM public.leave_requests 
                WHERE staff_id = v_staff_id AND status = 'Approved' 
                  AND (p_date_str::DATE BETWEEN start_date AND end_date)
                  AND leave_duration = 'Evening'
            ) THEN
                v_final_status := 'Half Leave';
            ELSE
                v_final_status := 'Half Day';
            END IF;
        ELSIF v_morning_log.id IS NULL AND v_evening_log.id IS NOT NULL THEN
            IF EXISTS (
                SELECT 1 FROM public.leave_requests 
                WHERE staff_id = v_staff_id AND status = 'Approved' 
                  AND (p_date_str::DATE BETWEEN start_date AND end_date)
                  AND leave_duration = 'Morning'
            ) THEN
                v_final_status := 'Half Leave';
            ELSE
                v_final_status := 'Half Day';
            END IF;
        ELSE
            v_final_status := 'Absent';
        END IF;

        -- Update statuses for all logs today
        IF v_morning_log.id IS NOT NULL THEN
            UPDATE public.attendance_logs SET status = v_final_status WHERE id = v_morning_log.id;
        END IF;
        IF v_evening_log.id IS NOT NULL THEN
            UPDATE public.attendance_logs SET status = v_final_status WHERE id = v_evening_log.id;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ====================================================
-- 5. Owner Dashboard Stats View Function
-- ====================================================

CREATE OR REPLACE FUNCTION public.get_owner_attendance_dashboard(
    p_gym_id UUID,
    p_date_str TEXT DEFAULT to_char(CURRENT_DATE, 'dd-MM-yyyy')
)
RETURNS JSONB AS $$
DECLARE
    v_members_present INT := 0;
    v_staff_present INT := 0;
    v_late_staff INT := 0;
    v_early_exit_staff INT := 0;
    v_half_day INT := 0;
    v_absent INT := 0;
    v_incomplete_att INT := 0;
    v_overtime INT := 0;
    v_pending_checkout INT := 0;
BEGIN
    -- Members Present
    SELECT COUNT(DISTINCT user_id) INTO v_members_present
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND user_type = 'Member' AND date = p_date_str;

    -- Staff Present
    SELECT COUNT(DISTINCT user_id) INTO v_staff_present
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND user_type = 'Staff' AND date = p_date_str;

    -- Late Staff
    SELECT COUNT(DISTINCT user_id) INTO v_late_staff
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND user_type = 'Staff' AND date = p_date_str 
      AND (status = 'Late' OR late_minutes > 0);

    -- Early Exit Staff
    SELECT COUNT(DISTINCT user_id) INTO v_early_exit_staff
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND user_type = 'Staff' AND date = p_date_str 
      AND (status = 'Early Exit' OR early_exit_minutes > 0);

    -- Half Day
    SELECT COUNT(DISTINCT user_id) INTO v_half_day
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND user_type = 'Staff' AND date = p_date_str AND status = 'Half Day';

    -- Overtime
    SELECT COUNT(DISTINCT user_id) INTO v_overtime
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND user_type = 'Staff' AND date = p_date_str 
      AND (status = 'Overtime' OR overtime_minutes > 0);

    -- Incomplete Attendance
    SELECT COUNT(DISTINCT user_id) INTO v_incomplete_att
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND user_type = 'Staff' AND date = p_date_str AND check_out IS NULL;

    -- Absent Staff
    SELECT COUNT(*) INTO v_absent
    FROM public.staff s
    WHERE s.gym_id = p_gym_id AND s.status = 'Active'
      AND NOT EXISTS (
          SELECT 1 FROM public.attendance_logs l 
          WHERE l.user_id = s.user_id AND l.gym_id = p_gym_id AND l.date = p_date_str
      )
      AND NOT EXISTS (
          SELECT 1 FROM public.leave_requests r
          WHERE r.staff_id = s.id AND r.status = 'Approved' 
            AND p_date_str::DATE BETWEEN r.start_date AND r.end_date AND r.leave_duration = 'Full Day'
      );

    RETURN jsonb_build_object(
        'members_present', v_members_present,
        'staff_present', v_staff_present,
        'late_staff', v_late_staff,
        'early_exit_staff', v_early_exit_staff,
        'half_day', v_half_day,
        'absent', v_absent,
        'incomplete_attendance', v_incomplete_att,
        'overtime', v_overtime,
        'pending_checkout', v_incomplete_att
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ====================================================
-- 6. Attendance Correction Request Functions
-- ====================================================

CREATE OR REPLACE FUNCTION public.submit_attendance_correction(
    p_gym_id UUID,
    p_staff_user_id UUID,
    p_log_id UUID,
    p_date DATE,
    p_check_in TIMESTAMPTZ,
    p_check_out TIMESTAMPTZ,
    p_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_staff_id UUID;
    v_req_id UUID;
BEGIN
    SELECT id INTO v_staff_id FROM public.staff WHERE user_id = p_staff_user_id AND gym_id = p_gym_id LIMIT 1;
    
    IF v_staff_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Staff record not found.');
    END IF;

    INSERT INTO public.attendance_correction_requests (
        gym_id, staff_id, attendance_log_id, request_date, requested_check_in, requested_check_out, reason, status
    )
    VALUES (
        p_gym_id, v_staff_id, p_log_id, p_date, p_check_in, p_check_out, p_reason, 'Pending'
    )
    RETURNING id INTO v_req_id;

    -- Alert the owner
    PERFORM public.log_attendance_alert(p_gym_id, 'Attendance Correction', 'New correction request submitted by ' || (SELECT name FROM public.staff WHERE id = v_staff_id), jsonb_build_object('request_id', v_req_id));

    RETURN jsonb_build_object('success', TRUE, 'requestId', v_req_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.review_attendance_correction(
    p_request_id UUID,
    p_status TEXT,
    p_reviewer_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_req RECORD;
    v_local_date_str TEXT;
    v_assigned_shift_type TEXT;
    v_staff_user_id UUID;
BEGIN
    SELECT * INTO v_req FROM public.attendance_correction_requests WHERE id = p_request_id;
    IF v_req IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Request not found.');
    END IF;

    IF v_req.status <> 'Pending' THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Request has already been reviewed.');
    END IF;

    UPDATE public.attendance_correction_requests
    SET status = p_status,
        reviewed_by = p_reviewer_id,
        reviewed_at = now(),
        updated_at = now()
    WHERE id = p_request_id;

    IF p_status = 'Approved' THEN
        -- Check if we should update an existing log or insert a new one
        IF v_req.attendance_log_id IS NOT NULL THEN
            UPDATE public.attendance_logs
            SET check_in = v_req.requested_check_in,
                check_out = v_req.requested_check_out,
                status = 'Present',
                updated_at = now()
            WHERE id = v_req.attendance_log_id;
        ELSE
            -- Insert correction log
            v_local_date_str := to_char(v_req.request_date, 'dd-MM-yyyy');
            SELECT user_id INTO v_staff_user_id FROM public.staff WHERE id = v_req.staff_id;
            
            INSERT INTO public.attendance_logs (
                gym_id, user_id, user_type, check_in, check_out, date, status, method, shift_status
            )
            VALUES (
                v_req.gym_id, v_staff_user_id, 'Staff', v_req.requested_check_in, v_req.requested_check_out, v_local_date_str, 'Present', 'Manual', 'Completed'
            );
        END IF;

        -- Recalculate daily status
        SELECT user_id INTO v_staff_user_id FROM public.staff WHERE id = v_req.staff_id;
        SELECT assignment_type INTO v_assigned_shift_type FROM public.staff_shift_assignments WHERE staff_id = v_req.staff_id AND status = 'Active' LIMIT 1;
        v_local_date_str := to_char(v_req.request_date, 'dd-MM-yyyy');
        PERFORM public.recalculate_staff_daily_status(v_staff_user_id, v_req.gym_id, v_local_date_str, v_assigned_shift_type);
    END IF;

    RETURN jsonb_build_object('success', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
