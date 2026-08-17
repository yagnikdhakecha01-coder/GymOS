-- =========================================================================
-- MIGRATION: sync_super_admin_free_trial.sql
-- Copy and run this script in your Supabase SQL Editor.
-- Dynamically connects Super Admin Free Trial settings (platform_settings) 
-- to newly registered gyms and subscription records.
-- =========================================================================

-- 1. Ensure platform_settings table exists
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

GRANT ALL ON public.platform_settings TO anon, authenticated, service_role;

-- 2. Insert or update default free trial setting (Default: 30 days)
INSERT INTO public.platform_settings (key, value, updated_at)
VALUES (
    'default_free_trial', 
    '{"duration_value": 30, "duration_unit": "days", "enabled": true}'::jsonb,
    NOW()
)
ON CONFLICT (key) DO NOTHING;


-- 3. TRIGGER 1: handle_new_gym_trial_setting (BEFORE INSERT ON gyms)
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
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    v_owner_id := COALESCE(
        NEW.owner_id,
        (SELECT user_id FROM public.user_gym_associations WHERE gym_id = NEW.id AND role = 'owner' LIMIT 1),
        auth.uid()
    );

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

    -- Read platform_settings for default free trial
    SELECT value INTO v_setting_json 
    FROM public.platform_settings 
    WHERE key = 'default_free_trial';

    IF v_setting_json IS NOT NULL THEN
        v_duration_val := COALESCE((v_setting_json->>'duration_value')::INT, 30);
        v_duration_unit := COALESCE(v_setting_json->>'duration_unit', 'days');
        v_trial_enabled := COALESCE((v_setting_json->>'enabled')::BOOLEAN, TRUE);
    END IF;

    IF v_has_existing_gym OR NOT v_trial_enabled THEN
        v_calc_expiry := NOW();
        NEW.status := 'expired';
        NEW.expiry_date := v_calc_expiry;
        NEW.trial_end_date := v_calc_expiry;
    ELSE
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

DROP TRIGGER IF EXISTS trg_new_gym_trial ON public.gyms;
CREATE TRIGGER trg_new_gym_trial
BEFORE INSERT ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.handle_new_gym_trial_setting();


-- 4. TRIGGER 2: handle_new_gym_subscription (AFTER INSERT ON user_gym_associations)
CREATE OR REPLACE FUNCTION public.handle_new_gym_subscription()
RETURNS TRIGGER AS $$
DECLARE
    v_setting_json JSONB;
    v_duration_val INT := 30;
    v_duration_unit TEXT := 'days';
    v_trial_enabled BOOLEAN := TRUE;
    v_calc_expiry TIMESTAMPTZ;
BEGIN
    IF NEW.role = 'owner' THEN
        -- Read platform settings for default free trial
        SELECT value INTO v_setting_json 
        FROM public.platform_settings 
        WHERE key = 'default_free_trial';

        IF v_setting_json IS NOT NULL THEN
            v_duration_val := COALESCE((v_setting_json->>'duration_value')::INT, 30);
            v_duration_unit := COALESCE(v_setting_json->>'duration_unit', 'days');
            v_trial_enabled := COALESCE((v_setting_json->>'enabled')::BOOLEAN, TRUE);
        END IF;

        IF NOT v_trial_enabled THEN
            v_calc_expiry := NOW();
        ELSIF v_duration_unit = 'months' THEN
            v_calc_expiry := NOW() + (v_duration_val || ' months')::INTERVAL;
        ELSE
            v_calc_expiry := NOW() + (v_duration_val || ' days')::INTERVAL;
        END IF;

        INSERT INTO public.subscriptions (gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date)
        VALUES (
            NEW.gym_id,
            NEW.user_id,
            'free_trial',
            CASE WHEN v_trial_enabled THEN 'trial' ELSE 'expired' END,
            NOW(),
            v_calc_expiry,
            NOW(),
            v_calc_expiry
        )
        ON CONFLICT (gym_id) DO UPDATE SET
            trial_end = EXCLUDED.trial_end,
            end_date = EXCLUDED.end_date,
            status = EXCLUDED.status;

        -- Synchronize gyms table expiry and status
        UPDATE public.gyms
        SET expiry_date = v_calc_expiry,
            trial_end_date = v_calc_expiry,
            status = CASE WHEN v_trial_enabled THEN 'trial' ELSE 'expired' END
        WHERE id = NEW.gym_id;

        -- Ensure subscription_history table constraint does not block execution
        BEGIN
            ALTER TABLE public.subscription_history DROP CONSTRAINT IF EXISTS subscription_history_action_check;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        INSERT INTO public.subscription_history (gym_id, old_plan_id, new_plan_id, action, changed_by, notes)
        VALUES (
            NEW.gym_id,
            NULL,
            'free_trial',
            'Trial Activated',
            NEW.user_id,
            'Auto trial started on registration (' || v_duration_val || ' ' || v_duration_unit || ')'
        )
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
