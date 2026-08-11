-- =========================================================================
-- DATABASE PATCH: setup_custom_branding.sql
-- Run this script in your Supabase SQL Editor to support whitelabel custom branding.
-- =========================================================================

-- 1. ADD COLUMN TO GYMS TABLE (if not exists)
ALTER TABLE public.gyms ADD COLUMN IF NOT EXISTS custom_branding_allowed BOOLEAN DEFAULT FALSE;

-- 2. CREATE FUNCTION: check_custom_branding_status
CREATE OR REPLACE FUNCTION public.check_custom_branding_status(p_gym_id UUID)
RETURNS TABLE (
    is_allowed BOOLEAN,
    gym_name TEXT,
    gym_logo TEXT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_plan_id TEXT;
    v_sub_status TEXT;
    v_admin_allowed BOOLEAN := FALSE;
    v_gym_name TEXT;
    v_gym_logo TEXT;
BEGIN
    -- Fetch gym name, logo, and custom branding allowed flag
    SELECT name, logo_url, COALESCE(custom_branding_allowed, FALSE)
    INTO v_gym_name, v_gym_logo, v_admin_allowed
    FROM public.gyms
    WHERE id = p_gym_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, ''::TEXT, ''::TEXT;
        RETURN;
    END IF;

    -- Fetch active subscription plan
    SELECT plan_id, status INTO v_plan_id, v_sub_status
    FROM public.subscriptions
    WHERE gym_id = p_gym_id;

    -- Custom branding is allowed if:
    -- 1. Admin manually enabled it (v_admin_allowed is TRUE) OR
    -- 2. Subscription status is active/trial AND plan_id is 'pro' or 'business'
    IF v_admin_allowed OR 
       (v_sub_status IN ('active', 'trial') AND v_plan_id IN ('pro', 'business')) THEN
        RETURN QUERY SELECT TRUE, v_gym_name, COALESCE(v_gym_logo, '');
    ELSE
        RETURN QUERY SELECT FALSE, v_gym_name, COALESCE(v_gym_logo, '');
    END IF;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.check_custom_branding_status(UUID) TO anon, authenticated, service_role;
