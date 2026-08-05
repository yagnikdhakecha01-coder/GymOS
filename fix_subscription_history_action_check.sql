-- =========================================================================
-- FIX SUBSCRIPTION HISTORY CHECK CONSTRAINT ERROR: fix_subscription_history_action_check.sql
-- Copy and paste this script in your Supabase SQL Editor and click RUN.
-- =========================================================================

-- 1. Drop existing restrictive CHECK constraint on subscription_history.action
ALTER TABLE public.subscription_history DROP CONSTRAINT IF EXISTS subscription_history_action_check;

-- 2. Add flexible CHECK constraint allowing 'create', 'Trial Activated', etc.
ALTER TABLE public.subscription_history 
ADD CONSTRAINT subscription_history_action_check 
CHECK (action IN (
    'create', 
    'Trial Activated', 
    'Plan Purchased', 
    'Plan Renewed', 
    'Plan Upgraded', 
    'Plan Downgraded', 
    'Payment Failed', 
    'Subscription Cancelled',
    'trial_extended',
    'expiry_updated'
));

-- 3. Update handle_new_gym_subscription function to be safe and use 'Trial Activated'
CREATE OR REPLACE FUNCTION public.handle_new_gym_subscription()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role = 'owner' THEN
        INSERT INTO public.subscriptions (gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date)
        VALUES (
            NEW.gym_id,
            NEW.user_id,
            'free_trial',
            'trial',
            now(),
            now() + interval '3 months',
            now(),
            now() + interval '3 months'
        )
        ON CONFLICT (gym_id) DO NOTHING;
        
        -- Log history using allowed action value
        INSERT INTO public.subscription_history (gym_id, old_plan_id, new_plan_id, action, changed_by, notes)
        VALUES (
            NEW.gym_id,
            NULL,
            'free_trial',
            'Trial Activated',
            NEW.user_id,
            'Auto 3-month trial started on registration'
        )
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
