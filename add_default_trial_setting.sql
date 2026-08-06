-- =========================================================================
-- DEFAULT FREE TRIAL CONFIGURATION & MULTI-GYM PREVENTION MIGRATION
-- Copy and paste this script in your Supabase SQL Editor and click RUN
-- =========================================================================

-- 1. CREATE PLATFORM SETTINGS TABLE IF NOT EXISTS
CREATE TABLE IF NOT EXISTS public.platform_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS & Policies
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_settings_select_policy ON public.platform_settings;
CREATE POLICY platform_settings_select_policy ON public.platform_settings FOR SELECT USING (true);

DROP POLICY IF EXISTS platform_settings_all_policy ON public.platform_settings;
CREATE POLICY platform_settings_all_policy ON public.platform_settings FOR ALL USING (true);

-- Insert Default Free Trial setting (Default: 3 months)
INSERT INTO public.platform_settings (key, value, updated_at)
VALUES (
    'default_free_trial', 
    '{"duration_value": 3, "duration_unit": "months", "enabled": true}'::jsonb,
    NOW()
)
ON CONFLICT (key) DO NOTHING;


-- 2. TRIGGER FUNCTION: AUTO-ASSIGN FREE TRIAL OR DENY FOR SECOND GYM
CREATE OR REPLACE FUNCTION public.handle_new_gym_trial_setting()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_id UUID;
    v_has_existing_gym BOOLEAN := FALSE;
    v_setting_json JSONB;
    v_duration_val INT := 30;
    v_duration_unit TEXT := 'days';
    v_trial_enabled BOOLEAN := TRUE;
    v_calc_expiry TIMESTAMPTZ;
BEGIN
    -- Prevent trigger recursion
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- Get creator owner ID from record or auth.uid()
    v_owner_id := COALESCE(
        NEW.owner_id,
        (SELECT user_id FROM public.user_gym_associations WHERE gym_id = NEW.id AND role = 'owner' LIMIT 1),
        auth.uid()
    );

    -- Check if this owner ALREADY owns another gym
    IF v_owner_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 
            FROM public.user_gym_associations uga
            JOIN public.gyms g ON g.id = uga.gym_id
            WHERE uga.user_id = v_owner_id 
              AND uga.role = 'owner'
              AND g.id != NEW.id
        ) INTO v_has_existing_gym;
    END IF;

    -- Read platform settings for default free trial
    SELECT value INTO v_setting_json 
    FROM public.platform_settings 
    WHERE key = 'default_free_trial';

    IF v_setting_json IS NOT NULL THEN
        v_duration_val := COALESCE((v_setting_json->>'duration_value')::INT, 30);
        v_duration_unit := COALESCE(v_setting_json->>'duration_unit', 'days');
        v_trial_enabled := COALESCE((v_setting_json->>'enabled')::BOOLEAN, TRUE);
    END IF;

    -- RULE: Second Gym OR Paid Plan Gym OR Trial Disabled -> 0 Trial Days (Expired)
    IF v_has_existing_gym OR NOT v_trial_enabled THEN
        v_calc_expiry := NOW();
        NEW.status := 'expired';
        NEW.expiry_date := v_calc_expiry;
        NEW.trial_end_date := v_calc_expiry;
    ELSE
        -- FIRST GYM GETS CONFIGURABLE FREE TRIAL DURATION FROM SUPER ADMIN SETTINGS
        IF v_duration_unit = 'months' THEN
            v_calc_expiry := NOW() + (v_duration_val || ' months')::INTERVAL;
        ELSE
            v_calc_expiry := NOW() + (v_duration_val || ' days')::INTERVAL;
        END IF;

        NEW.expiry_date := v_calc_expiry;
        NEW.trial_end_date := v_calc_expiry;
        NEW.status := 'trial';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to gyms table BEFORE INSERT
DROP TRIGGER IF EXISTS trg_new_gym_trial ON public.gyms;
CREATE TRIGGER trg_new_gym_trial
BEFORE INSERT ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.handle_new_gym_trial_setting();

GRANT ALL ON public.platform_settings TO anon, authenticated, service_role;
