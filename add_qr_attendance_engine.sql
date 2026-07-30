-- ====================================================
-- GYMOS - QR ATTENDANCE ENGINE MIGRATION
-- ====================================================

-- 1. Extend or Ensure Attendance Settings Table Structure
-- The existing fields are: gym_id, is_enabled, method, qr_validity_seconds, wifi_ssid, wifi_bssid, static_qr_token, static_qr_locked, late_time_setting
-- Let's ensure the table exists and update constraints for valid methods.
ALTER TABLE public.attendance_settings 
DROP CONSTRAINT IF EXISTS chk_attendance_method;

ALTER TABLE public.attendance_settings
ADD CONSTRAINT chk_attendance_method 
CHECK (method IN ('Static QR', 'Dynamic QR', 'Static QR + WiFi', 'Dynamic QR + WiFi', 'WiFi Only', 'QR Only', 'QR + WiFi'));

-- 2. Create Attendance Tokens (For dynamic verification tokens mapped to displays/gyms)
CREATE TABLE IF NOT EXISTS public.attendance_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    display_id UUID REFERENCES public.attendance_displays(id) ON DELETE SET NULL,
    token TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_used BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing for token validation speed
CREATE INDEX IF NOT EXISTS idx_att_tokens_lookup ON public.attendance_tokens(token, expires_at, is_used);

-- Enable RLS
ALTER TABLE public.attendance_tokens ENABLE ROW LEVEL SECURITY;

-- RLS Policy for Attendance Tokens
CREATE POLICY tokens_isolation ON public.attendance_tokens
    FOR ALL TO authenticated
    USING (gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    ));

GRANT ALL ON TABLE public.attendance_tokens TO anon, authenticated, service_role;

-- 3. Core RPC: Process Attendance Scan (Both Members & Staff)
CREATE OR REPLACE FUNCTION public.process_scan_attendance_v2(
    p_token TEXT,
    p_user_id UUID,
    p_method TEXT,
    p_ssid TEXT DEFAULT '',
    p_bssid TEXT DEFAULT ''
)
RETURNS JSONB AS $$
DECLARE
    v_gym_id UUID;
    v_user_type TEXT;
    v_user_name TEXT;
    v_membership_status TEXT;
    v_settings RECORD;
    v_display_id UUID;
    
    -- Token validation variables
    v_token_valid BOOLEAN := FALSE;
    v_token_expires TIMESTAMPTZ;
    v_token_used BOOLEAN;
    
    -- Staff working hours tracking
    v_last_log RECORD;
    v_check_out_time TIMESTAMPTZ;
    v_working_hours NUMERIC;
    
    -- Log storage variables
    v_log_id UUID;
    v_status TEXT := 'Present';
    v_late_threshold_time TIME;
    v_check_in_time TIME;
