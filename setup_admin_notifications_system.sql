-- =========================================================================
-- DATABASE MIGRATION: setup_admin_notifications_system.sql
-- Copy and run this script in your Supabase SQL Editor
-- Sets up tables, RLS policies, and automated PostgreSQL triggers for Super Admin notifications.
-- =========================================================================

-- 1. ADMIN NOTIFICATIONS TABLE (Events received by Super Admin)
CREATE TABLE IF NOT EXISTS public.admin_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'system', -- 'gym_registered', 'subscription_change', 'support_ticket', 'payment_received', 'trial_expiry', 'system'
    priority TEXT NOT NULL DEFAULT 'normal', -- 'normal', 'high', 'urgent'
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. BROADCAST NOTIFICATIONS TABLE (Announcements sent by Super Admin to Gym Owners)
CREATE TABLE IF NOT EXISTS public.broadcast_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL DEFAULT 'push', -- 'push', 'banner', 'popup', 'maintenance', 'offer'
    target TEXT NOT NULL DEFAULT 'all_gyms', -- 'all_gyms', 'trial_gyms', 'active_gyms', 'selected_gyms'
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS & Policies
ALTER TABLE public.admin_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.broadcast_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_notifications_all ON public.admin_notifications;
CREATE POLICY admin_notifications_all ON public.admin_notifications FOR ALL USING (true);

DROP POLICY IF EXISTS broadcast_notifications_all ON public.broadcast_notifications;
CREATE POLICY broadcast_notifications_all ON public.broadcast_notifications FOR ALL USING (true);

GRANT ALL ON public.admin_notifications TO anon, authenticated, service_role;
GRANT ALL ON public.broadcast_notifications TO anon, authenticated, service_role;

-- Insert initial welcome/system notification if table empty
INSERT INTO public.admin_notifications (title, message, category, priority, metadata)
SELECT 'Super Admin System Initialized', 'Database notifications system is now active. Real-time platform alerts will appear here.', 'system', 'normal', '{"event": "system_init"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.admin_notifications LIMIT 1);


-- =========================================================================
-- AUTOMATED TRIGGERS FOR PLATFORM EVENTS
-- =========================================================================

-- A. TRIGGER: New Gym Registration Notification
CREATE OR REPLACE FUNCTION public.fn_notify_admin_new_gym()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.admin_notifications (title, message, category, priority, metadata)
    VALUES (
        'New Gym Registered',
        'Gym "' || COALESCE(NEW.name, 'New Gym') || '" has registered on the platform.',
        'gym_registered',
        'high',
        jsonb_build_object(
            'gym_id', NEW.id,
            'gym_name', NEW.name,
            'city', NEW.city,
            'phone', NEW.phone_number,
            'email', NEW.email
        )
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_admin_new_gym ON public.gyms;
CREATE TRIGGER trg_notify_admin_new_gym
AFTER INSERT ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.fn_notify_admin_new_gym();


-- B. TRIGGER: Subscription Plan Change Notification
CREATE OR REPLACE FUNCTION public.fn_notify_admin_subscription_change()
RETURNS TRIGGER AS $$
DECLARE
    v_gym_name TEXT := 'Gym';
BEGIN
    SELECT name INTO v_gym_name FROM public.gyms WHERE id = NEW.gym_id LIMIT 1;
    
    INSERT INTO public.admin_notifications (title, message, category, priority, metadata)
    VALUES (
        'Subscription Updated',
        'Gym "' || COALESCE(v_gym_name, 'Gym') || '" plan changed to "' || COALESCE(NEW.plan_id, 'Free Trial') || '" (' || COALESCE(NEW.status, 'active') || ').',
        'subscription_change',
        'normal',
        jsonb_build_object(
            'gym_id', NEW.gym_id,
            'plan_id', NEW.plan_id,
            'status', NEW.status
        )
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_admin_subscription ON public.subscriptions;
CREATE TRIGGER trg_notify_admin_subscription
AFTER INSERT OR UPDATE OF plan_id, status ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.fn_notify_admin_subscription_change();


-- C. TRIGGER: New Support Ticket Raised Notification
CREATE OR REPLACE FUNCTION public.fn_notify_admin_support_ticket()
RETURNS TRIGGER AS $$
DECLARE
    v_gym_name TEXT := 'Gym';
BEGIN
    IF NEW.gym_id IS NOT NULL THEN
        SELECT name INTO v_gym_name FROM public.gyms WHERE id = NEW.gym_id LIMIT 1;
    END IF;

    INSERT INTO public.admin_notifications (title, message, category, priority, metadata)
    VALUES (
        'New Support Ticket Raised',
        'Ticket #' || SUBSTRING(NEW.id::text FROM 1 FOR 8) || ': "' || COALESCE(NEW.subject, 'Support Request') || '" (' || COALESCE(v_gym_name, 'Member/Staff') || ').',
        'support_ticket',
        CASE WHEN NEW.priority IN ('high', 'urgent') THEN 'urgent' ELSE 'high' END,
        jsonb_build_object(
            'ticket_id', NEW.id,
            'subject', NEW.subject,
            'priority', NEW.priority
        )
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Safely attach trigger to support_tickets table if exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'support_tickets') THEN
        DROP TRIGGER IF EXISTS trg_notify_admin_support_ticket ON public.support_tickets;
        CREATE TRIGGER trg_notify_admin_support_ticket
        AFTER INSERT ON public.support_tickets
        FOR EACH ROW EXECUTE FUNCTION public.fn_notify_admin_support_ticket();
    END IF;
END $$;


-- D. TRIGGER: Payment Received Notification
CREATE OR REPLACE FUNCTION public.fn_notify_admin_payment_received()
RETURNS TRIGGER AS $$
DECLARE
    v_gym_name TEXT := 'Gym';
BEGIN
    IF NEW.gym_id IS NOT NULL THEN
        SELECT name INTO v_gym_name FROM public.gyms WHERE id = NEW.gym_id LIMIT 1;
    END IF;

    INSERT INTO public.admin_notifications (title, message, category, priority, metadata)
    VALUES (
        'Payment Received',
        'Payment of ₹' || TRIM(TO_CHAR(COALESCE(NEW.amount, 0), '99,99,999')) || ' recorded for ' || COALESCE(v_gym_name, 'Platform') || '.',
        'payment_received',
        'normal',
        jsonb_build_object(
            'transaction_id', NEW.id,
            'amount', NEW.amount,
            'category', NEW.category
        )
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Safely attach trigger to transactions table if exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'transactions') THEN
        DROP TRIGGER IF EXISTS trg_notify_admin_payment ON public.transactions;
        CREATE TRIGGER trg_notify_admin_payment
        AFTER INSERT ON public.transactions
        FOR EACH ROW EXECUTE FUNCTION public.fn_notify_admin_payment_received();
    END IF;
END $$;
