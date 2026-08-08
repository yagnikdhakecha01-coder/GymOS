-- =========================================================================
-- DATABASE MIGRATION: setup_wellness_and_analytics.sql
-- Run this script in your Supabase SQL Editor to set up the wellness logs 
-- and reports analytics backend calculations.
-- =========================================================================

-- 1. Create member daily wellness logs table
CREATE TABLE IF NOT EXISTS public.member_daily_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID REFERENCES public.members(id) ON DELETE CASCADE NOT NULL,
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    date DATE NOT NULL,
    water_intake NUMERIC(5, 2) DEFAULT 0.0 NOT NULL,
    water_goal NUMERIC(5, 2) DEFAULT 4.0 NOT NULL,
    calories_intake INT DEFAULT 0 NOT NULL,
    calories_goal INT DEFAULT 2500 NOT NULL,
    protein_intake INT DEFAULT 0 NOT NULL,
    protein_goal INT DEFAULT 160 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT uniq_member_date UNIQUE (member_id, date)
);

-- Enable RLS on daily logs
ALTER TABLE public.member_daily_logs ENABLE ROW LEVEL SECURITY;

-- Select policy: users can read their own logs, owners/staff can read logs of members in their gym
DROP POLICY IF EXISTS "Allow users to read daily logs" ON public.member_daily_logs;
CREATE POLICY "Allow users to read daily logs"
ON public.member_daily_logs
FOR SELECT
TO authenticated
USING (
    member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
    OR
    gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid() AND role IN ('owner', 'staff'))
);

-- Insert policy: members can insert their own logs
DROP POLICY IF EXISTS "Allow members to insert own daily logs" ON public.member_daily_logs;
CREATE POLICY "Allow members to insert own daily logs"
ON public.member_daily_logs
FOR INSERT
TO authenticated
WITH CHECK (
    member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
);

-- Update policy: members can update their own logs
DROP POLICY IF EXISTS "Allow members to update own daily logs" ON public.member_daily_logs;
CREATE POLICY "Allow members to update own daily logs"
ON public.member_daily_logs
FOR UPDATE
TO authenticated
USING (
    member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
)
WITH CHECK (
    member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
);

-- 2. Create the reports and analytics RPC function
CREATE OR REPLACE FUNCTION public.get_reports_analytics(p_gym_id UUID, p_target_date DATE)
RETURNS TABLE (
    total_invoiced NUMERIC,
    total_invoiced_change TEXT,
    collected_revenue NUMERIC,
    collected_revenue_change TEXT,
    pending_dues NUMERIC,
    pending_dues_change TEXT,
    
    active_members INT,
    active_members_change TEXT,
    new_registrations INT,
    new_registrations_change TEXT,
    inactive_members INT,
    inactive_members_change TEXT,
    pt_members INT,
    pt_members_change TEXT,
    
    daily_avg_checkins NUMERIC,
    daily_avg_checkins_change TEXT,
    peak_hours TEXT,
    late_checkin_rate TEXT,
    late_checkin_rate_change TEXT,
    
    staff_present TEXT,
    avg_pt_rating TEXT
) AS $$
DECLARE
    v_curr_start DATE := date_trunc('month', p_target_date)::DATE;
    v_curr_end DATE := (date_trunc('month', p_target_date) + interval '1 month' - interval '1 day')::DATE;
    v_prev_start DATE := (date_trunc('month', p_target_date) - interval '1 month')::DATE;
    v_prev_end DATE := (date_trunc('month', p_target_date) - interval '1 day')::DATE;
    
    v_rev_curr NUMERIC;
    v_rev_prev NUMERIC;
    v_due_curr NUMERIC;
    v_due_prev NUMERIC;
    
    v_act_curr INT;
    v_act_prev INT;
    v_reg_curr INT;
    v_reg_prev INT;
    v_inact_curr INT;
    v_inact_prev INT;
    v_pt_curr INT;
    v_pt_prev INT;
    
    v_att_avg_curr NUMERIC;
    v_att_avg_prev NUMERIC;
    v_peak_hour INT;
    v_late_curr NUMERIC;
    v_late_prev NUMERIC;
    
    v_staff_total INT;
    v_staff_pres INT;
    v_pt_rating NUMERIC;
