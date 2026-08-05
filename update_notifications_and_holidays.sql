-- ====================================================================
-- GYMOS: PUSH NOTIFICATIONS, OWNER BROADCAST & HOLIDAY MANAGEMENT SQL
-- ====================================================================

-- 1. HOLIDAYS TABLE ENHANCEMENTS
CREATE TABLE IF NOT EXISTS public.holidays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    holiday_date DATE,
    date DATE,
    title TEXT,
    name TEXT,
    description TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure all column variants exist on existing table
ALTER TABLE public.holidays ADD COLUMN IF NOT EXISTS holiday_date DATE;
ALTER TABLE public.holidays ADD COLUMN IF NOT EXISTS date DATE;
ALTER TABLE public.holidays ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE public.holidays ADD COLUMN IF NOT EXISTS name TEXT;

-- Backfill values between column variants
UPDATE public.holidays SET holiday_date = date WHERE holiday_date IS NULL AND date IS NOT NULL;
UPDATE public.holidays SET date = holiday_date WHERE date IS NULL AND holiday_date IS NOT NULL;
UPDATE public.holidays SET title = name WHERE title IS NULL AND name IS NOT NULL;
UPDATE public.holidays SET name = title WHERE name IS NULL AND title IS NOT NULL;

ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS holidays_isolation_policy ON public.holidays;
CREATE POLICY holidays_isolation_policy ON public.holidays FOR ALL USING (true) WITH CHECK (true);
GRANT ALL ON public.holidays TO anon, authenticated, service_role;


-- 2. NOTIFICATIONS TABLE ENHANCEMENTS
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE,
    user_id UUID,
    target_role TEXT DEFAULT 'All', -- 'Owner', 'Staff', 'Member', 'All'
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT DEFAULT 'general', -- 'announcement', 'request', 'expiry', 'holiday'
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notifications_isolation_policy ON public.notifications;
CREATE POLICY notifications_isolation_policy ON public.notifications FOR ALL USING (true) WITH CHECK (true);
GRANT ALL ON public.notifications TO anon, authenticated, service_role;


-- 3. TRIGGER FUNCTION: ON HOLIDAY DECLARED AUTO NOTIFY & AUTO MARK ATTENDANCE
CREATE OR REPLACE FUNCTION public.fn_on_holiday_declared()
RETURNS TRIGGER AS $$
DECLARE
    r_staff RECORD;
    r_member RECORD;
    v_hdate DATE;
    v_htitle TEXT;
BEGIN
    v_hdate := COALESCE(NEW.holiday_date, NEW.date, CURRENT_DATE);
    v_htitle := COALESCE(NEW.title, NEW.name, 'Gym Holiday');

    -- Keep column variants synced
    NEW.holiday_date := v_hdate;
    NEW.date := v_hdate;
    NEW.title := v_htitle;
    NEW.name := v_htitle;

    -- Insert notification for the holiday
    INSERT INTO public.notifications (
        gym_id,
        target_role,
        title,
        body,
        type
    ) VALUES (
        NEW.gym_id,
        'All',
        '🎉 Holiday Declared: ' || v_htitle,
        'Gym will remain closed on ' || to_char(v_hdate, 'DD Mon YYYY') || '. Reason: ' || COALESCE(NEW.description, v_htitle),
        'holiday'
    );

    -- Auto mark attendance logs for all Staff members on this holiday date
    FOR r_staff IN SELECT id, user_id FROM public.staff WHERE gym_id = NEW.gym_id AND status = 'Active' LOOP
        INSERT INTO public.attendance_logs (
            gym_id,
            user_id,
            user_type,
            check_in,
            check_out,
            status
        ) VALUES (
            NEW.gym_id,
            COALESCE(r_staff.user_id, r_staff.id),
            'Staff',
            v_hdate::TIMESTAMPTZ,
            v_hdate::TIMESTAMPTZ,
            'Holiday'
        )
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- Auto mark attendance logs for all Active Members on this holiday date
    FOR r_member IN SELECT id FROM public.members WHERE gym_id = NEW.gym_id AND status = 'Active' LOOP
        INSERT INTO public.attendance_logs (
            gym_id,
            user_id,
            user_type,
            check_in,
            check_out,
            status
        ) VALUES (
            NEW.gym_id,
            r_member.id,
            'Member',
            v_hdate::TIMESTAMPTZ,
            v_hdate::TIMESTAMPTZ,
            'Holiday'
        )
        ON CONFLICT DO NOTHING;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_holiday_declared ON public.holidays;
