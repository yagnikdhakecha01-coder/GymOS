-- =========================================================================
-- MIGRATION: add_owner_staff_card_rpc.sql
-- Description: RPC function to fetch detailed staff card metrics directly from DB
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_owner_staff_cards_v1(
    p_gym_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    staff_id UUID,
    name TEXT,
    role TEXT,
    avatar TEXT,
    status TEXT,
    salary_pending NUMERIC,
    present_days INT,
    leave_days INT,
    early_exit_count INT,
    last_check_in TEXT,
    is_checked_in BOOLEAN,
    current_date_str TEXT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_of_month DATE := date_trunc('month', p_date)::DATE;
BEGIN
    RETURN QUERY
    WITH monthly_attendance AS (
        SELECT 
            s.id AS s_id,
            COUNT(DISTINCT al.check_in::DATE)::INT AS month_present,
            COUNT(DISTINCT CASE WHEN al.status IN ('Leave', 'Half Leave', 'On Leave') THEN al.check_in::DATE END)::INT AS month_leave,
            COUNT(CASE WHEN al.status = 'Early Exit' OR COALESCE(al.early_exit_minutes, 0) > 0 THEN 1 END)::INT AS month_early_exit
        FROM public.staff s
        LEFT JOIN public.attendance_logs al 
               ON (al.user_id = s.user_id OR al.user_id = s.id)
              AND al.gym_id = p_gym_id
              AND al.user_type = 'Staff'
              AND al.status IN ('Present', 'Late', 'Half Day', 'Overtime', 'Early Exit')
              AND al.check_in::DATE >= v_start_of_month
              AND al.check_in::DATE <= p_date
        WHERE s.gym_id = p_gym_id
        GROUP BY s.id
    ),
    today_attendance AS (
        SELECT DISTINCT ON (s.id)
            s.id AS s_id,
            al.check_in,
            al.check_out,
            (al.check_out IS NULL) AS checked_in
        FROM public.staff s
        JOIN public.attendance_logs al 
          ON (al.user_id = s.user_id OR al.user_id = s.id)
         AND al.gym_id = p_gym_id
         AND al.user_type = 'Staff'
         AND al.check_in::DATE = p_date
        WHERE s.gym_id = p_gym_id
        ORDER BY s.id, al.check_in DESC
    ),
    salary_dues AS (
        SELECT 
            s.id AS s_id,
            COALESCE(public.get_staff_pending_salary(s.id), s.salary_due, 0.0) AS pending_amt
        FROM public.staff s
        WHERE s.gym_id = p_gym_id
    )
    SELECT 
        s.id AS staff_id,
        s.name,
        s.role,
        COALESCE(s.avatar, '') AS avatar,
        s.status,
        COALESCE(sd.pending_amt, 0.0)::NUMERIC AS salary_pending,
        COALESCE(ma.month_present, 0)::INT AS present_days,
        COALESCE(ma.month_leave, 0)::INT AS leave_days,
        COALESCE(ma.month_early_exit, 0)::INT AS early_exit_count,
        CASE 
            WHEN ta.check_in IS NOT NULL THEN to_char(ta.check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')
            ELSE 'N/A'
        END AS last_check_in,
        COALESCE(ta.checked_in, FALSE) AS is_checked_in,
        to_char(p_date, 'DD Mon YYYY') AS current_date_str
    FROM public.staff s
    LEFT JOIN monthly_attendance ma ON s.id = ma.s_id
    LEFT JOIN today_attendance ta ON s.id = ta.s_id
    LEFT JOIN salary_dues sd ON s.id = sd.s_id
    WHERE s.gym_id = p_gym_id
    ORDER BY s.created_at DESC;
END;
$$;
