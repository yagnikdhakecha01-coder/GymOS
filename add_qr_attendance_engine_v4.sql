-- ====================================================
-- GYMOS - ENTERPRISE MULTI-TENANT ATTENDANCE ENGINE V4
-- ATOMIC SINGLE RPC & SECURE DISPLAY MANAGEMENT
-- ====================================================

-- Enable pgcrypto extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ----------------------------------------------------
-- 1. SCHEMAS AND TABLES ENHANCEMENTS
-- ----------------------------------------------------

-- Gym Attendance Settings
CREATE TABLE IF NOT EXISTS public.attendance_settings (
    gym_id UUID PRIMARY KEY REFERENCES public.gyms(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    method TEXT DEFAULT 'Dynamic QR' NOT NULL CHECK (method IN ('Static QR', 'Dynamic QR', 'Static QR + WiFi', 'Dynamic QR + WiFi', 'WiFi Only', 'QR Only', 'QR + WiFi')),
    qr_validity_seconds INT DEFAULT 30 NOT NULL,
    wifi_ssid TEXT DEFAULT '',
    wifi_bssid TEXT DEFAULT '',
    static_qr_token TEXT DEFAULT 'static_default_token',
    static_qr_locked BOOLEAN DEFAULT FALSE NOT NULL,
    late_time_setting TEXT DEFAULT '09:05 AM' NOT NULL,
    auto_mark_absent BOOLEAN DEFAULT FALSE NOT NULL,
    auto_close_shift BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Attendance Displays (Website Registration)
CREATE TABLE IF NOT EXISTS public.attendance_displays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    display_public_id TEXT UNIQUE NOT NULL,
    device_name TEXT,
    browser_fingerprint TEXT,
    device_secret TEXT,
    is_verified BOOLEAN DEFAULT FALSE NOT NULL,
    is_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    verified_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    verified_at TIMESTAMPTZ,
    last_seen TIMESTAMPTZ DEFAULT now() NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Attendance QR Tokens (Dynamic QR codes)
CREATE TABLE IF NOT EXISTS public.attendance_qr_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    display_id UUID REFERENCES public.attendance_displays(id) ON DELETE CASCADE,
    token TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_used BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Display Verification Tokens (For initial scanning display TV to verify)
CREATE TABLE IF NOT EXISTS public.attendance_display_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_id UUID NOT NULL REFERENCES public.attendance_displays(id) ON DELETE CASCADE,
    token TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_used BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Gym Shift Settings
CREATE TABLE IF NOT EXISTS public.gym_shift_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    mode TEXT NOT NULL DEFAULT 'Single Shift' CHECK (mode IN ('Single Shift', 'Two Shifts')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT uniq_gym_shift_settings UNIQUE (gym_id)
);

-- Gym Shifts
CREATE TABLE IF NOT EXISTS public.gym_shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    shift_type TEXT NOT NULL CHECK (shift_type IN ('Single Shift', 'Morning Shift', 'Evening Shift')),
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    start_time_24h TIME NOT NULL,
    end_time_24h TIME NOT NULL,
    late_after_24h TIME,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT uniq_gym_shift_type UNIQUE (gym_id, shift_type)
);

-- Staff Shift Assignments
CREATE TABLE IF NOT EXISTS public.staff_shift_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    shift_id UUID REFERENCES public.gym_shifts(id) ON DELETE CASCADE,
    assignment_type TEXT NOT NULL CHECK (assignment_type IN ('Single Shift', 'Morning Shift', 'Evening Shift', 'Both Shifts')),
    effective_from DATE DEFAULT CURRENT_DATE NOT NULL,
    effective_to DATE,
    status TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Completed', 'Cancelled')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Attendance Logs
CREATE TABLE IF NOT EXISTS public.attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'Staff',
    user_type TEXT DEFAULT 'Staff',
    member_id UUID REFERENCES public.members(id) ON DELETE CASCADE,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE,
    shift_id UUID REFERENCES public.gym_shifts(id) ON DELETE SET NULL,
    date TEXT NOT NULL, -- Format 'dd-MM-yyyy' or 'YYYY-MM-DD'
    check_in TIMESTAMPTZ NOT NULL,
    check_out TIMESTAMPTZ,
    method TEXT DEFAULT 'QR Code' NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('Present', 'Absent', 'Half Day', 'Late', 'Early Exit', 'Overtime', 'Leave', 'Half Leave', 'Incomplete Attendance')),
    shift_status TEXT DEFAULT 'Incomplete',
    working_minutes INT DEFAULT 0 NOT NULL,
    late_minutes INT DEFAULT 0 NOT NULL,
    early_exit_minutes INT DEFAULT 0 NOT NULL,
    overtime_minutes INT DEFAULT 0 NOT NULL,
    qr_type TEXT,
    qr_token_id TEXT,
    rule_version INT DEFAULT 1 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Ensure missing columns exist if table was already created earlier
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'Staff';
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS user_type TEXT DEFAULT 'Staff';
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS shift_id UUID;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS member_id UUID;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS staff_id UUID;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS working_minutes INT DEFAULT 0;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS late_minutes INT DEFAULT 0;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS early_exit_minutes INT DEFAULT 0;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS overtime_minutes INT DEFAULT 0;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS shift_status TEXT DEFAULT 'Incomplete';
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS qr_type TEXT;
ALTER TABLE public.attendance_logs ADD COLUMN IF NOT EXISTS qr_token_id TEXT;

