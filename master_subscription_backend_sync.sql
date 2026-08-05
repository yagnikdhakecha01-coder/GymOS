-- =========================================================================
-- MASTER SUBSCRIPTION BACKEND SYNC & AUTOMATION MIGRATION (FK SAFE)
-- Copy and paste this script in your Supabase SQL Editor and click RUN
-- =========================================================================

-- 0. MAKE OWNER_ID NULLABLE IN SUBSCRIPTIONS TO PREVENT FK VIOLATIONS ON TEST GYMS
ALTER TABLE public.subscriptions ALTER COLUMN owner_id DROP NOT NULL;

-- DROP ALL OLD CONFLICTING TRIGGERS TO PREVENT LOOPS & FK VIOLATIONS
DROP TRIGGER IF EXISTS on_subscription_sync ON public.subscriptions;
DROP TRIGGER IF EXISTS on_gym_sync ON public.gyms;
DROP TRIGGER IF EXISTS trg_sync_gym_dates ON public.gyms;
DROP TRIGGER IF EXISTS trg_sync_gym_dates_before ON public.gyms;
DROP TRIGGER IF EXISTS trg_sync_gym_dates_after ON public.gyms;

-- 1. BEFORE TRIGGER: Calculate dates BEFORE gym insertion
CREATE OR REPLACE FUNCTION public.handle_gym_dates_before()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.expiry_date IS NULL AND NEW.trial_end_date IS NULL THEN
        NEW.trial_end_date := NOW() + INTERVAL '3 months';
        NEW.expiry_date := NOW() + INTERVAL '3 months';
    ELSIF NEW.expiry_date IS NULL THEN
        NEW.expiry_date := NEW.trial_end_date;
    ELSIF NEW.trial_end_date IS NULL THEN
        NEW.trial_end_date := NEW.expiry_date;
    END IF;

    IF NEW.status IS NULL THEN
        NEW.status := 'trial';
    END IF;
    IF NEW.plan IS NULL THEN
        NEW.plan := 'free_trial';
    END IF;

    IF NEW.expiry_date <= NOW() THEN
        NEW.status := 'expired';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_sync_gym_dates_before
BEFORE INSERT OR UPDATE ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.handle_gym_dates_before();

-- 2. AFTER TRIGGER: Insert/Update subscriptions table AFTER gym exists in database
CREATE OR REPLACE FUNCTION public.handle_gym_subscriptions_after()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_id UUID;
    v_target_date TIMESTAMPTZ;
BEGIN
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    v_target_date := COALESCE(NEW.expiry_date, NEW.trial_end_date, NOW() + INTERVAL '3 months');

    SELECT user_id INTO v_owner_id
    FROM public.user_gym_associations
    WHERE gym_id = NEW.id AND role = 'owner'
    LIMIT 1;

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


-- 3. BACKEND RPC FUNCTION: Get Gym Subscription Info & Days Left directly from PostgreSQL
CREATE OR REPLACE FUNCTION public.get_gym_subscription_info(p_gym_id UUID)
RETURNS TABLE (
    gym_id UUID,
    plan TEXT,
    status TEXT,
    expiry_date TIMESTAMPTZ,
    days_left INT,
    is_expired BOOLEAN,
    is_locked BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        g.id AS gym_id,
        COALESCE(g.plan, 'free_trial') AS plan,
        COALESCE(g.status, 'trial') AS status,
        COALESCE(g.expiry_date, g.trial_end_date) AS expiry_date,
        GREATEST(0, EXTRACT(DAY FROM (COALESCE(g.expiry_date, g.trial_end_date) - NOW()))::INT) AS days_left,
        (COALESCE(g.expiry_date, g.trial_end_date) <= NOW() OR g.status = 'expired') AS is_expired,
        COALESCE(g.is_locked, FALSE) AS is_locked
    FROM public.gyms g
    WHERE g.id = p_gym_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. ONE-TIME BACKFILL: Synchronize all existing gyms right now
UPDATE public.gyms
SET 
    expiry_date = COALESCE(expiry_date, trial_end_date, NOW() + INTERVAL '3 months'),
    trial_end_date = COALESCE(expiry_date, trial_end_date, NOW() + INTERVAL '3 months');