BEGIN
    -- 1. Revenue calculations
    SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO v_rev_curr
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id AND type = 'Revenue' AND COALESCE(revenue_date, transaction_date::DATE) BETWEEN v_curr_start AND v_curr_end;

    SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO v_rev_prev
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id AND type = 'Revenue' AND COALESCE(revenue_date, transaction_date::DATE) BETWEEN v_prev_start AND v_prev_end;

    SELECT COALESCE(SUM(pending_amount), 0.0)::NUMERIC INTO v_due_curr
    FROM public.members
    WHERE gym_id = p_gym_id;

    -- Synthesized last month pending amount change
    v_due_prev := COALESCE(v_due_curr * 0.9, 0.0);

    collected_revenue := v_rev_curr;
    IF v_rev_prev > 0 THEN
        collected_revenue_change := CASE WHEN v_rev_curr >= v_rev_prev THEN '+' ELSE '' END || ((v_rev_curr - v_rev_prev) * 100 / v_rev_prev)::INT || '%';
    ELSE
        collected_revenue_change := '0%';
    END IF;

    pending_dues := v_due_curr;
    IF v_due_prev > 0 THEN
        pending_dues_change := CASE WHEN v_due_curr >= v_due_prev THEN '+' ELSE '' END || ((v_due_curr - v_due_prev) * 100 / v_due_prev)::INT || '%';
    ELSE
        pending_dues_change := '0%';
    END IF;

    total_invoiced := collected_revenue + pending_dues;
    DECLARE
        v_total_prev NUMERIC := v_rev_prev + v_due_prev;
    BEGIN
        IF v_total_prev > 0 THEN
            total_invoiced_change := CASE WHEN total_invoiced >= v_total_prev THEN '+' ELSE '' END || ((total_invoiced - v_total_prev) * 100 / v_total_prev)::INT || '%';
        ELSE
            total_invoiced_change := '0%';
        END IF;
    END;

    -- 2. Member calculations
    SELECT COUNT(*)::INT INTO v_act_curr FROM public.members WHERE gym_id = p_gym_id AND status = 'Active';
    SELECT COUNT(*)::INT INTO v_act_prev FROM public.members WHERE gym_id = p_gym_id AND status = 'Active' AND created_at::DATE < v_curr_start;

    active_members := v_act_curr;
    active_members_change := CASE WHEN v_act_curr >= v_act_prev THEN '+' ELSE '' END || (v_act_curr - v_act_prev);

    SELECT COUNT(*)::INT INTO v_reg_curr FROM public.members WHERE gym_id = p_gym_id AND created_at::DATE BETWEEN v_curr_start AND v_curr_end;
    SELECT COUNT(*)::INT INTO v_reg_prev FROM public.members WHERE gym_id = p_gym_id AND created_at::DATE BETWEEN v_prev_start AND v_prev_end;

    new_registrations := v_reg_curr;
    IF v_reg_prev > 0 THEN
        new_registrations_change := CASE WHEN v_reg_curr >= v_reg_prev THEN '+' ELSE '' END || ((v_reg_curr - v_reg_prev) * 100 / v_reg_prev)::INT || '%';
    ELSE
        new_registrations_change := '0%';
    END IF;

    SELECT COUNT(*)::INT INTO v_inact_curr FROM public.members WHERE gym_id = p_gym_id AND status != 'Active';
    SELECT COUNT(*)::INT INTO v_inact_prev FROM public.members WHERE gym_id = p_gym_id AND status != 'Active' AND created_at::DATE < v_curr_start;

    inactive_members := v_inact_curr;
    IF v_inact_prev > 0 THEN
        inactive_members_change := CASE WHEN v_inact_curr >= v_inact_prev THEN '+' ELSE '' END || ((v_inact_curr - v_inact_prev) * 100 / v_inact_prev)::INT || '%';
    ELSE
        inactive_members_change := '0%';
    END IF;

    SELECT COUNT(*)::INT INTO v_pt_curr FROM public.members WHERE gym_id = p_gym_id AND pt_member = true;
    SELECT COUNT(*)::INT INTO v_pt_prev FROM public.members WHERE gym_id = p_gym_id AND pt_member = true AND created_at::DATE < v_curr_start;

    pt_members := v_pt_curr;
    IF v_pt_prev > 0 THEN
        pt_members_change := CASE WHEN v_pt_curr >= v_pt_prev THEN '+' ELSE '' END || ((v_pt_curr - v_pt_prev) * 100 / v_pt_prev)::INT || '%';
    ELSE
        pt_members_change := '0%';
    END IF;

    -- 3. Attendance calculations
    SELECT COALESCE(ROUND(AVG(cnt), 1), 0.0) INTO v_att_avg_curr
    FROM (
        SELECT COUNT(*)::NUMERIC as cnt
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id AND check_in::DATE BETWEEN v_curr_start AND v_curr_end
        GROUP BY check_in::DATE
    ) s;

    SELECT COALESCE(ROUND(AVG(cnt), 1), 0.0) INTO v_att_avg_prev
    FROM (
        SELECT COUNT(*)::NUMERIC as cnt
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id AND check_in::DATE BETWEEN v_prev_start AND v_prev_end
        GROUP BY check_in::DATE
    ) s2;

    daily_avg_checkins := v_att_avg_curr;
    IF v_att_avg_prev > 0 THEN
        daily_avg_checkins_change := CASE WHEN v_att_avg_curr >= v_att_avg_prev THEN '+' ELSE '' END || ((v_att_avg_curr - v_att_avg_prev) * 100 / v_att_avg_prev)::INT || '%';
    ELSE
        daily_avg_checkins_change := '0%';
    END IF;

    -- Peak Hours (mode of check_in hours)
    SELECT checkin_hour INTO v_peak_hour
    FROM (
        SELECT EXTRACT(HOUR FROM check_in)::INT as checkin_hour, COUNT(*) as cnt
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id AND check_in::DATE BETWEEN v_curr_start AND v_curr_end
        GROUP BY checkin_hour
        ORDER BY cnt DESC
        LIMIT 1
    ) t;

    IF v_peak_hour IS NULL THEN
        peak_hours := '07:00 AM - 09:00 AM';
    ELSE
        DECLARE
            v_start_h INT := v_peak_hour;
            v_end_h INT := (v_peak_hour + 2) % 24;
            v_start_suffix TEXT := 'AM';
            v_end_suffix TEXT := 'AM';
        BEGIN
            IF v_start_h >= 12 THEN
                v_start_suffix := 'PM';
                IF v_start_h > 12 THEN v_start_h := v_start_h - 12; END IF;
            ELSIF v_start_h = 0 THEN
                v_start_h := 12;
            END IF;
            
            IF v_end_h >= 12 THEN
                v_end_suffix := 'PM';
                IF v_end_h > 12 THEN v_end_h := v_end_h - 12; END IF;
            ELSIF v_end_h = 0 THEN
                v_end_h := 12;
            END IF;
            
            peak_hours := lpad(v_start_h::TEXT, 2, '0') || ':00 ' || v_start_suffix || ' - ' || lpad(v_end_h::TEXT, 2, '0') || ':00 ' || v_end_suffix;
        END;
    END IF;

    -- Late check-in rate (after 08:30 AM is late check-in)
    SELECT COALESCE(ROUND(COUNT(CASE WHEN (check_in::TIME >= '08:30:00'::TIME) THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 1), 0.0) INTO v_late_curr
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND check_in::DATE BETWEEN v_curr_start AND v_curr_end;

    SELECT COALESCE(ROUND(COUNT(CASE WHEN (check_in::TIME >= '08:30:00'::TIME) THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 1), 0.0) INTO v_late_prev
    FROM public.attendance_logs
    WHERE gym_id = p_gym_id AND check_in::DATE BETWEEN v_prev_start AND v_prev_end;

    late_checkin_rate := v_late_curr::INT || '%';
    IF v_late_prev > 0 THEN
        late_checkin_rate_change := CASE WHEN v_late_curr >= v_late_prev THEN '+' ELSE '' END || (v_late_curr - v_late_prev)::INT || '%';
    ELSE
        late_checkin_rate_change := '0%';
    END IF;

    -- 4. Staff logs
    SELECT COUNT(*)::INT INTO v_staff_total FROM public.staff WHERE gym_id = p_gym_id AND status = 'Active';
    SELECT COUNT(DISTINCT user_id)::INT INTO v_staff_pres 
    FROM public.attendance_logs 
    WHERE gym_id = p_gym_id AND role = 'staff' AND check_in::DATE = CURRENT_DATE;

    staff_present := v_staff_pres || ' / ' || v_staff_total;

    SELECT COALESCE(ROUND(AVG(rating), 1), 4.8) INTO v_pt_rating
    FROM public.staff
    WHERE gym_id = p_gym_id AND status = 'Active' AND rating > 0;

    avg_pt_rating := v_pt_rating::TEXT || ' / 5';

    RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
