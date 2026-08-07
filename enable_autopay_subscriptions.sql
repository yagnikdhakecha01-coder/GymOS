-- ====================================================================
-- GYMOS - AUTOPAY & RECURRING SUBSCRIPTIONS SUPPORT
-- Run this script in your Supabase SQL Editor
-- ====================================================================

-- 1. Add AutoPay & Recurring Billing Columns to subscriptions table
ALTER TABLE public.subscriptions 
ADD COLUMN IF NOT EXISTS auto_pay BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS next_billing_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS razorpay_subscription_id TEXT;

-- 2. Update existing active/trial subscriptions next_billing_date
UPDATE public.subscriptions
SET next_billing_date = COALESCE(end_date, trial_end, NOW() + INTERVAL '30 days'),
    auto_pay = true
WHERE next_billing_date IS NULL;
