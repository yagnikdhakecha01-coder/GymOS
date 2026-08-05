-- =========================================================================
-- FIX GYM SUBSCRIPTION FOREIGN KEY TRIGGER ERROR: fix_gyms_subscription_fk_trigger.sql
-- Copy and paste this script in your Supabase SQL Editor and click RUN.
-- =========================================================================

-- 1. Drop old conflicting triggers
DROP TRIGGER IF EXISTS trg_sync_gym_dates ON public.gyms;
DROP TRIGGER IF EXISTS trg_sync_gym_dates_before ON public.gyms;
DROP TRIGGER IF EXISTS trg_sync_gym_dates_after ON public.gyms;
DROP TRIGGER IF EXISTS on_gym_sync ON public.gyms;

-- 2. BEFORE TRIGGER: Pre-calculate default dates on NEW gym BEFORE insert (FK safe)
CREATE OR REPLACE FUNCTION public.handle_gym_dates_before()
RETURNS TRIGGER AS $$
BEGIN
    -- Determine effective target expiry date (Default 3 months)
    IF NEW.expiry_date IS NULL AND NEW.trial_end_date IS NULL THEN
        NEW.trial_end_date := NOW() + INTERVAL '3 months';
        NEW.expiry_date := NOW() + INTERVAL '3 months';
    ELSIF NEW.expiry_date IS NULL THEN
        NEW.expiry_date := NEW.trial_end_date;
    ELSIF NEW.trial_end_date IS NULL THEN
        NEW.trial_end_date := NEW.expiry_date;
    END IF;

    -- Default status and plan if missing
    IF NEW.status IS NULL THEN
        NEW.status := 'trial';
    END IF;
    IF NEW.plan IS NULL THEN
        NEW.plan := 'free_trial';
    END IF;

    -- Auto check expiration status
    IF NEW.expiry_date <= NOW() THEN
        NEW.status := 'expired';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_sync_gym_dates_before
BEFORE INSERT OR UPDATE ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.handle_gym_dates_before();


-- 3. AFTER TRIGGER: Safely sync subscriptions table AFTER gym row exists in database
CREATE OR REPLACE FUNCTION public.handle_gym_subscriptions_after()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_id UUID;
    v_target_date TIMESTAMPTZ;
BEGIN
    -- Avoid infinite recursion
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    v_target_date := COALESCE(NEW.expiry_date, NEW.trial_end_date, NOW() + INTERVAL '3 months');

    -- Safely get owner_id if association exists
    SELECT user_id INTO v_owner_id
    FROM public.user_gym_associations
    WHERE gym_id = NEW.id AND role = 'owner'
    LIMIT 1;

    -- Insert or update subscriptions record AFTER gym is in table
    INSERT INTO public.subscriptions (
        gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date, updated_at
    )
    VALUES (
        NEW.id,
        v_owner_id,
        COALESCE(NEW.plan, 'free_trial'),
        COALESCE(NEW.status, 'trial'),
        COALESCE(NEW.created_at, NOW()),
        v_target_date,
        COALESCE(NEW.created_at, NOW()),
        v_target_date,
        NOW()
    )
    ON CONFLICT (gym_id) DO UPDATE SET 
        owner_id = EXCLUDED.owner_id,
        plan_id = EXCLUDED.plan_id,
        status = EXCLUDED.status,
        trial_end = EXCLUDED.trial_end,
        end_date = EXCLUDED.end_date,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_sync_gym_dates_after
AFTER INSERT OR UPDATE ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.handle_gym_subscriptions_after();
