-- =========================================================================
-- UPDATE FREE TRIAL PLAN STAFF LIMIT TO 5 STAFF MEMBERS
-- Run this script in Supabase SQL Editor
-- =========================================================================

-- 1. Update max_staff to 5 for free_trial plan in subscription_plans table
UPDATE public.subscription_plans 
SET max_staff = 5 
WHERE id = 'free_trial';

-- 2. Upsert plan configurations to ensure free_trial has max_staff = 5
INSERT INTO public.subscription_plans (id, name, price, max_members, max_staff, max_gyms) VALUES
('free_trial', 'Free Trial (Pro)', 0.00, 10, 5, 1),
('starter', 'Starter', 699.00, 100, 3, 1),
('pro', 'Pro', 1499.00, 1000, 10, 1),
('business', 'Business', 2999.00, 2000, 50, 3)
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name,
    price = EXCLUDED.price,
    max_members = EXCLUDED.max_members,
    max_staff = EXCLUDED.max_staff,
    max_gyms = EXCLUDED.max_gyms;