BEGIN
    -- 1. Identify User Type, Name, and Membership
    -- Check if Staff
    SELECT 'Staff', name INTO v_user_type, v_user_name 
    FROM public.staff 
    WHERE user_id = p_user_id 
    LIMIT 1;

    -- Check if Member (if not staff)
    IF v_user_type IS NULL THEN
        -- Using profiles linked to member
        SELECT 'Member', p.full_name, m.status INTO v_user_type, v_user_name, v_membership_status 
        FROM public.members m
        JOIN public.profiles p ON m.user_id = p.id
        WHERE m.user_id = p_user_id 
        LIMIT 1;
    END IF;

    IF v_user_type IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User profile not found in Gym database.');
    END IF;

    -- 2. Resolve & Validate Token (Supports Static QR token in settings OR Dynamic QR token in attendance_tokens)
    -- Check if token is Static QR token matching active settings
    SELECT gym_id, is_enabled, method, static_qr_token, static_qr_locked, late_time_setting
    INTO v_settings
    FROM public.attendance_settings
    WHERE static_qr_token = p_token
    LIMIT 1;

    IF v_settings IS NOT NULL THEN
        -- Token resolved via Static QR settings
        v_gym_id := v_settings.gym_id;
        v_token_valid := TRUE;
        
        IF NOT v_settings.is_enabled THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is currently disabled.');
        END IF;

        IF v_settings.method <> 'Static QR' AND v_settings.method <> 'Static QR + WiFi' THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Static QR attendance is not currently active.');
        END IF;
    ELSE
        -- Token might be a Dynamic QR token in attendance_tokens
        SELECT gym_id, display_id, expires_at, is_used 
        INTO v_gym_id, v_display_id, v_token_expires, v_token_used
        FROM public.attendance_tokens
        WHERE token = p_token
        LIMIT 1;

        IF v_gym_id IS NOT NULL THEN
            -- Verify expiration
            IF v_token_expires < now() THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has expired.');
            END IF;

            IF v_token_used THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has already been scanned.');
            END IF;

            v_token_valid := TRUE;

            -- Check active settings for dynamic verification method
            SELECT is_enabled, method, late_time_setting
            INTO v_settings
            FROM public.attendance_settings
            WHERE gym_id = v_gym_id
            LIMIT 1;

            IF NOT v_settings.is_enabled THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is currently disabled.');
            END IF;

            IF v_settings.method <> 'Dynamic QR' AND v_settings.method <> 'Dynamic QR + WiFi' AND v_settings.method <> 'QR Only' AND v_settings.method <> 'QR + WiFi' THEN
                RETURN jsonb_build_object('success', FALSE, 'reason', 'Dynamic QR attendance is not active.');
            END IF;
        END IF;
    END IF;

    -- If token could not be resolved or validated
    IF NOT v_token_valid THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid or unrecognized QR Code.');
    END IF;

    -- 3. Verify User belongs to Gym & Check Membership Status (Members only)
    IF v_user_type = 'Member' THEN
        -- Check if member belongs to resolved Gym
        IF NOT EXISTS (
            SELECT 1 FROM public.members 
            WHERE user_id = p_user_id AND gym_id = v_gym_id
        ) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'You are not registered under this Gym.');
        END IF;

        -- Verify active status
        IF v_membership_status <> 'Active' THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Membership is inactive or expired. Status: ' || COALESCE(v_membership_status, 'None'));
        END IF;
    ELSE
        -- Staff belongs to Gym verification
        IF NOT EXISTS (
            SELECT 1 FROM public.staff 
            WHERE user_id = p_user_id AND gym_id = v_gym_id
        ) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Staff record not associated with this Gym.');
        END IF;
    END IF;

    -- 4. WiFi Verification check if active method requires WiFi
    IF v_settings.method IN ('Static QR + WiFi', 'Dynamic QR + WiFi', 'QR + WiFi') THEN
        -- Check if phone's connected SSID matches saved settings SSID
        IF p_ssid <> '' AND p_ssid <> (SELECT wifi_ssid FROM public.attendance_settings WHERE gym_id = v_gym_id) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Please connect to the Gym WiFi network to scan.');
        END IF;
    END IF;

    -- 5. Mark Member Attendance
    IF v_user_type = 'Member' THEN
        -- Rule: Only ONE attendance log entry per member per calendar date
        IF EXISTS (
            SELECT 1 FROM public.attendance_logs
            WHERE user_id = p_user_id 
              AND gym_id = v_gym_id 
              AND (check_in::DATE = CURRENT_DATE OR date = to_char(CURRENT_DATE, 'dd-MM-yyyy'))
        ) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance already marked for today.');
        END IF;

        -- Determine status (Late check)
        -- Format late threshold setting to time
        BEGIN
            v_late_threshold_time := (v_settings.late_time_setting)::TIME;
            v_check_in_time := CURRENT_TIME::TIME;
            IF v_check_in_time > v_late_threshold_time THEN
                v_status := 'Late';
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_status := 'Present';
        END;

        -- Insert Log
        INSERT INTO public.attendance_logs (
            gym_id,
            user_id,
            user_type,
            check_in,
            status,
            method,
            display_id,
            date
        )
        VALUES (
            v_gym_id,
            p_user_id,
            'Member',
            now(),
            v_status,
            p_method,
            v_display_id,
            to_char(CURRENT_DATE, 'dd-MM-yyyy')
        )
        RETURNING id INTO v_log_id;

        -- If dynamic token, mark token as used
        IF v_settings IS NULL THEN
            UPDATE public.attendance_tokens SET is_used = TRUE WHERE token = p_token;
        END IF;

        RETURN jsonb_build_object(
            'success', TRUE,
            'logId', v_log_id,
            'userName', v_user_name,
            'userType', 'Member',
            'action', 'Check-In',
            'status', v_status,
            'checkInTime', to_char(now(), 'hh:mi AM')
        );

    -- 6. Mark Staff Attendance (Check-In / Check-Out toggle)
    ELSE
        -- Find most recent open check-in log for staff today
        SELECT * INTO v_last_log
        FROM public.attendance_logs
        WHERE user_id = p_user_id
          AND gym_id = v_gym_id
          AND user_type = 'Staff'
          AND check_out IS NULL
        ORDER BY check_in DESC
        LIMIT 1;

        IF v_last_log IS NULL THEN
            -- No open check-in session -> Perform CHECK-IN
            INSERT INTO public.attendance_logs (
                gym_id,
                user_id,
                user_type,
                check_in,
                status,
                method,
                display_id,
                date
            )
            VALUES (
                v_gym_id,
                p_user_id,
                'Staff',
                now(),
                'Present',
                p_method,
                v_display_id,
                to_char(CURRENT_DATE, 'dd-MM-yyyy')
            )
            RETURNING id INTO v_log_id;

            -- If dynamic token, mark token as used
            IF v_settings IS NULL THEN
                UPDATE public.attendance_tokens SET is_used = TRUE WHERE token = p_token;
            END IF;

            RETURN jsonb_build_object(
                'success', TRUE,
                'logId', v_log_id,
                'userName', v_user_name,
                'userType', 'Staff',
                'action', 'Check-In',
                'status', 'Present',
                'checkInTime', to_char(now(), 'hh:mi AM')
            );
        ELSE
            -- Open check-in session exists -> Perform CHECK-OUT
            v_check_out_time := now();
            
            -- Calculate working hours (difference in hours)
            v_working_hours := ROUND(EXTRACT(EPOCH FROM (v_check_out_time - v_last_log.check_in))::NUMERIC / 3600.0, 2);

            UPDATE public.attendance_logs
            SET check_out = v_check_out_time,
                working_hours = v_working_hours,
                display_id = COALESCE(v_display_id, display_id)
            WHERE id = v_last_log.id;

            -- If dynamic token, mark token as used
            IF v_settings IS NULL THEN
                UPDATE public.attendance_tokens SET is_used = TRUE WHERE token = p_token;
            END IF;

            RETURN jsonb_build_object(
                'success', TRUE,
                'logId', v_last_log.id,
                'userName', v_user_name,
                'userType', 'Staff',
                'action', 'Check-Out',
                'status', v_last_log.status,
                'checkInTime', to_char(v_last_log.check_in, 'hh:mi AM'),
                'checkOutTime', to_char(v_check_out_time, 'hh:mi AM'),
                'workingHours', v_working_hours
            );
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
