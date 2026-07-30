-- Create or replace get_dashboard_alerts_v1 function to compute all gym alerts
CREATE OR REPLACE FUNCTION public.get_dashboard_alerts_v1(p_gym_id UUID, p_target_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB AS $$
DECLARE
    v_memberships_ending_today_count INT := 0;
    v_memberships_ending_today_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_memberships_expiring_15_days_count INT := 0;
    v_memberships_expiring_15_days_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_staff_leaves_count INT := 0;
    v_staff_leaves_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_holiday_requests_count INT := 0;
    v_holiday_requests_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_payments_pending_count INT := 0;
    v_payments_pending_avatars TEXT[] := ARRAY[]::TEXT[];
    
    v_pt_trials_count INT := 0;
    v_pt_trials_avatars TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- 1. Memberships ending today (expiryDate = p_target_date)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_memberships_ending_today_count, v_memberships_ending_today_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = p_target_date;

    IF v_memberships_ending_today_avatars IS NULL THEN
        v_memberships_ending_today_avatars := ARRAY[]::TEXT[];
    END IF;

    -- 2. Memberships expiring in 15 days (next 15 days, excluding today)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_memberships_expiring_15_days_count, v_memberships_expiring_15_days_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND extra_fields->>'expiryDate' IS NOT NULL 
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE > p_target_date 
      AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE <= (p_target_date + INTERVAL '15 days')::DATE;

    IF v_memberships_expiring_15_days_avatars IS NULL THEN
        v_memberships_expiring_15_days_avatars := ARRAY[]::TEXT[];
    END IF;

    -- 3. Staff Leave Requests (leave_type != 'Other' and status = 'Pending')
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(s.avatar, '')) FILTER (WHERE s.avatar IS NOT NULL AND s.avatar != '')
    INTO v_staff_leaves_count, v_staff_leaves_avatars
    FROM public.leave_requests lr
    JOIN public.staff s ON lr.staff_id = s.id
    WHERE lr.gym_id = p_gym_id 
      AND lr.status = 'Pending'::public.leave_status
      AND lr.leave_type != 'Other'::public.leave_type;

    IF v_staff_leaves_avatars IS NULL THEN
        v_staff_leaves_avatars := ARRAY[]::TEXT[];
    END IF;

    -- 4. Holiday Requests (leave_type = 'Other' and status = 'Pending')
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(s.avatar, '')) FILTER (WHERE s.avatar IS NOT NULL AND s.avatar != '')
    INTO v_holiday_requests_count, v_holiday_requests_avatars
    FROM public.leave_requests lr
    JOIN public.staff s ON lr.staff_id = s.id
    WHERE lr.gym_id = p_gym_id 
      AND lr.status = 'Pending'::public.leave_status
      AND lr.leave_type = 'Other'::public.leave_type;

    IF v_holiday_requests_avatars IS NULL THEN
        v_holiday_requests_avatars := ARRAY[]::TEXT[];
    END IF;

    -- 5. Payments still pending (pending_amount > 0)
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_payments_pending_count, v_payments_pending_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND pending_amount > 0;

    IF v_payments_pending_avatars IS NULL THEN
        v_payments_pending_avatars := ARRAY[]::TEXT[];
    END IF;

    -- 6. PT Trials (status = 'Trial')
    SELECT 
        COUNT(*)::INT, 
        ARRAY_AGG(COALESCE(avatar, '')) FILTER (WHERE avatar IS NOT NULL AND avatar != '')
    INTO v_pt_trials_count, v_pt_trials_avatars
    FROM public.members
    WHERE gym_id = p_gym_id 
      AND status = 'Trial';

    IF v_pt_trials_avatars IS NULL THEN
        v_pt_trials_avatars := ARRAY[]::TEXT[];
    END IF;

    -- Return grouped alerts as JSONB
    RETURN jsonb_build_object(
        'memberships_ending_today', jsonb_build_object(
            'count', v_memberships_ending_today_count,
            'avatars', to_jsonb(v_memberships_ending_today_avatars)
        ),
        'memberships_expiring_15_days', jsonb_build_object(
            'count', v_memberships_expiring_15_days_count,
            'avatars', to_jsonb(v_memberships_expiring_15_days_avatars)
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
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
