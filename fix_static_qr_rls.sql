-- ====================================================
-- GYMOS - FIX STATIC QR RLS BYPASS
-- ====================================================

CREATE OR REPLACE FUNCTION public.get_display_static_qr(
    p_display_public_id TEXT,
    p_secret TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
    v_token TEXT;
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
    
    -- Retrieve static token
    SELECT static_qr_token INTO v_token
    FROM public.attendance_settings
    WHERE gym_id = v_display.gym_id;
    
    RETURN jsonb_build_object(
        'success', TRUE,
        'static_qr_token', v_token
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_display_static_qr TO anon, authenticated, service_role;
