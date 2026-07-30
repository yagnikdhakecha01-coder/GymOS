-- 1. Date parser helper to robustly parse text dates ('16 Jul 2026' or '2026-07-16')
CREATE OR REPLACE FUNCTION public.safe_parse_date(date_str TEXT)
RETURNS DATE AS $$
BEGIN
    IF date_str IS NULL OR date_str = '' THEN
        RETURN NULL;
    END IF;
    -- Try DD Mon YYYY (e.g. '16 Jul 2026')
    BEGIN
        RETURN to_date(date_str, 'DD Mon YYYY');
    EXCEPTION WHEN OTHERS THEN
        -- Try YYYY-MM-DD
        BEGIN
            RETURN date_str::DATE;
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 2. Dashboard RPC stats by date (updated with alerts count)
CREATE OR REPLACE FUNCTION public.get_gym_dashboard_stats(p_gym_id UUID, p_target_date DATE)
RETURNS TABLE (
    monthly_revenue NUMERIC,
    active_members INT,
    total_members INT,
    today_attendance INT,
    expiring_today INT,
    expiring_15_days INT,
    pending_leaves INT,
    pending_holidays INT
) AS $$
DECLARE
    v_month_start DATE := date_trunc('month', p_target_date);
    v_month_end DATE := (date_trunc('month', p_target_date) + interval '1 month' - interval '1 day')::DATE;
BEGIN
    RETURN QUERY
    SELECT
        -- Monthly revenue in target month
        COALESCE((
            SELECT SUM(amount)
            FROM public.finance_transactions
            WHERE gym_id = p_gym_id
              AND type = 'Revenue'
              AND transaction_date::DATE BETWEEN v_month_start AND v_month_end
        ), 0.0)::NUMERIC AS monthly_revenue,

        -- Active members as of target date (joined on/before target date & active status)
        (
            SELECT COUNT(*)::INT
            FROM public.members
            WHERE gym_id = p_gym_id
              AND status = 'Active'
              AND public.safe_parse_date(join_date) <= p_target_date
        ) AS active_members,

        -- Total members as of target date (joined on/before target date)
        (
            SELECT COUNT(*)::INT
            FROM public.members
            WHERE gym_id = p_gym_id
              AND public.safe_parse_date(join_date) <= p_target_date
        ) AS total_members,

        -- Today's attendance (on target date)
        (
            SELECT COUNT(DISTINCT user_id)::INT
            FROM public.attendance_logs
            WHERE gym_id = p_gym_id
              AND user_type = 'Member'
              AND status IN ('Present', 'Late', 'Early Exit', 'Overtime')
              AND (
                date = to_char(p_target_date, 'dd-MM-yyyy')
                OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_target_date
              )
        ) AS today_attendance,

        -- Expiring today
        (
            SELECT COUNT(*)::INT
            FROM public.member_memberships
            WHERE gym_id = p_gym_id
              AND end_date = p_target_date
        ),

        -- Expiring in 15 days
        (
            SELECT COUNT(*)::INT
            FROM public.member_memberships
            WHERE gym_id = p_gym_id
              AND end_date BETWEEN p_target_date AND (p_target_date + interval '15 days')::DATE
        ),

        -- Pending leaves
        (
            SELECT COUNT(*)::INT
            FROM public.leave_requests
            WHERE gym_id = p_gym_id
              AND status = 'Pending'::public.leave_status
        ),

        -- Pending holidays (leaves with leave_type = 'Other')
        (
            SELECT COUNT(*)::INT
            FROM public.leave_requests
            WHERE gym_id = p_gym_id
              AND status = 'Pending'::public.leave_status
              AND leave_type = 'Other'::public.leave_type
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Finance Summary RPC stats by date (includes 6 sparkline data points)
CREATE OR REPLACE FUNCTION public.get_finance_summary(p_gym_id UUID, p_target_date DATE)
RETURNS TABLE (
    total_revenue NUMERIC,
    total_expense NUMERIC,
    net_profit NUMERIC,
    monthly_revenue_data NUMERIC[]
) AS $$
DECLARE
    v_month_start DATE := date_trunc('month', p_target_date);
    v_month_end DATE := (date_trunc('month', p_target_date) + interval '1 month' - interval '1 day')::DATE;
    v_revenue_list NUMERIC[] := ARRAY[]::NUMERIC[];
    v_day INT;
    v_day_rev NUMERIC;
BEGIN
    -- Monthly Revenue
    SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO total_revenue
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id
      AND type = 'Revenue'
      AND transaction_date::DATE BETWEEN v_month_start AND v_month_end;

    -- Monthly Expense
    SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO total_expense
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id
      AND type = 'Expense'
      AND transaction_date::DATE BETWEEN v_month_start AND v_month_end;

    -- Net Profit
    net_profit := total_revenue - total_expense;

    -- Calculate 6 data points for the sparkline chart dynamically (5-day intervals)
    FOR v_day IN 0..5 LOOP
        SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO v_day_rev
        FROM public.finance_transactions
        WHERE gym_id = p_gym_id
          AND type = 'Revenue'
          AND transaction_date::DATE >= (v_month_start + (v_day * 5) * interval '1 day')::DATE
          AND transaction_date::DATE < (v_month_start + ((v_day + 1) * 5) * interval '1 day')::DATE;
        v_revenue_list := array_append(v_revenue_list, v_day_rev);
    END LOOP;

    monthly_revenue_data := v_revenue_list;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
