-- ====================================================
-- GYMOS - ENTERPRISE ATTENDANCE SYSTEM MIGRATION
-- ====================================================

-- 1. Create Tables
CREATE TABLE IF NOT EXISTS public.attendance_settings (
    gym_id UUID PRIMARY KEY REFERENCES public.gyms(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    method TEXT DEFAULT 'QR Only' CHECK (method IN ('QR Only', 'WiFi Only', 'QR + WiFi', 'Static QR + WiFi')),
    qr_validity_seconds INT DEFAULT 150 NOT NULL,
    wifi_ssid TEXT DEFAULT '',
    wifi_bssid TEXT DEFAULT '',
    static_qr_token TEXT DEFAULT gen_random_uuid()::text NOT NULL,
    static_qr_locked BOOLEAN DEFAULT FALSE NOT NULL,
    late_time_setting TEXT DEFAULT '09:05 AM' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.attendance_display_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_id UUID UNIQUE NOT NULL,
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    browser_fingerprint TEXT NOT NULL,
    device_name TEXT,
    is_verified BOOLEAN DEFAULT FALSE NOT NULL,
    last_seen TIMESTAMPTZ DEFAULT now() NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.attendance_qr_tokens (
    token TEXT PRIMARY KEY,
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    display_id UUID,
    nonce TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_used BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    user_type TEXT NOT NULL CHECK (user_type IN ('Member', 'Staff')),
    method TEXT NOT NULL CHECK (method IN ('Dynamic QR', 'Static QR', 'WiFi', 'Static QR + WiFi', 'Manual')),
    device_info TEXT,
    display_id UUID,
    check_in TIMESTAMPTZ NOT NULL,
    check_out TIMESTAMPTZ,
    working_hours NUMERIC(5,2),
    status TEXT NOT NULL CHECK (status IN ('Present', 'Late', 'Absent', 'On Leave')),
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Seed attendance settings automatically when a gym is created
CREATE OR REPLACE FUNCTION public.fn_on_gym_created_attendance()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.attendance_settings (gym_id)
    VALUES (NEW.id)
    ON CONFLICT (gym_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_seed_attendance_settings
AFTER INSERT ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.fn_on_gym_created_attendance();

-- Seed settings for existing gyms
INSERT INTO public.attendance_settings (gym_id)
SELECT id FROM public.gyms
ON CONFLICT (gym_id) DO NOTHING;

-- 2. Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_att_logs_lookup ON public.attendance_logs(gym_id, user_id, check_in DESC);
CREATE INDEX IF NOT EXISTS idx_att_display_lookup ON public.attendance_display_sessions(gym_id, display_id);
CREATE INDEX IF NOT EXISTS idx_att_tokens_lookup ON public.attendance_qr_tokens(token, expires_at DESC);

-- 3. Row-Level Security (RLS) Policies
ALTER TABLE public.attendance_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_display_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_qr_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY attendance_settings_isolation ON public.attendance_settings
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY attendance_display_sessions_isolation ON public.attendance_display_sessions
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY attendance_qr_tokens_isolation ON public.attendance_qr_tokens
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY attendance_logs_isolation ON public.attendance_logs
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- Grants
GRANT ALL ON TABLE public.attendance_settings TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_display_sessions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_qr_tokens TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_logs TO anon, authenticated, service_role;

-- ====================================================
-- 4. RPC ENDPOINTS & BUSINESS LOGIC
-- ====================================================

-- 4.1 Register / Upsert Attendance Display Session
CREATE OR REPLACE FUNCTION public.register_display_session(
    p_display_id UUID,
    p_gym_id UUID,
    p_browser_fingerprint TEXT,
    p_device_name TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_session RECORD;
BEGIN
    INSERT INTO public.attendance_display_sessions (
        display_id,
        gym_id,
        browser_fingerprint,
        device_name,
        is_verified,
        last_seen
    )
    VALUES (
        p_display_id,
        p_gym_id,
        p_browser_fingerprint,
        p_device_name,
        FALSE,
        now()
    )
    ON CONFLICT (display_id) DO UPDATE
    SET last_seen = now(),
        browser_fingerprint = p_browser_fingerprint,
        device_name = p_device_name
    RETURNING * INTO v_session;

    RETURN jsonb_build_object(
        'success', TRUE,
        'display_id', v_session.display_id,
        'gym_id', v_session.gym_id,
        'is_verified', v_session.is_verified,
        'last_seen', v_session.last_seen
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4.2 Send Heartbeat for Display
CREATE OR REPLACE FUNCTION public.send_display_heartbeat(p_display_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_updated_at TIMESTAMPTZ;
    v_is_verified BOOLEAN;
    v_gym_name TEXT;
    v_gym_id UUID;
BEGIN
    UPDATE public.attendance_display_sessions
    SET last_seen = now()
    WHERE display_id = p_display_id
    RETURNING last_seen, is_verified, gym_id INTO v_updated_at, v_is_verified, v_gym_id;

    IF v_updated_at IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display session not found');
    END IF;

    SELECT name INTO v_gym_name FROM public.gyms WHERE id = v_gym_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'last_seen', v_updated_at,
        'is_verified', v_is_verified,
        'gym_name', v_gym_name
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4.3 Verify Display Device
CREATE OR REPLACE FUNCTION public.verify_display_device(p_display_id UUID, p_gym_id UUID)
RETURNS JSONB AS $$
BEGIN
    UPDATE public.attendance_display_sessions
    SET is_verified = TRUE,
        gym_id = p_gym_id
    WHERE display_id = p_display_id;

    RETURN jsonb_build_object('success', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4.4 Generate Dynamic QR Token
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

-- 4.5 Process Scan Attendance (Member / Staff)
CREATE OR REPLACE FUNCTION public.process_scan_attendance(
    p_token TEXT,
    p_user_id UUID,
    p_method TEXT,
    p_ssid TEXT,
    p_bssid TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_gym_id UUID;
    v_user_type TEXT;
    v_user_name TEXT;
    v_settings RECORD;
    v_token_record RECORD;
    v_today_start TIMESTAMPTZ;
    v_existing_log RECORD;
    v_status TEXT := 'Present';
    v_work_hours NUMERIC(5,2);
    v_display_id UUID;
BEGIN
    -- Get user details
    SELECT gym_id, 'Member', name INTO v_gym_id, v_user_type, v_user_name
    FROM public.members WHERE user_id = p_user_id;

    IF v_gym_id IS NULL THEN
        SELECT gym_id, 'Staff', name INTO v_gym_id, v_user_type, v_user_name
        FROM public.staff WHERE user_id = p_user_id;
    END IF;

    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User profile not linked to any Gym');
    END IF;

    -- Load Settings
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_gym_id;
    IF NOT v_settings.is_enabled THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is disabled by the owner');
    END IF;

    -- 1. WiFi check if rule matches
    IF v_settings.method IN ('WiFi Only', 'QR + WiFi', 'Static QR + WiFi') THEN
        IF p_ssid IS NULL OR p_ssid <> v_settings.wifi_ssid THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'You must be connected to the Gym WiFi (' || v_settings.wifi_ssid || ')');
        END IF;
    END IF;

    -- 2. Token validation based on method
    IF p_method = 'Dynamic QR' THEN
        SELECT * INTO v_token_record FROM public.attendance_qr_tokens WHERE token = p_token;
        IF v_token_record IS NULL THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid QR Code');
        END IF;
        IF v_token_record.is_used THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'This QR Code has already been used');
        END IF;
        IF v_token_record.expires_at < now() THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code expired. Please scan the refreshed QR.');
        END IF;
        
        v_display_id := v_token_record.display_id;
        
        -- Mark token as used
        UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
    ELSIF p_method = 'Static QR' THEN
        IF p_token <> v_settings.static_qr_token THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid Static QR Code');
        END IF;
    END IF;

    v_today_start := date_trunc('day', now());

    -- 3. User Role based attendance check
    IF v_user_type = 'Member' THEN
        -- Check if already marked today
        SELECT * INTO v_existing_log 
        FROM public.attendance_logs 
        WHERE user_id = p_user_id AND check_in >= v_today_start
        LIMIT 1;

        IF v_existing_log IS NOT NULL THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance already marked for today');
        END IF;

        -- Create Member Attendance (Check-in only)
        INSERT INTO public.attendance_logs (gym_id, user_id, user_type, method, display_id, check_in, status)
        VALUES (v_gym_id, p_user_id, 'Member', p_method, v_display_id, now(), 'Present');

        RETURN jsonb_build_object(
            'success', TRUE,
            'userName', v_user_name,
            'userType', 'Member',
            'action', 'Check-In',
            'checkInTime', to_char(now(), 'hh:mm a'),
            'status', 'Present'
        );
    ELSE
        -- Staff Attendance (Check-in/Check-out support)
        SELECT * INTO v_existing_log 
        FROM public.attendance_logs 
        WHERE user_id = p_user_id AND check_in >= v_today_start AND check_out IS NULL
        LIMIT 1;

        IF v_existing_log IS NOT NULL THEN
            -- Check-Out
            v_work_hours := ROUND((EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 3600.0)::numeric, 2);
            
            UPDATE public.attendance_logs
            SET check_out = now(),
                working_hours = v_work_hours
            WHERE id = v_existing_log.id;

            RETURN jsonb_build_object(
                'success', TRUE,
                'userName', v_user_name,
                'userType', 'Staff',
                'action', 'Check-Out',
                'checkOutTime', to_char(now(), 'hh:mm a'),
                'workingHours', v_work_hours,
                'status', v_existing_log.status
            );
        ELSE
            -- Check-In
            -- Calculate if Late based on late_time_setting
            DECLARE
                v_limit_time TIME;
                v_current_time TIME := now()::time;
            BEGIN
                v_limit_time := to_timestamp(v_settings.late_time_setting, 'hh:mi AM')::time;
                IF v_current_time > v_limit_time THEN
                    v_status := 'Late';
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_status := 'Present';
            END;

            INSERT INTO public.attendance_logs (gym_id, user_id, user_type, method, display_id, check_in, status)
            VALUES (v_gym_id, p_user_id, 'Staff', p_method, v_display_id, now(), v_status);

            RETURN jsonb_build_object(
                'success', TRUE,
                'userName', v_user_name,
                'userType', 'Staff',
                'action', 'Check-In',
                'checkInTime', to_char(now(), 'hh:mm a'),
                'status', v_status
            );
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
