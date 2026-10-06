-- ==============================================================================
-- Migration: Setup Web QR Code Login & Persistent Session Tracking
-- Description: Enables WhatsApp Web-style QR code authentication for GymOS Web
-- ==============================================================================

-- 1. Create web_login_sessions table
CREATE TABLE IF NOT EXISTS public.web_login_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token TEXT UNIQUE NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
    device_name TEXT,
    ip_address TEXT,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    gym_id UUID REFERENCES public.gyms(id) ON DELETE SET NULL,
    role TEXT CHECK (role IN ('owner', 'staff', 'member', 'receptionist', 'trainer')),
    auth_payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '10 minutes'),
    approved_at TIMESTAMPTZ
);

-- Index for instant lookup by session token
CREATE INDEX IF NOT EXISTS idx_web_login_sessions_token ON public.web_login_sessions(token);
CREATE INDEX IF NOT EXISTS idx_web_login_sessions_status_expiry ON public.web_login_sessions(status, expires_at);

-- 2. Enable Row Level Security (RLS)
ALTER TABLE public.web_login_sessions ENABLE ROW LEVEL SECURITY;

-- Allow public / anon to read their own pending session by token
DROP POLICY IF EXISTS "Public read session by token" ON public.web_login_sessions;
CREATE POLICY "Public read session by token"
ON public.web_login_sessions
FOR SELECT
USING (true);

-- Allow web clients to create new pending session
DROP POLICY IF EXISTS "Public insert pending session" ON public.web_login_sessions;
CREATE POLICY "Public insert pending session"
ON public.web_login_sessions
FOR INSERT
WITH CHECK (status = 'pending');

-- Allow authenticated users to update session (to approve/reject)
DROP POLICY IF EXISTS "Auth users can update session" ON public.web_login_sessions;
CREATE POLICY "Auth users can update session"
ON public.web_login_sessions
FOR UPDATE
USING (auth.uid() IS NOT NULL);

-- 3. Add to Supabase Realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'web_login_sessions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.web_login_sessions;
    END IF;
END $$;

-- 4. RPC to create a fresh web QR session
CREATE OR REPLACE FUNCTION public.create_web_qr_session(
    p_device_name TEXT DEFAULT 'Browser Web Session',
    p_ip_address TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token TEXT;
    v_expires_at TIMESTAMPTZ;
BEGIN
    v_token := encode(gen_random_bytes(24), 'hex');
    v_expires_at := now() + INTERVAL '10 minutes';

    INSERT INTO public.web_login_sessions (
        token,
        status,
        device_name,
        ip_address,
        expires_at
    ) VALUES (
        v_token,
        'pending',
        p_device_name,
        p_ip_address,
        v_expires_at
    );

    RETURN jsonb_build_object(
        'success', true,
        'token', v_token,
        'expires_at', v_expires_at
    );
END;
$$;

-- 5. RPC to approve web QR login from mobile app
CREATE OR REPLACE FUNCTION public.approve_web_qr_login(
    p_token TEXT,
    p_scanner_device_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_email TEXT;
    v_role TEXT;
    v_gym_id UUID;
    v_session_record RECORD;
    v_profile RECORD;
    v_gym RECORD;
    v_payload JSONB;
BEGIN
    -- 1. Verify caller is authenticated
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Authentication required');
    END IF;

    -- 2. Verify token exists and is valid
    SELECT * INTO v_session_record
    FROM public.web_login_sessions
    WHERE token = p_token;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid QR code session');
    END IF;

    IF v_session_record.status <> 'pending' THEN
        RETURN jsonb_build_object('success', false, 'error', 'QR code has already been used or cancelled');
    END IF;

    IF v_session_record.expires_at < now() THEN
        UPDATE public.web_login_sessions SET status = 'expired' WHERE id = v_session_record.id;
        RETURN jsonb_build_object('success', false, 'error', 'QR code session expired');
    END IF;

    -- 3. Fetch user email
    SELECT email INTO v_email FROM auth.users WHERE id = v_user_id;

    -- 4. Detect role and primary gym_id
    -- First check if user is Gym Owner
    SELECT id, gym_name INTO v_gym FROM public.gyms WHERE owner_id = v_user_id LIMIT 1;
    IF FOUND THEN
        v_role := 'owner';
        v_gym_id := v_gym.id;
    ELSE
        -- Check if user is Staff
        SELECT gym_id, role INTO v_profile FROM public.staff WHERE auth_user_id = v_user_id LIMIT 1;
        IF FOUND THEN
            v_role := COALESCE(v_profile.role, 'staff');
            v_gym_id := v_profile.gym_id;
        ELSE
            -- Check if user is Member
            SELECT gym_id INTO v_profile FROM public.members WHERE auth_user_id = v_user_id LIMIT 1;
            IF FOUND THEN
                v_role := 'member';
                v_gym_id := v_profile.gym_id;
            ELSE
                v_role := 'owner'; -- Fallback to profile
            END IF;
        END IF;
    END IF;

    -- 5. Construct secure payload
    v_payload := jsonb_build_object(
        'user_id', v_user_id,
        'email', v_email,
        'role', v_role,
        'gym_id', v_gym_id,
        'approved_by_device', p_scanner_device_name,
        'approved_at', now()
    );

    -- 6. Update session record to APPROVED
    UPDATE public.web_login_sessions
    SET status = 'approved',
        user_id = v_user_id,
        gym_id = v_gym_id,
        role = v_role,
        auth_payload = v_payload,
        approved_at = now()
    WHERE id = v_session_record.id;

    RETURN jsonb_build_object(
        'success', true,
        'role', v_role,
        'gym_id', v_gym_id,
        'message', 'Login approved successfully'
    );
END;
$$;
