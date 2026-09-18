-- =========================================================================
-- DATABASE MIGRATION: update_role_based_notifications.sql
-- Role-based Notification Routing & Privacy Separation
-- =========================================================================

-- 1. Ensure target_role and user_id exist on public.notifications
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE,
    user_id UUID,
    target_role TEXT DEFAULT 'All', -- 'Owner', 'Staff', 'Member', 'All'
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT DEFAULT 'general', -- 'member_join', 'expiry', 'request', 'announcement', 'holiday'
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS target_role TEXT DEFAULT 'All';
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'general';
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT FALSE;

-- Ensure RLS is enabled and accessible
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notifications_isolation_policy ON public.notifications;
CREATE POLICY notifications_isolation_policy ON public.notifications FOR ALL USING (true) WITH CHECK (true);
GRANT ALL ON public.notifications TO anon, authenticated, service_role;

-- 2. Clean up existing untargeted owner alerts
UPDATE public.notifications
SET target_role = 'Owner'
WHERE (target_role IS NULL OR target_role = 'All')
  AND (
    title ILIKE '%Leave Request%' 
    OR title ILIKE '%Advance%' 
    OR title ILIKE '%Membership ending%' 
    OR title ILIKE '%Membership expiring%'
    OR title ILIKE '%Member Registered%'
    OR title ILIKE '%New Member Joined%'
  );

