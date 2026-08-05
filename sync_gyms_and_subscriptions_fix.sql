-- =========================================================================
-- MIGRATION: sync_gyms_and_subscriptions_fix.sql
-- Run this script in Supabase SQL Editor to sync all gyms with subscriptions table
-- =========================================================================

-- 1. Sync Trigger from subscriptions to gyms
CREATE OR REPLACE FUNCTION public.sync_subscription_to_gyms()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.gyms 
    SET 
        plan = NEW.plan_id,
        status = NEW.status,
        expiry_date = NEW.end_date,
        trial_end_date = NEW.trial_end
    WHERE id = NEW.gym_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_subscription_sync ON public.subscriptions;
CREATE TRIGGER on_subscription_sync
AFTER INSERT OR UPDATE ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.sync_subscription_to_gyms();


-- 2. Sync Trigger from gyms to subscriptions
CREATE OR REPLACE FUNCTION public.sync_gyms_to_subscriptions()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.subscriptions (gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date)
    VALUES (
        NEW.id,
        COALESCE(
            (SELECT user_id FROM public.user_gym_associations WHERE gym_id = NEW.id AND role = 'owner' LIMIT 1),
            NEW.id
        ),
        COALESCE(NEW.plan, 'free_trial'),
        COALESCE(NEW.status, 'trial'),
        COALESCE(NEW.created_at, now()),
        COALESCE(NEW.trial_end_date, NEW.expiry_date, now() + interval '3 months'),
        COALESCE(NEW.created_at, now()),
        COALESCE(NEW.expiry_date, NEW.trial_end_date, now() + interval '3 months')
    )
    ON CONFLICT (gym_id) DO UPDATE 
    SET 
        plan_id = EXCLUDED.plan_id,
        status = EXCLUDED.status,
        end_date = EXCLUDED.end_date,
        trial_end = EXCLUDED.trial_end;
        
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_gym_sync ON public.gyms;
CREATE TRIGGER on_gym_sync
AFTER INSERT OR UPDATE OF plan, status, expiry_date, trial_end_date ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.sync_gyms_to_subscriptions();


-- 3. Backfill missing subscriptions for all existing gyms right now
INSERT INTO public.subscriptions (gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date)
SELECT 
    g.id, 
    COALESCE(
        (SELECT user_id FROM public.user_gym_associations WHERE gym_id = g.id AND role = 'owner' LIMIT 1),
        g.id
    ),
    COALESCE(g.plan, 'free_trial'),
    COALESCE(g.status, 'trial'),
    COALESCE(g.created_at, now()),
    COALESCE(g.trial_end_date, g.expiry_date, now() + interval '3 months'),
    COALESCE(g.created_at, now()),
    COALESCE(g.expiry_date, g.trial_end_date, now() + interval '3 months')
FROM public.gyms g
ON CONFLICT (gym_id) DO UPDATE SET 
    trial_end = EXCLUDED.trial_end,
    end_date = EXCLUDED.end_date,
    status = EXCLUDED.status,
    plan_id = EXCLUDED.plan_id;


-- 4. Enable RLS and Permissive Read Policy for Subscriptions
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscriptions_isolation_policy ON public.subscriptions;
CREATE POLICY subscriptions_isolation_policy ON public.subscriptions
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS subscriptions_anon_read ON public.subscriptions;
CREATE POLICY subscriptions_anon_read ON public.subscriptions
    FOR SELECT TO anon, authenticated
    USING (true);
