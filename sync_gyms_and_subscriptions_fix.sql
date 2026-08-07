-- ====================================================================
-- GYMOS - SYNC GYMS TABLE WITH SUBSCRIPTIONS TABLE
-- Run this script in your Supabase SQL Editor to sync plan, status & dates
-- ====================================================================

-- 1. Update gyms table based on active subscriptions
UPDATE public.gyms g
SET 
    plan = COALESCE(s.plan_id, g.plan, 'free_trial'),
    status = COALESCE(s.status, g.status, 'trial'),
    expiry_date = COALESCE(s.end_date, g.expiry_date),
    trial_end_date = COALESCE(s.trial_end, g.trial_end_date)
FROM public.subscriptions s
WHERE g.id = s.gym_id;

-- 2. Automatically sync status for paid active plans
UPDATE public.subscriptions
SET status = 'active'
WHERE plan_id IN ('starter', 'pro', 'business') 
  AND status = 'trial';

UPDATE public.gyms
SET status = 'active'
WHERE plan IN ('starter', 'pro', 'business') 
  AND status = 'trial';
