-- ====================================================
-- GYMOS - COMPLETE FIX FOR DYNAMIC QR DISPLAY
-- Run this ENTIRE script in Supabase SQL Editor
-- ====================================================

-- Ensure pgcrypto extension is enabled (needed for gen_random_bytes)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ====================================================
-- 1. FIX: get_display_static_qr (handles BOTH static & dynamic QR)
-- ====================================================
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
    -- Verify display device is active, verified, and matches the secret
    SELECT * INTO v_display 
    FROM public.attendance_displays 
    WHERE display_public_id = p_display_public_id;
    
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display not found.');
    END IF;
    
    IF NOT v_display.is_verified OR NOT v_display.is_enabled THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display is not verified or is disabled.');
    END IF;
    
    IF v_display.device_secret <> p_secret THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid device credentials.');
    END IF;

    -- Fetch attendance settings for the gym
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_display.gym_id;

    IF v_settings IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'No attendance settings found for this gym. Please configure attendance settings first.');
    END IF;

    -- If mode is Dynamic QR, generate dynamic token securely
    IF v_settings.method IN ('Dynamic QR', 'Dynamic QR + WiFi', 'QR Only', 'QR + WiFi') THEN
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

GRANT EXECUTE ON FUNCTION public.get_display_static_qr TO anon, authenticated, service_role;

-- ====================================================
-- 2. FIX: send_display_heartbeat (returns method + validity for real-time sync)
-- ====================================================
CREATE OR REPLACE FUNCTION public.send_display_heartbeat(
    p_public_id TEXT,
    p_secret TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
    v_settings RECORD;
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

    -- Fetch attendance settings for the gym to return current method & validity
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_display.gym_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'is_enabled', v_display.is_enabled,
        'method', COALESCE(v_settings.method, 'Static QR'),
        'qr_validity_seconds', COALESCE(v_settings.qr_validity_seconds, 30)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.send_display_heartbeat TO anon, authenticated, service_role;

-- ====================================================
-- 3. ENSURE: attendance_qr_tokens table has correct schema
-- This adds missing columns if the table was created from an older migration
-- ====================================================
DO $$
BEGIN
    -- Add display_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'attendance_qr_tokens' 
        AND column_name = 'display_id'
    ) THEN
        ALTER TABLE public.attendance_qr_tokens ADD COLUMN display_id UUID REFERENCES public.attendance_displays(id) ON DELETE CASCADE;
    END IF;

    -- Add is_used column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'attendance_qr_tokens' 
        AND column_name = 'is_used'
    ) THEN
        ALTER TABLE public.attendance_qr_tokens ADD COLUMN is_used BOOLEAN DEFAULT FALSE NOT NULL;
    END IF;

    -- Add gym_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'attendance_qr_tokens' 
        AND column_name = 'gym_id'
    ) THEN
        ALTER TABLE public.attendance_qr_tokens ADD COLUMN gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Ensure RLS policies allow the SECURITY DEFINER functions to work
ALTER TABLE public.attendance_qr_tokens ENABLE ROW LEVEL SECURITY;

-- Grant access
GRANT ALL ON TABLE public.attendance_qr_tokens TO anon, authenticated, service_role;
