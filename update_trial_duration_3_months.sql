-- =========================================================================
-- DATABASE MIGRATION: update_trial_duration_3_months.sql
-- Run this script in your Supabase SQL Editor to update new trials to 3 months
-- =========================================================================

-- Ensure check constraint allows all actions
ALTER TABLE public.subscription_history DROP CONSTRAINT IF EXISTS subscription_history_action_check;

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
        
        -- Log history with valid action name
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
