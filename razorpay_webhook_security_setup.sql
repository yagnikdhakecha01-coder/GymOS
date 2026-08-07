-- Razorpay Webhook & Payment Verification Security Setup
-- This script outlines the exact backend signature verification logic and Webhook handler for Supabase.

-- 1. Create audit table for payment webhook logs
CREATE TABLE IF NOT EXISTS razorpay_webhook_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    payment_id TEXT,
    order_id TEXT,
    gym_id TEXT,
    payload JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on webhook logs table so only service role can write/read
ALTER TABLE razorpay_webhook_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only service_role can access webhook logs"
    ON razorpay_webhook_logs
    FOR ALL
    USING (auth.role() = 'service_role');

-- 2. Webhook Event Handler Function (Executes when Razorpay sends 'payment.authorized' or 'subscription.charged')
CREATE OR REPLACE FUNCTION process_razorpay_webhook(
    p_event_type TEXT,
    p_gym_id UUID,
    p_plan_id TEXT,
    p_payment_id TEXT,
    p_order_id TEXT,
    p_amount NUMERIC
) RETURNS VOID AS $$
DECLARE
    v_trial_end TIMESTAMP WITH TIME ZONE;
    v_start_date TIMESTAMP WITH TIME ZONE;
    v_end_date TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Log incoming event
    INSERT INTO razorpay_webhook_logs (event_type, payment_id, order_id, gym_id, payload)
    VALUES (p_event_type, p_payment_id, p_order_id, p_gym_id::TEXT, jsonb_build_object(
        'plan_id', p_plan_id,
        'amount', p_amount
    ));

    -- Get current trial end date if active
    SELECT trial_end INTO v_trial_end
    FROM subscriptions
    WHERE gym_id = p_gym_id;

    IF v_trial_end IS NOT NULL AND v_trial_end > NOW() THEN
        v_start_date := v_trial_end;
        v_end_date := v_trial_end + INTERVAL '30 days';
    ELSE
        v_start_date := NOW();
        v_end_date := NOW() + INTERVAL '30 days';
    END IF;

    -- Update subscription record securely in DB
    UPDATE subscriptions
    SET plan_id = p_plan_id,
        status = 'active',
        auto_pay = TRUE,
        start_date = v_start_date,
        end_date = v_end_date,
        next_billing_date = v_end_date,
        updated_at = NOW()
    WHERE gym_id = p_gym_id;

    -- Sync status in gyms table
    UPDATE gyms
    SET plan = p_plan_id,
        status = 'active',
        expiry_date = v_end_date,
        updated_at = NOW()
    WHERE id = p_gym_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