-- 3. TRIGGER: When a new member registers/joins -> Notify Gym Owner ONLY
CREATE OR REPLACE FUNCTION public.fn_on_member_joined_notify()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.notifications (
        gym_id,
        user_id,
        target_role,
        title,
        body,
        type,
        is_read
    ) VALUES (
        NEW.gym_id,
        NULL,
        'Owner',
        '🎉 New Member Joined',
        NEW.name || ' has registered as a member in your gym.',
        'member_join',
        FALSE
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_member_joined_notify ON public.members;
CREATE TRIGGER trg_on_member_joined_notify
AFTER INSERT ON public.members
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_member_joined_notify();

-- 4. RPC: check_membership_expiring_alerts (Dual Notification: 1 to Owner, 1 to Member)
CREATE OR REPLACE FUNCTION public.check_membership_expiring_alerts(p_gym_id UUID)
RETURNS VOID AS $$
DECLARE
    r_member RECORD;
    v_expiry_date DATE;
    v_days_diff INT;
    v_when_str TEXT;
BEGIN
    FOR r_member IN
        SELECT 
            m.id AS member_id,
            m.user_id AS auth_user_id,
            m.name AS member_name,
            m.extra_fields->>'expiryDate' AS expiry_str
        FROM public.members m
        WHERE m.gym_id = p_gym_id
          AND m.extra_fields->>'expiryDate' IS NOT NULL
          AND m.status IN ('Active', 'Trial')
    LOOP
        BEGIN
            v_expiry_date := (substring(r_member.expiry_str from '^\d{4}-\d{2}-\d{2}'))::DATE;
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;
        END;

        IF v_expiry_date IS NULL THEN
            CONTINUE;
        END IF;

        v_days_diff := v_expiry_date - CURRENT_DATE;

        -- Only trigger on specific countdown milestones: 15 days, 7 days, 3 days, 1 day, 0 days
        IF v_days_diff IN (0, 1, 3, 7, 15) THEN
            IF v_days_diff = 0 THEN
                v_when_str := 'today (' || to_char(v_expiry_date, 'DD Mon') || ')';
            ELSIF v_days_diff = 1 THEN
                v_when_str := 'tomorrow (' || to_char(v_expiry_date, 'DD Mon') || ')';
            ELSE
                v_when_str := 'in ' || v_days_diff || ' days (' || to_char(v_expiry_date, 'DD Mon') || ')';
            END IF;

            -- A. Notify Owner (if not already sent today for this member & interval)
            IF NOT EXISTS (
                SELECT 1 FROM public.notifications
                WHERE gym_id = p_gym_id
                  AND target_role = 'Owner'
                  AND type = 'expiry'
                  AND title LIKE '%' || r_member.member_name || '%'
                  AND created_at::DATE = CURRENT_DATE
            ) THEN
                INSERT INTO public.notifications (
                    gym_id,
                    user_id,
                    target_role,
                    title,
                    body,
                    type,
                    is_read
                ) VALUES (
                    p_gym_id,
                    NULL,
                    'Owner',
                    '⏳ Plan Expiring: ' || r_member.member_name,
                    r_member.member_name || '''s gym membership expires ' || v_when_str || '. Contact them to renew.',
                    'expiry',
                    FALSE
                );
            END IF;

            -- B. Notify THAT SPECIFIC MEMBER only (if not already sent today)
            IF NOT EXISTS (
                SELECT 1 FROM public.notifications
                WHERE gym_id = p_gym_id
                  AND (user_id = r_member.member_id OR user_id = r_member.auth_user_id)
                  AND target_role = 'Member'
                  AND type = 'expiry'
                  AND created_at::DATE = CURRENT_DATE
            ) THEN
                INSERT INTO public.notifications (
                    gym_id,
                    user_id,
                    target_role,
                    title,
                    body,
                    type,
                    is_read
                ) VALUES (
                    p_gym_id,
                    r_member.member_id,
                    'Member',
                    '⏳ Your Gym Plan is Expiring Soon',
                    'Hi ' || r_member.member_name || ', your gym membership will expire ' || v_when_str || '. Please renew to keep your workouts uninterrupted!',
                    'expiry',
                    FALSE
                );
            END IF;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.check_membership_expiring_alerts(UUID) TO anon, authenticated, service_role;

-- 5. TRIGGER FOR STAFF LEAVE REQUESTS:
-- Staff request created -> Target: 'Owner'
-- Owner decision (Approved/Rejected) -> Target: 'Staff' (user_id = staff_id)
CREATE OR REPLACE FUNCTION public.fn_on_leave_request_notify()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.notifications (
            gym_id,
            user_id,
            target_role,
            title,
            body,
            type,
            is_read
        ) VALUES (
            NEW.gym_id,
            NULL,
            'Owner',
            '📋 New Staff Leave Request',
            COALESCE(s_name, 'Staff Member') || ' has requested leave from ' || to_char(NEW.start_date, 'DD Mon') || ' to ' || to_char(NEW.end_date, 'DD Mon'),
            'request',
            FALSE
        );
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> NEW.status AND NEW.status IN ('Approved', 'Rejected') THEN
        INSERT INTO public.notifications (
            gym_id,
            user_id,
            target_role,
            title,
            body,
            type,
            is_read
        ) VALUES (
            NEW.gym_id,
            NEW.staff_id,
            'Staff',
            'Leave Request ' || NEW.status,
            'Your leave request from ' || to_char(NEW.start_date, 'DD Mon') || ' to ' || to_char(NEW.end_date, 'DD Mon') || ' has been ' || NEW.status,
            'request',
            FALSE
        );
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_leave_request_notify ON public.leave_requests;
CREATE TRIGGER trg_on_leave_request_notify
AFTER INSERT OR UPDATE ON public.leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_leave_request_notify();

-- 6. TRIGGER FOR STAFF ADVANCE REQUESTS:
-- Staff advance created -> Target: 'Owner'
-- Owner decision (Approved/Rejected/Given) -> Target: 'Staff' (user_id = staff_id)
CREATE OR REPLACE FUNCTION public.fn_on_advance_request_notify()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.notifications (
            gym_id,
            user_id,
            target_role,
            title,
            body,
            type,
            is_read
        ) VALUES (
            NEW.gym_id,
            NULL,
            'Owner',
            '💰 New Advance Salary Request',
            COALESCE(s_name, 'Staff Member') || ' has requested an advance of ₹' || COALESCE(NEW.advance_amount, 0),
            'request',
            FALSE
        );
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> NEW.status AND NEW.status IN ('Approved', 'Rejected', 'Given') THEN
        INSERT INTO public.notifications (
            gym_id,
            user_id,
            target_role,
            title,
            body,
            type,
            is_read
        ) VALUES (
            NEW.gym_id,
            NEW.staff_id,
            'Staff',
            'Advance Request ' || NEW.status,
            'Your advance salary request of ₹' || COALESCE(NEW.advance_amount, 0) || ' has been ' || NEW.status,
            'request',
            FALSE
        );
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_advance_request_notify ON public.salary_advance_ledger;
CREATE TRIGGER trg_on_advance_request_notify
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_advance_request_notify();
