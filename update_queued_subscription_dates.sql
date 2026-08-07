-- SQL Migration Script for GymOS Subscription Date Calculation & Queuing
-- This script ensures that when a paid subscription is activated during an active Free Trial:
-- 1. The paid plan start_date is set to the trial_end date.
-- 2. The paid plan end_date is set to (trial_end + 30 days).
-- 3. All dates follow proper timestamp standards.

CREATE OR REPLACE FUNCTION handle_subscription_queue()
RETURNS TRIGGER AS $$
BEGIN
    -- If free trial is active and a paid plan is selected
    IF OLD.trial_end IS NOT NULL AND OLD.trial_end > NOW() AND NEW.plan_id != 'free_trial' THEN
        -- Set paid plan start date to free trial end date
        NEW.start_date := OLD.trial_end;
        -- Set paid plan end date to 30 days after free trial ends
        NEW.end_date := OLD.trial_end + INTERVAL '30 days';
        NEW.next_billing_date := NEW.end_date;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to subscriptions table on update
DROP TRIGGER IF EXISTS trigger_queue_subscription ON subscriptions;
CREATE TRIGGER trigger_queue_subscription
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION handle_subscription_queue();
