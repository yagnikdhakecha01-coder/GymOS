-- Redefine log_attendance_alert to do nothing for check-in/out related alert types
CREATE OR REPLACE FUNCTION public.log_attendance_alert(
    p_gym_id UUID,
    p_alert_type TEXT,
    p_message TEXT,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID AS $$
BEGIN
    -- Ignore check-in and check-out related alert types
    IF p_alert_type IN (
        'Staff Check In', 'Staff Check Out', 'Late Entry', 'Early Exit', 
        'Duplicate Check In', 'QR Expired', 'Rejected QR', 'Wrong Gym QR', 
        'Wrong Shift', 'Display Not Verified'
    ) THEN
        RETURN;
    END IF;

    INSERT INTO public.attendance_alerts (gym_id, alert_type, message, metadata, is_read, created_at)
    VALUES (p_gym_id, p_alert_type, p_message, p_metadata, FALSE, now());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Clear out legacy check-in/out alert entries
DELETE FROM public.attendance_alerts 
WHERE alert_type IN (
    'Staff Check In', 'Staff Check Out', 'Late Entry', 'Early Exit', 
    'Duplicate Check In', 'QR Expired', 'Rejected QR', 'Wrong Gym QR', 
    'Wrong Shift', 'Display Not Verified'
);

-- 1. Date parser helper to robustly parse text dates ('16 Jul 2026' or '2026-07-16')
CREATE OR REPLACE FUNCTION public.safe_parse_date(date_str TEXT)
RETURNS DATE AS $$
BEGIN
    IF date_str IS NULL OR date_str = '' THEN
        RETURN NULL;
    END IF;
    BEGIN
        RETURN to_date(date_str, 'DD Mon YYYY');
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            RETURN date_str::DATE;
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 2. get_dashboard_alerts_v1 function to fetch all dynamic alerts grouped by exact date offsets
CREATE OR REPLACE FUNCTION public.get_dashboard_alerts_v1(p_gym_id UUID, p_target_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB AS $$
DECLARE
    -- Ending today (0 days)
    v_ending_today_count INT := 0;
    v_ending_today_avatars TEXT[] := ARRAY[]::TEXT[];
    
    -- Expiring in 1 day (tomorrow)
    v_expiring_1_day_count INT := 0;
    v_expiring_1_day_avatars TEXT[] := ARRAY[]::TEXT[];
    
    -- Expiring in 3 days (range of 2-3 days)
    v_expiring_3_days_count INT := 0;
    v_expiring_3_days_avatars TEXT[] := ARRAY[]::TEXT[];
    
    -- Expiring in 7 days (range of 4-7 days)
    v_expiring_7_days_count INT := 0;
    v_expiring_7_days_avatars TEXT[] := ARRAY[]::TEXT[];
    
    -- Expiring in 15 days (range of 8-15 days)
    v_expiring_15_days_count INT := 0;
    v_expiring_15_days_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_staff_leaves_count INT := 0;
    v_staff_leaves_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_holiday_requests_count INT := 0;
    v_holiday_requests_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_payments_pending_count INT := 0;
    v_payments_pending_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_pt_trials_count INT := 0;
    v_pt_trials_avatars TEXT[] := ARRAY[]::TEXT[];

    v_staff_advances_count INT := 0;
    v_staff_advances_avatars TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- 1. Memberships ending today (0 days)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_ending_today_count, v_ending_today_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = p_target_date;

    IF v_ending_today_avatars IS NULL THEN v_ending_today_avatars := ARRAY[]::TEXT[]; END IF;

    -- 2. Memberships expiring in 1 day (tomorrow)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_expiring_1_day_count, v_expiring_1_day_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = (p_target_date + INTERVAL '1 day')::DATE;

    IF v_expiring_1_day_avatars IS NULL THEN v_expiring_1_day_avatars := ARRAY[]::TEXT[]; END IF;

    -- 3. Memberships expiring in 3 days (range of 2 to 3 days)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_expiring_3_days_count, v_expiring_3_days_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE >= (p_target_date + INTERVAL '2 days')::DATE
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE <= (p_target_date + INTERVAL '3 days')::DATE;

    IF v_expiring_3_days_avatars IS NULL THEN v_expiring_3_days_avatars := ARRAY[]::TEXT[]; END IF;

    -- 4. Memberships expiring in 7 days (range of 4 to 7 days)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_expiring_7_days_count, v_expiring_7_days_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE >= (p_target_date + INTERVAL '4 days')::DATE
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE <= (p_target_date + INTERVAL '7 days')::DATE;

    IF v_expiring_7_days_avatars IS NULL THEN v_expiring_7_days_avatars := ARRAY[]::TEXT[]; END IF;

    -- 5. Memberships expiring in 15 days (range of 8 to 15 days)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_expiring_15_days_count, v_expiring_15_days_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE >= (p_target_date + INTERVAL '8 days')::DATE
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE <= (p_target_date + INTERVAL '15 days')::DATE;

    IF v_expiring_15_days_avatars IS NULL THEN v_expiring_15_days_avatars := ARRAY[]::TEXT[]; END IF;

    -- 6. Staff Leave Requests (leave_type != 'Other' and status = 'Pending')
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(s.avatar, '')) FILTER (WHERE s.avatar IS NOT NULL AND s.avatar != '')
    INTO v_staff_leaves_count, v_staff_leaves_avatars
    FROM public.leave_requests lr
    JOIN public.staff s ON lr.staff_id = s.id
    WHERE lr.gym_id = p_gym_id 
      AND lr.status = 'Pending'::public.leave_status
      AND lr.leave_type != 'Other'::public.leave_type;

    IF v_staff_leaves_avatars IS NULL THEN v_staff_leaves_avatars := ARRAY[]::TEXT[]; END IF;

    -- 7. Holiday Requests (leave_type = 'Other' and status = 'Pending')
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(s.avatar, '')) FILTER (WHERE s.avatar IS NOT NULL AND s.avatar != '')
    INTO v_holiday_requests_count, v_holiday_requests_avatars
    FROM public.leave_requests lr
    JOIN public.staff s ON lr.staff_id = s.id
    WHERE lr.gym_id = p_gym_id 
      AND lr.status = 'Pending'::public.leave_status
      AND lr.leave_type = 'Other'::public.leave_type;

    IF v_holiday_requests_avatars IS NULL THEN v_holiday_requests_avatars := ARRAY[]::TEXT[]; END IF;

    -- 8. Payments still pending (pending_amount > 0)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_payments_pending_count, v_payments_pending_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND pending_amount > 0;

    IF v_payments_pending_avatars IS NULL THEN v_payments_pending_avatars := ARRAY[]::TEXT[]; END IF;

    -- 9. PT Trials (status = 'Trial')
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_pt_trials_count, v_pt_trials_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND status = 'Trial';

    IF v_pt_trials_avatars IS NULL THEN v_pt_trials_avatars := ARRAY[]::TEXT[]; END IF;

    -- 10. Staff Advance Requests (status = 'Pending')
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(s.avatar, '')) FILTER (WHERE s.avatar IS NOT NULL AND s.avatar != '')
    INTO v_staff_advances_count, v_staff_advances_avatars
    FROM public.salary_advance_ledger sal
    JOIN public.staff s ON sal.staff_id = s.id
    WHERE sal.gym_id = p_gym_id 
      AND sal.status = 'Pending'::public.advance_status;

    IF v_staff_advances_avatars IS NULL THEN v_staff_advances_avatars := ARRAY[]::TEXT[]; END IF;

    -- Return grouped alerts as JSONB
    RETURN jsonb_build_object(
        'memberships_ending_today', jsonb_build_object(
            'count', v_ending_today_count,
            'avatars', to_jsonb(v_ending_today_avatars)
        ),
        'memberships_expiring_1_day', jsonb_build_object(
            'count', v_expiring_1_day_count,
            'avatars', to_jsonb(v_expiring_1_day_avatars)
        ),
        'memberships_expiring_3_days', jsonb_build_object(
            'count', v_expiring_3_days_count,
            'avatars', to_jsonb(v_expiring_3_days_avatars)
        ),
        'memberships_expiring_7_days', jsonb_build_object(
            'count', v_expiring_7_days_count,
            'avatars', to_jsonb(v_expiring_7_days_avatars)
        ),
        'memberships_expiring_15_days', jsonb_build_object(
            'count', v_expiring_15_days_count,
            'avatars', to_jsonb(v_expiring_15_days_avatars)
        ),
        'staff_leave_requests', jsonb_build_object(
            'count', v_staff_leaves_count,
            'avatars', to_jsonb(v_staff_leaves_avatars)
        ),
        'holiday_requests', jsonb_build_object(
            'count', v_holiday_requests_count,
            'avatars', to_jsonb(v_holiday_requests_avatars)
        ),
        'payments_pending', jsonb_build_object(
            'count', v_payments_pending_count,
            'avatars', to_jsonb(v_payments_pending_avatars)
        ),
        'pt_trials', jsonb_build_object(
            'count', v_pt_trials_count,
            'avatars', to_jsonb(v_pt_trials_avatars)
        ),
        'staff_advance_requests', jsonb_build_object(
            'count', v_staff_advances_count,
            'avatars', to_jsonb(v_staff_advances_avatars)
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. check_new_alerts_v1 function to fetch alert titles and messages for push notifications
CREATE OR REPLACE FUNCTION public.check_new_alerts_v1(p_gym_id UUID, p_target_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    alert_type TEXT,
    entity_id TEXT,
    title TEXT,
    message TEXT,
    avatar_url TEXT
) AS $$
BEGIN
    -- 1. Memberships ending today (0 days)
    RETURN QUERY
    SELECT 
        'membership_expiry'::TEXT AS alert_type,
        (m.id::TEXT || '_0') AS entity_id,
        'Membership ending today!'::TEXT AS title,
        (m.name || '''s membership ends today. Take action immediately!')::TEXT AS message,
        COALESCE(m.avatar, '')::TEXT AS avatar_url
    FROM public.members m
    WHERE m.gym_id = p_gym_id 
      AND m.extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(m.extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = p_target_date;

    -- 2. Memberships expiring tomorrow (1 day)
    RETURN QUERY
    SELECT 
        'membership_expiry'::TEXT AS alert_type,
        (m.id::TEXT || '_1') AS entity_id,
        'Membership expiring tomorrow!'::TEXT AS title,
        (m.name || '''s membership expires tomorrow.')::TEXT AS message,
        COALESCE(m.avatar, '')::TEXT AS avatar_url
    FROM public.members m
    WHERE m.gym_id = p_gym_id 
      AND m.extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(m.extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = (p_target_date + INTERVAL '1 day')::DATE;

    -- 3. Memberships expiring in 3 days
    RETURN QUERY
    SELECT 
        'membership_expiry'::TEXT AS alert_type,
        (m.id::TEXT || '_3') AS entity_id,
        'Membership expiring in 3 days!'::TEXT AS title,
        (m.name || '''s membership expires in 3 days.')::TEXT AS message,
        COALESCE(m.avatar, '')::TEXT AS avatar_url
    FROM public.members m
    WHERE m.gym_id = p_gym_id 
      AND m.extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(m.extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = (p_target_date + INTERVAL '3 days')::DATE;

    -- 4. Memberships expiring in 7 days
    RETURN QUERY
    SELECT 
        'membership_expiry'::TEXT AS alert_type,
        (m.id::TEXT || '_7') AS entity_id,
        'Membership expiring in 7 days!'::TEXT AS title,
        (m.name || '''s membership expires in 7 days.')::TEXT AS message,
        COALESCE(m.avatar, '')::TEXT AS avatar_url
    FROM public.members m
    WHERE m.gym_id = p_gym_id 
      AND m.extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(m.extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = (p_target_date + INTERVAL '7 days')::DATE;

    -- 5. Memberships expiring in 15 days
    RETURN QUERY
    SELECT 
        'membership_expiry'::TEXT AS alert_type,
        (m.id::TEXT || '_15') AS entity_id,
        'Membership expiring in 15 days!'::TEXT AS title,
        (m.name || '''s membership expires in 15 days.')::TEXT AS message,
        COALESCE(m.avatar, '')::TEXT AS avatar_url
    FROM public.members m
    WHERE m.gym_id = p_gym_id 
      AND m.extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(m.extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = (p_target_date + INTERVAL '15 days')::DATE;

    -- 6. Pending staff leave requests
    RETURN QUERY
    SELECT 
        'staff_leave'::TEXT AS alert_type,
        lr.id::TEXT AS entity_id,
        'New Staff Leave Request!'::TEXT AS title,
        (s.name || ' requested ' || lr.leave_type::TEXT || ' leave starting ' || to_char(lr.start_date, 'DD Mon YYYY'))::TEXT AS message,
        COALESCE(s.avatar, '')::TEXT AS avatar_url
    FROM public.leave_requests lr
    JOIN public.staff s ON lr.staff_id = s.id
    WHERE lr.gym_id = p_gym_id 
      AND lr.status = 'Pending'::public.leave_status;

    -- 7. Pending staff advance requests
    RETURN QUERY
    SELECT 
        'staff_advance'::TEXT AS alert_type,
        sal.id::TEXT AS entity_id,
        'New Staff Advance Request!'::TEXT AS title,
        (s.name || ' requested advance of ₹' || sal.advance_amount::TEXT)::TEXT AS message,
        COALESCE(s.avatar, '')::TEXT AS avatar_url
    FROM public.salary_advance_ledger sal
    JOIN public.staff s ON sal.staff_id = s.id
    WHERE sal.gym_id = p_gym_id 
      AND sal.status = 'Pending'::public.advance_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