CREATE TRIGGER trg_on_holiday_declared
BEFORE INSERT ON public.holidays
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_holiday_declared();


-- 4. TRIGGER FUNCTIONS: LEAVE & ADVANCE REQUEST NOTIFICATIONS
-- Staff submits Leave -> Notify Owner. Owner approves/rejects -> Notify Staff.
CREATE OR REPLACE FUNCTION public.fn_on_leave_request_notify()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.notifications (
            gym_id,
            target_role,
            title,
            body,
            type
        ) VALUES (
            NEW.gym_id,
            'Owner',
            '📋 New Leave Request',
            COALESCE(s_name, 'Staff Member') || ' has requested leave from ' || to_char(NEW.start_date, 'DD Mon') || ' to ' || to_char(NEW.end_date, 'DD Mon'),
            'request'
        );
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> NEW.status AND NEW.status IN ('Approved', 'Rejected') THEN
        INSERT INTO public.notifications (
            gym_id,
            user_id,
            target_role,
            title,
            body,
            type
        ) VALUES (
            NEW.gym_id,
            NEW.staff_id,
            'Staff',
            'Leave Request ' || NEW.status,
            'Your leave request from ' || to_char(NEW.start_date, 'DD Mon') || ' to ' || to_char(NEW.end_date, 'DD Mon') || ' has been ' || NEW.status,
            'request'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_leave_request_notify ON public.leave_requests;
CREATE TRIGGER trg_on_leave_request_notify
AFTER INSERT OR UPDATE ON public.leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_leave_request_notify();


-- Staff submits Advance Salary Request -> Notify Owner. Owner approves/rejects -> Notify Staff.
CREATE OR REPLACE FUNCTION public.fn_on_advance_request_notify()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.notifications (
            gym_id,
            target_role,
            title,
            body,
            type
        ) VALUES (
            NEW.gym_id,
            'Owner',
            '💰 New Advance Salary Request',
            COALESCE(s_name, 'Staff Member') || ' has requested an advance of ₹' || COALESCE(NEW.advance_amount, 0),
            'request'
        );
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> NEW.status AND NEW.status IN ('Approved', 'Rejected', 'Given') THEN
        INSERT INTO public.notifications (
            gym_id,
            user_id,
            target_role,
            title,
            body,
            type
        ) VALUES (
            NEW.gym_id,
            NEW.staff_id,
            'Staff',
            'Advance Request ' || NEW.status,
            'Your advance salary request of ₹' || COALESCE(NEW.advance_amount, 0) || ' has been ' || NEW.status,
            'request'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_advance_request_notify ON public.salary_advance_ledger;
CREATE TRIGGER trg_on_advance_request_notify
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_advance_request_notify();


-- 5. RPC FUNCTION: CHECK MEMBERSHIP EXPIRING IN 15 DAYS AND NOTIFY MEMBERS
CREATE OR REPLACE FUNCTION public.check_membership_expiring_15_days(p_gym_id UUID)
RETURNS VOID AS $$
DECLARE
    r_exp RECORD;
BEGIN
    FOR r_exp IN 
        SELECT 
            mm.member_id,
            m.name AS member_name,
            mm.end_date,
            mp.name AS plan_name
        FROM public.member_memberships mm
        JOIN public.members m ON mm.member_id = m.id
        LEFT JOIN public.membership_plans mp ON mm.plan_id = mp.id
        WHERE mm.gym_id = p_gym_id
          AND mm.status = 'Active'
          AND mm.end_date = (CURRENT_DATE + INTERVAL '15 days')
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.notifications 
            WHERE user_id = r_exp.member_id 
              AND type = 'expiry'
              AND created_at::DATE = CURRENT_DATE
        ) THEN
            INSERT INTO public.notifications (
                gym_id,
                user_id,
                target_role,
                title,
                body,
                type
            ) VALUES (
                p_gym_id,
                r_exp.member_id,
                'Member',
                '⏳ Membership Expiring Soon',
                'Hi ' || r_exp.member_name || ', your ' || COALESCE(r_exp.plan_name, 'Gym') || ' membership will expire in 15 days on ' || to_char(r_exp.end_date, 'DD Mon YYYY') || '. Please renew to stay fit!',
                'expiry'
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.check_membership_expiring_15_days(UUID) TO anon, authenticated, service_role;
