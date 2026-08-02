-- ====================================================
-- GYMOS - DATABASE-SIDE REPORTS CALCULATION SYSTEM
-- ====================================================

-- 1. Function to fetch overall report summary statistics (avoiding full table client downloads)
CREATE OR REPLACE FUNCTION public.get_all_reports_stats(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_revenue NUMERIC(12, 2);
    v_expense NUMERIC(12, 2);
    v_pending NUMERIC(12, 2);
    v_members INT;
    v_staff INT;
    v_pt_members INT;
    v_trials INT;
BEGIN
    -- Get total revenue
    SELECT COALESCE(SUM(amount), 0.0) INTO v_revenue
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id AND type = 'Revenue';

    -- Get total expense
    SELECT COALESCE(SUM(amount), 0.0) INTO v_expense
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id AND type = 'Expense';

    -- Get pending payments total from members table
    SELECT COALESCE(SUM(pending_amount), 0.0) INTO v_pending
    FROM public.members
    WHERE gym_id = p_gym_id;

    -- Get total members count
    SELECT COUNT(*) INTO v_members
    FROM public.members
    WHERE gym_id = p_gym_id;

    -- Get total staff count
    SELECT COUNT(*) INTO v_staff
    FROM public.staff
    WHERE gym_id = p_gym_id;

    -- Get personal training members count
    SELECT COUNT(*) INTO v_pt_members
    FROM public.members
    WHERE gym_id = p_gym_id AND pt_member = true;

    -- Get trial members count
    SELECT COUNT(*) INTO v_trials
    FROM public.trial_members
    WHERE gym_id = p_gym_id;

    RETURN jsonb_build_object(
        'revenue_total', v_revenue,
        'expense_total', v_expense,
        'pending_payments_total', v_pending,
        'members_count', v_members,
        'staff_count', v_staff,
        'pt_members_count', v_pt_members,
        'trials_count', v_trials
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Function to fetch trial member report details directly from backend
CREATE OR REPLACE FUNCTION public.get_trial_report_stats(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total', COUNT(*),
        'active', COUNT(*) FILTER (WHERE status != 'Converted' AND CURRENT_DATE <= end_date),
        'expired', COUNT(*) FILTER (WHERE status != 'Converted' AND CURRENT_DATE > end_date),
        'converted', COUNT(*) FILTER (WHERE status = 'Converted'),
        'free', COUNT(*) FILTER (WHERE trial_type = 'Free'),
        'paid', COUNT(*) FILTER (WHERE trial_type = 'Paid'),
        'revenue', COALESCE(SUM(received_amount) FILTER (WHERE trial_type = 'Paid'), 0.0)
    ) INTO result
    FROM public.trial_members
    WHERE gym_id = p_gym_id;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.get_all_reports_stats(UUID) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_trial_report_stats(UUID) TO anon, authenticated, service_role;
