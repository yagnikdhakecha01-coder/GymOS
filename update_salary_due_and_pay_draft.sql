-- ====================================================================
-- GYMOS: SALARY DUE, OWNER STAFF CARD & PAY SALARY DRAFT RPC FIXES
-- ====================================================================

-- 1. FIX RPC: get_total_salary_due
CREATE OR REPLACE FUNCTION public.get_total_salary_due(p_gym_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_month_str TEXT := to_char(CURRENT_DATE, 'FMMonth YYYY');
    v_total_due NUMERIC(12,2) := 0.0;
BEGIN
    SELECT COALESCE(SUM(s.salary), 0.0) INTO v_total_due
    FROM public.staff s
    WHERE s.gym_id = p_gym_id
      AND s.status = 'Active'
      AND NOT EXISTS (
          SELECT 1 FROM public.salary_drafts sd
          WHERE sd.staff_id = s.id
            AND trim(sd.salary_month) = trim(v_month_str)
            AND sd.status = 'Paid'::public.draft_status
      );

    RETURN v_total_due;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_total_salary_due(UUID) TO anon, authenticated, service_role;


-- 2. FIX RPC: get_owner_staff_cards_v1
DROP FUNCTION IF EXISTS public.get_owner_staff_cards_v1(UUID, DATE);

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
    current_date_str TEXT,
    is_salary_paid BOOLEAN,
    paid_amount NUMERIC
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_of_month DATE := date_trunc('month', p_date)::DATE;
    v_month_str TEXT := to_char(p_date, 'FMMonth YYYY');
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
    paid_drafts AS (
        SELECT 
            sd.staff_id AS s_id,
            TRUE AS is_paid,
            sd.net_salary AS amount
        FROM public.salary_drafts sd
        WHERE sd.gym_id = p_gym_id
          AND trim(sd.salary_month) = trim(v_month_str)
          AND sd.status = 'Paid'::public.draft_status
    )
    SELECT 
        s.id AS staff_id,
        s.name,
        s.role,
        COALESCE(s.avatar, '') AS avatar,
        s.status,
        CASE 
            WHEN COALESCE(pd.is_paid, FALSE) = TRUE THEN 0.0
            ELSE COALESCE(s.salary, 0.0)
        END::NUMERIC AS salary_pending,
        COALESCE(ma.month_present, 0)::INT AS present_days,
        COALESCE(ma.month_leave, 0)::INT AS leave_days,
        COALESCE(ma.month_early_exit, 0)::INT AS early_exit_count,
        CASE 
            WHEN ta.check_in IS NOT NULL THEN to_char(ta.check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')
            ELSE 'N/A'
        END AS last_check_in,
        COALESCE(ta.checked_in, FALSE) AS is_checked_in,
        to_char(p_date, 'DD Mon YYYY') AS current_date_str,
        COALESCE(pd.is_paid, FALSE) AS is_salary_paid,
        COALESCE(pd.amount, 0.0)::NUMERIC AS paid_amount
    FROM public.staff s
    LEFT JOIN monthly_attendance ma ON s.id = ma.s_id
    LEFT JOIN today_attendance ta ON s.id = ta.s_id
    LEFT JOIN paid_drafts pd ON s.id = pd.s_id
    WHERE s.gym_id = p_gym_id
    ORDER BY s.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_owner_staff_cards_v1(UUID, DATE) TO anon, authenticated, service_role;


-- 3. FIX RPC: pay_salary_draft
CREATE OR REPLACE FUNCTION public.pay_salary_draft(
    p_draft_id UUID,
    p_payment_mode TEXT DEFAULT 'Cash',
    p_notes TEXT DEFAULT ''
)
RETURNS VOID AS $$
DECLARE
    v_gym_id UUID;
    v_staff_id UUID;
    v_net_salary NUMERIC(12,2);
    v_advance_deduction NUMERIC(12,2);
    v_salary_month TEXT;
    v_tx_id UUID;
    s_name TEXT;
    r_advance RECORD;
    v_to_recover NUMERIC(12,2) := 0.0;
    v_recovered_temp NUMERIC(12,2) := 0.0;
BEGIN
    -- Fetch draft details
    SELECT gym_id, staff_id, net_salary, advance_deduction, salary_month
    INTO v_gym_id, v_staff_id, v_net_salary, v_advance_deduction, v_salary_month
    FROM public.salary_drafts
    WHERE id = p_draft_id AND status <> 'Paid'::public.draft_status;

    IF NOT FOUND THEN
        -- Already paid
        RETURN;
    END IF;

    SELECT name INTO s_name FROM public.staff WHERE id = v_staff_id;

    -- 1. Insert into expenses table
    IF NOT EXISTS (
        SELECT 1 FROM public.expenses 
        WHERE gym_id = v_gym_id 
          AND category = 'Salaries' 
          AND amount = v_net_salary 
          AND date = CURRENT_DATE
    ) THEN
        INSERT INTO public.expenses (
            gym_id,
            title,
            category,
            amount,
            date,
            notes
        ) VALUES (
            v_gym_id,
            'Salary Payment - ' || COALESCE(s_name, 'Staff'),
            'Salaries',
            v_net_salary,
            CURRENT_DATE,
            COALESCE(p_notes, 'Salary payment for ' || v_salary_month)
        );
    END IF;

    -- 2. Insert into transactions table
    IF NOT EXISTS (
        SELECT 1 FROM public.transactions 
        WHERE gym_id = v_gym_id 
          AND type = 'Expense' 
          AND category = 'Salaries' 
          AND amount = v_net_salary 
          AND date = CURRENT_DATE
    ) THEN
        INSERT INTO public.transactions (
            gym_id,
            type,
            title,
            category,
            amount,
            date
        )
        VALUES (
            v_gym_id,
            'Expense',
            'Salary Payment - ' || COALESCE(s_name, 'Staff'),
            'Salaries',
            v_net_salary,
            CURRENT_DATE
        ) RETURNING id INTO v_tx_id;
    END IF;

    -- 3. Mark Commissions included as Paid
    UPDATE public.commission_ledger
    SET status = 'Paid'::public.commission_status,
        paid_at = NOW()
    WHERE staff_id = v_staff_id AND status = 'Pending'::public.commission_status;

    -- 4. Recover advances dynamically
    v_to_recover := COALESCE(v_advance_deduction, 0.0);
    IF v_to_recover > 0 THEN
        FOR r_advance IN 
            SELECT id, remaining_amount, recovered_amount, advance_amount
            FROM public.salary_advance_ledger
            WHERE staff_id = v_staff_id 
              AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
            ORDER BY given_date ASC
        LOOP
            IF v_to_recover <= 0 THEN
                EXIT;
            END IF;

            IF r_advance.remaining_amount <= v_to_recover THEN
                v_recovered_temp := r_advance.remaining_amount;
                
                UPDATE public.salary_advance_ledger
                SET recovered_amount = r_advance.advance_amount,
                    remaining_amount = 0.0,
                    status = 'Recovered'::public.advance_status,
                    salary_payment_id = p_draft_id,
                    updated_at = NOW()
                WHERE id = r_advance.id;
                
                v_to_recover := v_to_recover - v_recovered_temp;
            ELSE
                UPDATE public.salary_advance_ledger
                SET recovered_amount = COALESCE(r_advance.recovered_amount, 0.0) + v_to_recover,
                    remaining_amount = r_advance.remaining_amount - v_to_recover,
                    salary_payment_id = p_draft_id,
                    updated_at = NOW()
                WHERE id = r_advance.id;
                
                v_to_recover := 0.0;
            END IF;
        END LOOP;
    END IF;

    -- 5. Mark draft as Paid
    UPDATE public.salary_drafts
    SET status = 'Paid'::public.draft_status,
        paid_transaction_id = v_tx_id,
        created_at = NOW()
    WHERE id = p_draft_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.pay_salary_draft(UUID, TEXT, TEXT) TO anon, authenticated, service_role;