-- Remove legacy check constraints on attendance_logs to avoid 23514 errors
ALTER TABLE public.attendance_logs DROP CONSTRAINT IF EXISTS attendance_logs_method_check;
ALTER TABLE public.attendance_logs DROP CONSTRAINT IF EXISTS chk_attendance_method;

-- Remove NOT NULL constraints and set default values on user_type & role
ALTER TABLE public.attendance_logs ALTER COLUMN user_type DROP NOT NULL;
ALTER TABLE public.attendance_logs ALTER COLUMN user_type SET DEFAULT 'Staff';
ALTER TABLE public.attendance_logs ALTER COLUMN role DROP NOT NULL;
ALTER TABLE public.attendance_logs ALTER COLUMN role SET DEFAULT 'Staff';

-- Backfill NULL values for historical records
UPDATE public.attendance_logs SET user_type = COALESCE(user_type, role, 'Staff') WHERE user_type IS NULL;
UPDATE public.attendance_logs SET role = COALESCE(role, user_type, 'Staff') WHERE role IS NULL;

-- Attendance Alerts
CREATE TABLE IF NOT EXISTS public.attendance_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    alert_type TEXT NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb NOT NULL,
    is_read BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexes for Speed & Performance
CREATE INDEX IF NOT EXISTS idx_att_settings_gym ON public.attendance_settings(gym_id);
CREATE INDEX IF NOT EXISTS idx_att_displays_gym ON public.attendance_displays(gym_id);
CREATE INDEX IF NOT EXISTS idx_att_displays_pub ON public.attendance_displays(display_public_id);
CREATE INDEX IF NOT EXISTS idx_att_qr_tokens_lookup ON public.attendance_qr_tokens(token, expires_at, is_used);
CREATE INDEX IF NOT EXISTS idx_att_logs_user_date ON public.attendance_logs(user_id, gym_id, date);
CREATE INDEX IF NOT EXISTS idx_att_logs_gym_date ON public.attendance_logs(gym_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_staff_shift_assign_staff ON public.staff_shift_assignments(staff_id, status);

-- ----------------------------------------------------
-- 2. ROW LEVEL SECURITY (RLS)
-- ----------------------------------------------------

ALTER TABLE public.attendance_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_displays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_qr_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_display_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_shift_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_shift_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_alerts ENABLE ROW LEVEL SECURITY;

-- Helper function to check if auth.uid() belongs to gym
CREATE OR REPLACE FUNCTION public.fn_is_user_in_gym(p_gym_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.user_gym_associations WHERE user_id = auth.uid() AND gym_id = p_gym_id
        UNION
        SELECT 1 FROM public.staff WHERE user_id = auth.uid() AND gym_id = p_gym_id
        UNION
        SELECT 1 FROM public.members WHERE user_id = auth.uid() AND gym_id = p_gym_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS Policies
DROP POLICY IF EXISTS att_settings_isolation ON public.attendance_settings;
CREATE POLICY att_settings_isolation ON public.attendance_settings
    FOR ALL TO authenticated USING (public.fn_is_user_in_gym(gym_id));

DROP POLICY IF EXISTS att_displays_isolation ON public.attendance_displays;
CREATE POLICY att_displays_isolation ON public.attendance_displays
    FOR ALL TO authenticated USING (public.fn_is_user_in_gym(gym_id));

DROP POLICY IF EXISTS att_qr_tokens_isolation ON public.attendance_qr_tokens;
CREATE POLICY att_qr_tokens_isolation ON public.attendance_qr_tokens
    FOR ALL TO authenticated USING (public.fn_is_user_in_gym(gym_id));

DROP POLICY IF EXISTS att_logs_isolation ON public.attendance_logs;
CREATE POLICY att_logs_isolation ON public.attendance_logs
    FOR ALL TO authenticated USING (public.fn_is_user_in_gym(gym_id));

DROP POLICY IF EXISTS att_alerts_isolation ON public.attendance_alerts;
CREATE POLICY att_alerts_isolation ON public.attendance_alerts
    FOR ALL TO authenticated USING (public.fn_is_user_in_gym(gym_id));

DROP POLICY IF EXISTS gym_shifts_isolation ON public.gym_shifts;
CREATE POLICY gym_shifts_isolation ON public.gym_shifts
    FOR ALL TO authenticated USING (public.fn_is_user_in_gym(gym_id));

DROP POLICY IF EXISTS staff_shift_assignments_isolation ON public.staff_shift_assignments;
CREATE POLICY staff_shift_assignments_isolation ON public.staff_shift_assignments
    FOR ALL TO authenticated USING (public.fn_is_user_in_gym(gym_id));

-- Grant permissions to anonymous & authenticated roles for RPC access
GRANT ALL ON TABLE public.attendance_settings TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_displays TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_qr_tokens TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_display_tokens TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.gym_shift_settings TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.gym_shifts TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.staff_shift_assignments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_logs TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_alerts TO anon, authenticated, service_role;

-- ----------------------------------------------------
-- 3. DISPLAY WEBSITE SECURITY & REGISTRATION RPCs
-- ----------------------------------------------------

-- RPC: Get or Create permanent Display link for a Gym
CREATE OR REPLACE FUNCTION public.get_or_create_gym_display(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_public_id TEXT;
BEGIN
    SELECT display_public_id INTO v_public_id
    FROM public.attendance_displays
    WHERE gym_id = p_gym_id
    LIMIT 1;

    IF v_public_id IS NULL THEN
        -- Generate random 9-char public ID
        v_public_id := lower(encode(gen_random_bytes(5), 'hex'));
        INSERT INTO public.attendance_displays (gym_id, display_public_id, device_name, is_verified)
        VALUES (p_gym_id, v_public_id, 'Primary Display TV', FALSE);
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'display_public_id', v_public_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Handshake when Display Link Opens on Web Browser
CREATE OR REPLACE FUNCTION public.register_display_link(
    p_public_id TEXT,
    p_fingerprint TEXT,
    p_device_name TEXT,
    p_secret TEXT DEFAULT ''
)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
    v_token TEXT;
    v_expires_at TIMESTAMPTZ;
    v_gym_name TEXT;
BEGIN
    -- Locate display record by public ID
    SELECT * INTO v_display FROM public.attendance_displays WHERE display_public_id = p_public_id;
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid Display Link');
    END IF;

    SELECT name INTO v_gym_name FROM public.gyms WHERE id = v_display.gym_id;

    -- If display is disabled by owner, reject
    IF NOT v_display.is_enabled THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'This display device has been disabled by the gym owner.');
    END IF;

    -- If already verified, and secret matches stored secret
    IF v_display.is_verified AND v_display.device_secret IS NOT NULL AND v_display.device_secret = p_secret THEN
        UPDATE public.attendance_displays
        SET last_seen = now(),
            browser_fingerprint = p_fingerprint
        WHERE id = v_display.id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'status', 'VERIFIED',
            'gym_name', COALESCE(v_gym_name, 'GymOS'),
            'device_secret', v_display.device_secret
        );
    END IF;

    -- Otherwise, verification is required. Generate secure token for QR
    v_token := encode(digest(p_public_id || gen_random_uuid()::text || now()::text, 'sha256'), 'hex');
    v_expires_at := now() + INTERVAL '5 minutes';

    -- Invalidate old unused verification tokens for this display
    UPDATE public.attendance_display_tokens
    SET is_used = TRUE
    WHERE display_id = v_display.id;

    -- Store new verification token
    INSERT INTO public.attendance_display_tokens (display_id, token, expires_at)
    VALUES (v_display.id, v_token, v_expires_at);

    -- Update display record
    UPDATE public.attendance_displays
    SET browser_fingerprint = p_fingerprint,
        device_name = p_device_name,
        is_verified = FALSE,
        device_secret = NULL
    WHERE id = v_display.id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'status', 'WAITING_FOR_VERIFICATION',
        'gym_name', COALESCE(v_gym_name, 'GymOS'),
        'verification_token', v_token
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Check Verification Status (Poll from Display Website)
CREATE OR REPLACE FUNCTION public.check_display_verification_status(p_public_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
BEGIN
    SELECT * INTO v_display FROM public.attendance_displays WHERE display_public_id = p_public_id;
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display not found');
    END IF;

    IF v_display.is_verified AND v_display.is_enabled THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'is_verified', TRUE,
            'device_secret', v_display.device_secret
        );
    ELSE
        RETURN jsonb_build_object('success', TRUE, 'is_verified', FALSE);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Send Display Heartbeat
CREATE OR REPLACE FUNCTION public.send_display_heartbeat(
    p_public_id TEXT,
    p_secret TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
BEGIN
    SELECT * INTO v_display FROM public.attendance_displays WHERE display_public_id = p_public_id;
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display not found');
    END IF;

    IF NOT v_display.is_verified OR v_display.device_secret <> p_secret THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display authorization failed');
    END IF;

    UPDATE public.attendance_displays
    SET last_seen = now()
    WHERE id = v_display.id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'is_enabled', v_display.is_enabled
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Fetch Display QR Code (Only for Verified Displays)
CREATE OR REPLACE FUNCTION public.get_display_static_qr(
    p_display_public_id TEXT,
    p_secret TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
    v_settings RECORD;
    v_dynamic_token TEXT;
    v_expires_at TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_display FROM public.attendance_displays WHERE display_public_id = p_display_public_id;
    IF v_display IS NULL OR NOT v_display.is_verified OR NOT v_display.is_enabled OR v_display.device_secret <> p_secret THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Unauthorized display device');
    END IF;

    -- Fetch attendance settings for the gym
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_display.gym_id;

    -- If mode is Dynamic QR, generate dynamic token
    IF v_settings IS NOT NULL AND v_settings.method IN ('Dynamic QR', 'Dynamic QR + WiFi', 'QR Only', 'QR + WiFi') THEN
        v_dynamic_token := 'dyn_' || encode(gen_random_bytes(12), 'hex');
        v_expires_at := now() + ((COALESCE(v_settings.qr_validity_seconds, 30) || ' seconds')::INTERVAL);

        INSERT INTO public.attendance_qr_tokens (gym_id, display_id, token, expires_at)
        VALUES (v_display.gym_id, v_display.id, v_dynamic_token, v_expires_at);

        RETURN jsonb_build_object(
            'success', TRUE,
            'qr_type', 'Dynamic',
            'static_qr_token', v_dynamic_token,
            'expires_in_seconds', COALESCE(v_settings.qr_validity_seconds, 30)
        );
    ELSE
        -- Return static token from settings
        RETURN jsonb_build_object(
            'success', TRUE,
            'qr_type', 'Static',
            'static_qr_token', COALESCE(v_settings.static_qr_token, 'static_default_token')
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Verify Display Token from Owner App (Scanning Display TV)
CREATE OR REPLACE FUNCTION public.verify_display_token(
    p_token TEXT,
    p_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_token_record RECORD;
    v_display RECORD;
    v_gym_id UUID;
    v_new_secret TEXT;
BEGIN
    -- Locate verification token
    SELECT * INTO v_token_record FROM public.attendance_display_tokens WHERE token = p_token;
    IF v_token_record IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid verification token');
    END IF;

    IF v_token_record.is_used THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'This token has already been used');
    END IF;

    IF v_token_record.expires_at < now() THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Verification token has expired');
    END IF;

    -- Get display record
    SELECT * INTO v_display FROM public.attendance_displays WHERE id = v_token_record.display_id;
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Associated display not found');
    END IF;

    v_gym_id := v_display.gym_id;

    -- Verify scanning user belongs to this gym as owner/admin
    IF NOT EXISTS (
        SELECT 1 FROM public.user_gym_associations 
        WHERE user_id = p_user_id AND gym_id = v_gym_id
    ) THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'You do not have permission to verify displays for this Gym.');
    END IF;

    -- Generate device secret
    v_new_secret := 'sec_' || encode(gen_random_bytes(16), 'hex');

    -- Mark token used
    UPDATE public.attendance_display_tokens SET is_used = TRUE WHERE id = v_token_record.id;

    -- Activate & verify display
    UPDATE public.attendance_displays
    SET is_verified = TRUE,
        is_enabled = TRUE,
        device_secret = v_new_secret,
        verified_by = p_user_id,
        verified_at = now(),
        last_seen = now()
    WHERE id = v_display.id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Display device verified successfully!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ----------------------------------------------------
-- 4. CORE ATOMIC ATTENDANCE RPC (SINGLE TRANSACTION)
-- ----------------------------------------------------

CREATE OR REPLACE FUNCTION public.process_qr_attendance(p_token TEXT)
RETURNS JSONB AS $$
DECLARE
    v_scanner_uid UUID := auth.uid();
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date_str TEXT := to_char(v_local_now, 'YYYY-MM-DD');

    -- Identified Gym & Display
    v_gym_id UUID;
    v_display_id UUID;
    v_token_expires TIMESTAMPTZ;
    v_token_used BOOLEAN;
    v_token_valid BOOLEAN := FALSE;
    v_qr_type TEXT := 'Dynamic';

    -- Settings
    v_settings RECORD;

    -- User Profile / Member / Staff Identification
    v_user_type TEXT;
    v_user_name TEXT;
    v_member_id UUID;
    v_member_status TEXT;
    v_staff_id UUID;
    v_staff_status TEXT;

    -- Shift variables
    v_shift_assignment RECORD;
    v_shift_record RECORD;
    v_assigned_shift_type TEXT;
    v_shift_start TIME;
    v_shift_end TIME;
    v_late_after TIME;

    -- Attendance calculations
    v_existing_log RECORD;
    v_log_id UUID;
    v_check_in_time TIMESTAMPTZ;
    v_working_mins INT := 0;
    v_late_mins INT := 0;
    v_early_exit_mins INT := 0;
    v_status TEXT := 'Present';
    v_shift_status TEXT := 'Completed';

    v_formatted_check_in TEXT;
    v_formatted_check_out TEXT;
    v_err_msg TEXT;
BEGIN
    -- 0. Check Authentication
    IF v_scanner_uid IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User not authenticated. Please log in.');
    END IF;

    -- 1. STEP 1: VALIDATE QR TOKEN (Identify Gym & Display from Token)
    -- Check Dynamic QR Token first
    SELECT gym_id, display_id, expires_at, is_used
    INTO v_gym_id, v_display_id, v_token_expires, v_token_used
    FROM public.attendance_qr_tokens
    WHERE token = p_token
    LIMIT 1;

    IF v_gym_id IS NOT NULL THEN
        -- Dynamic Token Found
        IF (v_token_expires < now()) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has expired. Please scan the active QR code.');
        END IF;

        IF v_token_used THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has already been scanned.');
        END IF;

        v_token_valid := TRUE;
        v_qr_type := 'Dynamic';

        -- Mark Dynamic Token as Used immediately to prevent reuse
        UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
    ELSE
        -- Check Static QR Token in attendance_settings
        SELECT gym_id, is_enabled, method, static_qr_token, late_time_setting
        INTO v_settings
        FROM public.attendance_settings
        WHERE static_qr_token = p_token
        LIMIT 1;

        IF v_settings IS NOT NULL THEN
            v_gym_id := v_settings.gym_id;
            v_token_valid := TRUE;
            v_qr_type := 'Static';
        END IF;
    END IF;

    -- Invalid QR Token Check
    IF NOT v_token_valid OR v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid or unrecognized QR Code.');
    END IF;

    -- STEP 2: VALIDATE DISPLAY (If dynamic QR linked to a Display TV)
    IF v_display_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.attendance_displays 
            WHERE id = v_display_id AND gym_id = v_gym_id AND is_verified = TRUE AND is_enabled = TRUE
        ) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance display device is unverified or disabled.');
        END IF;
    END IF;

    -- Fetch Gym Attendance Settings
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_gym_id;
    IF v_settings IS NOT NULL AND NOT COALESCE(v_settings.is_enabled, TRUE) THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is currently disabled by gym administration.');
    END IF;

    -- STEP 3: IDENTIFY USER (Member vs Staff) & VALIDATE MULTI-TENANT ISOLATION
    -- Check if Staff
    SELECT id, name, status INTO v_staff_id, v_user_name, v_staff_status
    FROM public.staff
    WHERE user_id = v_scanner_uid AND gym_id = v_gym_id
    LIMIT 1;

    IF v_staff_id IS NOT NULL THEN
        v_user_type := 'Staff';
    ELSE
        -- Check if Member
        SELECT id, status INTO v_member_id, v_member_status
        FROM public.members
        WHERE user_id = v_scanner_uid AND gym_id = v_gym_id
        LIMIT 1;

        IF v_member_id IS NOT NULL THEN
            v_user_type := 'Member';
            SELECT COALESCE(full_name, 'Member') INTO v_user_name FROM public.profiles WHERE id = v_scanner_uid;
        END IF;
    END IF;

    -- Cross-Gym Isolation Check: User belongs to another gym
    IF v_user_type IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.members WHERE user_id = v_scanner_uid) OR EXISTS (SELECT 1 FROM public.staff WHERE user_id = v_scanner_uid) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'You are trying to mark attendance in another gym.');
        ELSE
            RETURN jsonb_build_object('success', FALSE, 'reason', 'User record not associated with this Gym.');
        END IF;
    END IF;

    -- ====================================================
    -- MEMBER ATTENDANCE FLOW
    -- ====================================================
    IF v_user_type = 'Member' THEN
        -- Verify membership status
        IF v_member_status NOT IN ('Active', 'Trial') THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Membership is inactive or expired. Status: ' || COALESCE(v_member_status, 'Expired'));
        END IF;

        -- Check if attendance marked today
        SELECT * INTO v_existing_log 
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR check_in::DATE = CURRENT_DATE);

        IF v_existing_log IS NOT NULL THEN
            -- Already marked today - return existing log
            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', TRUE,
                'user_type', 'Member',
                'user_name', COALESCE(v_user_name, 'Member'),
                'status', v_existing_log.status,
                'check_in', to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'attendance_date', v_existing_log.date,
                'method', v_existing_log.method,
                'message', 'Attendance already marked for today.'
            );
        END IF;

        -- Create Member Check In
        INSERT INTO public.attendance_logs (
            gym_id, user_id, role, user_type, member_id, date, check_in, status, method, qr_type
        ) VALUES (
            v_gym_id, v_scanner_uid, 'Member', 'Member', v_member_id, v_local_date_str, now(), 'Present', COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
        ) RETURNING id INTO v_log_id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'already_marked', FALSE,
            'user_type', 'Member',
            'user_name', COALESCE(v_user_name, 'Member'),
            'status', 'Present',
            'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
            'attendance_date', v_local_date_str,
            'method', 'QR Code',
            'message', 'Member attendance checked in successfully!'
        );
    END IF;

    -- ====================================================
    -- STAFF ATTENDANCE & SHIFT ENGINE FLOW
    -- ====================================================
    IF v_user_type = 'Staff' THEN
        -- Resolve Assigned Shift for Staff
        SELECT * INTO v_shift_assignment
        FROM public.staff_shift_assignments
        WHERE staff_id = v_staff_id AND gym_id = v_gym_id AND status = 'Active'
        ORDER BY created_at DESC LIMIT 1;

        v_assigned_shift_type := COALESCE(v_shift_assignment.assignment_type, 'Single Shift');

        -- Lookup Shift Definition Timings
        IF v_assigned_shift_type = 'Morning Shift' THEN
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Morning Shift';
        ELSIF v_assigned_shift_type = 'Evening Shift' THEN
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Evening Shift';
        ELSE
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Single Shift';
        END IF;

        -- SHIFT VALIDATION: Validate shift window if configured
        IF v_shift_record IS NOT NULL THEN
            v_shift_start := v_shift_record.start_time_24h;
            v_shift_end := v_shift_record.end_time_24h;

            -- If current time is way outside shift window (allow 1 hr buffer before shift start)
            IF v_local_time < (v_shift_start - INTERVAL '1 hour')::TIME OR v_local_time > (v_shift_end + INTERVAL '2 hours')::TIME THEN
                -- Format shift time nicely for error message
                v_err_msg := 'You are not assigned to this shift. Your shift is ' || 
                             COALESCE(v_shift_record.shift_type, 'Shift') || ' ' || 
                             COALESCE(v_shift_record.start_time, '') || ' - ' || COALESCE(v_shift_record.end_time, '') || '.';
                RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
            END IF;
        END IF;

        -- Fetch existing staff attendance log for today
        SELECT * INTO v_existing_log
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR check_in::DATE = CURRENT_DATE)
        ORDER BY check_in DESC LIMIT 1;

        -- NO PREVIOUS LOG TODAY -> CREATE CHECK IN
        IF v_existing_log IS NULL OR v_existing_log.check_out IS NOT NULL THEN

            -- Calculate Late Minutes if configured
            v_status := 'Present';
            v_late_mins := 0;

            IF v_settings IS NOT NULL AND v_settings.late_time_setting IS NOT NULL AND v_settings.late_time_setting <> '' THEN
                BEGIN
                    v_late_after := v_settings.late_time_setting::TIME;
                    IF v_local_time > v_late_after THEN
                        v_status := 'Late';
                        v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_late_after)) / 60;
                    END IF;
                EXCEPTION WHEN OTHERS THEN
                    v_late_mins := 0;
                END;
            END IF;

            INSERT INTO public.attendance_logs (
                gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
            ) VALUES (
                v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_shift_record.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
            ) RETURNING id INTO v_log_id;

            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', FALSE,
                'user_type', 'Staff',
                'action', 'Check In',
                'status', v_status,
                'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'late_minutes', v_late_mins,
                'shift_status', 'Incomplete',
                'message', 'Staff Check In successful!'
            );
        END IF;

        -- EXISTING LOG WITH NO CHECK OUT -> PERFORM CHECK OUT
        IF v_existing_log IS NOT NULL AND v_existing_log.check_out IS NULL THEN
            -- Calculate Working Minutes & Early Exit Minutes
            v_working_mins := EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 60;
            v_early_exit_mins := 0;

            IF v_shift_record IS NOT NULL AND v_shift_record.end_time_24h IS NOT NULL THEN
                IF v_local_time < v_shift_record.end_time_24h THEN
                    v_early_exit_mins := EXTRACT(EPOCH FROM (v_shift_record.end_time_24h - v_local_time)) / 60;
                END IF;
            END IF;

            -- Update existing attendance log with check out
            UPDATE public.attendance_logs
            SET check_out = now(),
                working_minutes = v_working_mins,
                early_exit_minutes = v_early_exit_mins,
                shift_status = 'Completed',
                updated_at = now()
            WHERE id = v_existing_log.id;

            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', TRUE,
                'user_type', 'Staff',
                'action', 'Check Out',
                'status', v_existing_log.status,
                'check_in', to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'check_out', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'working_minutes', v_working_mins,
                'early_exit_minutes', v_early_exit_mins,
                'shift_status', 'Completed',
                'message', 'Staff Check Out successful!'
            );
        END IF;

    END IF;

    RETURN jsonb_build_object('success', FALSE, 'reason', 'Unable to process attendance request.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Expose process_scan_attendance_v3 as alias wrapper for backward compatibility
CREATE OR REPLACE FUNCTION public.process_scan_attendance_v3(
    p_token TEXT,
    p_user_id UUID DEFAULT NULL,
    p_method TEXT DEFAULT 'QR Code',
    p_ssid TEXT DEFAULT '',
    p_bssid TEXT DEFAULT ''
)
RETURNS JSONB AS $$
BEGIN
    RETURN public.process_qr_attendance(p_token);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
