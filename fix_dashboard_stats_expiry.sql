-- Update get_gym_dashboard_stats function to dynamically query expiryDate from extra_fields in public.members table
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

        -- Expiring today (from public.members extra_fields)
        (
            SELECT COUNT(*)::INT
            FROM public.members
            WHERE gym_id = p_gym_id
              AND extra_fields->>'expiryDate' IS NOT NULL 
              AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = p_target_date
        ),

        -- Expiring in next 1 to 15 days (from public.members extra_fields, excluding today)
        (
            SELECT COUNT(*)::INT
            FROM public.members
            WHERE gym_id = p_gym_id
              AND extra_fields->>'expiryDate' IS NOT NULL 
              AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE > p_target_date
              AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE <= (p_target_date + interval '15 days')::DATE
        ),

        -- Pending leaves (leaves with leave_type != 'Other')
        (
            SELECT COUNT(*)::INT
            FROM public.leave_requests
            WHERE gym_id = p_gym_id
              AND status = 'Pending'::public.leave_status
              AND leave_type != 'Other'::public.leave_type
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
