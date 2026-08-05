-- Upgrade subscription plans schema and seed updated plan configurations
ALTER TABLE public.subscription_plans ADD COLUMN IF NOT EXISTS max_gyms INT DEFAULT 1;

-- Seed / Update subscription plans
INSERT INTO public.subscription_plans (id, name, price, max_members, max_staff, max_gyms) VALUES
('free_trial', 'Free Trial (Pro)', 0.00, 10, 1, 1),
('starter', 'Starter', 699.00, 100, 3, 1),
('pro', 'Pro', 1499.00, 1000, 10, 1),
('business', 'Business', 2999.00, 2000, 50, 3)
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name,
    price = EXCLUDED.price,
    max_members = EXCLUDED.max_members,
    max_staff = EXCLUDED.max_staff,
    max_gyms = EXCLUDED.max_gyms;

-- Update trigger function for handle_new_gym_subscription to start with a 14-day trial
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
            now() + interval '14 days',
            now(),
            now() + interval '14 days'
        )
        ON CONFLICT (gym_id) DO NOTHING;
        
        -- Log history
        INSERT INTO public.subscription_history (gym_id, old_plan_id, new_plan_id, action, changed_by, notes)
        VALUES (
            NEW.gym_id,
            NULL,
            'free_trial',
            'create',
            NEW.user_id,
            'Auto trial started on registration'
        )
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
