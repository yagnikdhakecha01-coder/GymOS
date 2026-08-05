-- =========================================================================
-- DATABASE MIGRATION: sync_gyms_and_subscriptions.sql
-- Run this script in your Supabase SQL Editor to link and sync gyms and subscriptions
-- =========================================================================

-- 1. Trigger to sync subscription changes back to gyms table
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


-- 2. Trigger to sync gym changes back to subscriptions table
CREATE OR REPLACE FUNCTION public.sync_gyms_to_subscriptions()
RETURNS TRIGGER AS $$
BEGIN
    -- Ensure subscription record exists
    INSERT INTO public.subscriptions (gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date)
    VALUES (
        NEW.id,
        (SELECT user_id FROM public.user_gym_associations WHERE gym_id = NEW.id AND role = 'owner' LIMIT 1),
        NEW.plan,
        NEW.status,
        now(),
        NEW.trial_end_date,
        now(),
        NEW.expiry_date
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
AFTER UPDATE OF plan, status, expiry_date, trial_end_date ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.sync_gyms_to_subscriptions();
