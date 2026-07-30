-- ====================================================
-- GYMOS - ATTENDANCE DISPLAY REGISTRATION MIGRATION
-- ====================================================

-- Drop old tables if they exist to avoid conflicts
DROP TABLE IF EXISTS public.attendance_display_tokens CASCADE;
DROP TABLE IF EXISTS public.attendance_displays CASCADE;

-- 1. Create Tables
CREATE TABLE public.attendance_displays (
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

CREATE TABLE public.attendance_display_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_id UUID NOT NULL REFERENCES public.attendance_displays(id) ON DELETE CASCADE,
    token TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_used BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing for high-performance lookup
CREATE INDEX idx_att_disp_gym ON public.attendance_displays(gym_id);
CREATE INDEX idx_att_disp_pub ON public.attendance_displays(display_public_id);
CREATE INDEX idx_att_disp_tokens_val ON public.attendance_display_tokens(token, expires_at);

-- Enable Row-Level Security (RLS)
ALTER TABLE public.attendance_displays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_display_tokens ENABLE ROW LEVEL SECURITY;

-- 2. RLS Policies
CREATE POLICY displays_isolation ON public.attendance_displays
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY tokens_isolation ON public.attendance_display_tokens
    FOR ALL TO authenticated
    USING (display_id IN (SELECT id FROM public.attendance_displays WHERE gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )));

-- Grants
GRANT ALL ON TABLE public.attendance_displays TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.attendance_display_tokens TO anon, authenticated, service_role;

-- ====================================================
-- 3. FUNCTIONS & RPC LOGIC
-- ====================================================

-- Helper: Generate random alphanumeric display public id (9 chars)
CREATE OR REPLACE FUNCTION public.fn_generate_display_public_id()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    result TEXT := '';
    i INTEGER := 0;
    v_exists BOOLEAN;
BEGIN
    LOOP
        result := '';
        FOR i IN 1..9 LOOP
            result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
        END LOOP;
        
        SELECT EXISTS(SELECT 1 FROM public.attendance_displays WHERE display_public_id = result) INTO v_exists;
        EXIT WHEN NOT v_exists;
    END LOOP;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- RPC 3.1: Get or Create permanent Display link for a Gym
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
        v_public_id := public.fn_generate_display_public_id();
        INSERT INTO public.attendance_displays (gym_id, display_public_id, device_name, is_verified)
        VALUES (p_gym_id, v_public_id, 'Primary Display TV', FALSE);
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'display_public_id', v_public_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC 3.2: Handshake when Display Link Opens
CREATE OR REPLACE FUNCTION public.register_display_link(
    p_public_id TEXT,
    p_fingerprint TEXT,
    p_device_name TEXT,
    p_secret TEXT
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

    -- If already verified, and secret + fingerprint match, trust automatically
    IF v_display.is_verified AND v_display.is_enabled AND v_display.device_secret = p_secret AND v_display.browser_fingerprint = p_fingerprint THEN
        UPDATE public.attendance_displays
        SET last_seen = now()
        WHERE id = v_display.id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'status', 'VERIFIED',
            'gym_name', v_gym_name,
            'device_secret', v_display.device_secret
        );
    END IF;

    -- Otherwise, we require verification. Generate secure token for QR
    v_token := encode(digest(p_public_id || gen_random_uuid()::text || now()::text, 'sha256'), 'hex');
    v_expires_at := now() + INTERVAL '5 minutes';

    -- Invalidate old unused tokens for this display
    UPDATE public.attendance_display_tokens
    SET is_used = TRUE
    WHERE display_id = v_display.id;

    -- Store new verification token
    INSERT INTO public.attendance_display_tokens (display_id, token, expires_at)
    VALUES (v_display.id, v_token, v_expires_at);

    -- Update display record fingerprint/status
    UPDATE public.attendance_displays
    SET browser_fingerprint = p_fingerprint,
        device_name = p_device_name,
        is_verified = FALSE,
        device_secret = NULL
    WHERE id = v_display.id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'status', 'WAITING_FOR_VERIFICATION',
        'gym_name', v_gym_name,
        'verification_token', v_token
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC 3.3: Verify Token from Owner/Staff App
CREATE OR REPLACE FUNCTION public.verify_display_token(
    p_token TEXT,
    p_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_token_record RECORD;
    v_display RECORD;
    v_gym_association RECORD;
    v_staff_record RECORD;
    v_new_secret TEXT;
    v_user_name TEXT;
BEGIN
    -- Find token
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

    -- Find display
    SELECT * INTO v_display FROM public.attendance_displays WHERE id = v_token_record.display_id;
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Associated display not found');
    END IF;

    -- Fetch user role association
    SELECT * INTO v_gym_association 
    FROM public.user_gym_associations 
    WHERE user_id = p_user_id AND gym_id = v_display.gym_id;

    IF v_gym_association IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Unauthorized: User is not associated with this Gym');
    END IF;

    -- Check Staff Permissions if role is staff
    IF v_gym_association.role = 'staff' THEN
        SELECT * INTO v_staff_record FROM public.staff WHERE user_id = p_user_id AND gym_id = v_display.gym_id;
        -- Staff must be Manager or Receptionist to manage attendance/displays
        IF v_staff_record IS NULL OR v_staff_record.role NOT IN ('Manager', 'Receptionist') THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Unauthorized: Staff lack Attendance Management permissions');
        END IF;
        v_user_name := v_staff_record.name;
    ELSE
        -- Owner
        SELECT full_name INTO v_user_name FROM public.profiles WHERE id = p_user_id;
    END IF;

    -- Generate secure device secret
    v_new_secret := encode(digest(v_display.id::text || gen_random_uuid()::text || now()::text, 'sha256'), 'hex');

    -- Update display to VERIFIED
    UPDATE public.attendance_displays
    SET is_verified = TRUE,
        device_secret = v_new_secret,
        verified_by = p_user_id,
        verified_at = now(),
        last_seen = now()
    WHERE id = v_display.id;

    -- Mark token as used
    UPDATE public.attendance_display_tokens
    SET is_used = TRUE
    WHERE id = v_token_record.id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'display_name', v_display.device_name,
        'verified_by_name', v_user_name
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC 3.4: Send Heartbeat
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
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Unauthorized or unverified session');
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

-- RPC 3.5: Rename, Disable, Reverify, or Remove Device
CREATE OR REPLACE FUNCTION public.manage_display_device(
    p_display_id UUID,
    p_action TEXT,
    p_name TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
BEGIN
    -- Rename
    IF p_action = 'RENAME' THEN
        UPDATE public.attendance_displays
        SET device_name = COALESCE(p_name, device_name)
        WHERE id = p_display_id;
    -- Disable / Enable toggle
    ELSIF p_action = 'TOGGLE_STATUS' THEN
        UPDATE public.attendance_displays
        SET is_enabled = NOT is_enabled,
            device_secret = CASE WHEN is_enabled THEN NULL ELSE device_secret END -- Clear secret if disabling to force reconnect
        WHERE id = p_display_id;
    -- Reverify (revoke trust, force verification)
    ELSIF p_action = 'REVERIFY' THEN
        UPDATE public.attendance_displays
        SET is_verified = FALSE,
            device_secret = NULL,
            verified_at = NULL,
            verified_by = NULL
        WHERE id = p_display_id;
    -- Remove / Delete
    ELSIF p_action = 'REMOVE' THEN
        DELETE FROM public.attendance_displays
        WHERE id = p_display_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
