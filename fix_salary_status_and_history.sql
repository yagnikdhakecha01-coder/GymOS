-- ====================================================================
-- GYMOS - PRECISE SALARY STATUS, HISTORY & STAFF CARD SYNCHRONIZATION
-- ====================================================================

-- 1. UPDATE FUNCTION: get_owner_staff_cards_v1
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
    v_mon_short TEXT := to_char(p_date, 'Mon YYYY');
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
            s.id AS s_id,
            TRUE AS is_paid,
            GREATEST(
                COALESCE(sd.gross_salary, 0.0),
                COALESCE(sd.base_salary, s.salary, 0.0) + COALESCE(
                    NULLIF(sd.commission_amount, 0),
                    (SELECT COALESCE(SUM(cl.amount), 0.0) FROM public.commission_ledger cl WHERE cl.salary_payment_id = sd.id OR (cl.staff_id = s.id AND cl.salary_month = v_month_str AND cl.status = 'Paid')),
                    0.0
                ) + COALESCE(sd.other_additions, 0.0) - COALESCE(sd.other_deductions, 0.0),
                COALESCE(sd.net_salary, 0.0) + COALESCE(
                    NULLIF(sd.advance_deduction, 0),
                    (SELECT COALESCE(SUM(sa.recovered_amount), 0.0) FROM public.salary_advance_ledger sa WHERE sa.salary_payment_id = sd.id OR (sa.staff_id = s.id AND sa.salary_month = v_month_str AND sa.status = 'Recovered')),
                    0.0
                ),
                COALESCE(tx.amount, exp.amount, 0.0) + COALESCE(
                    (SELECT COALESCE(SUM(sa.recovered_amount), 0.0) FROM public.salary_advance_ledger sa WHERE sa.staff_id = s.id AND sa.salary_month = v_month_str),
                    0.0
                ),
                COALESCE(sd.net_salary, tx.amount, exp.amount, s.salary, 0.0)
            ) AS amount
        FROM public.staff s
        LEFT JOIN public.salary_drafts sd
               ON sd.staff_id = s.id
              AND (
                trim(lower(sd.salary_month)) = trim(lower(v_month_str))
                OR trim(lower(sd.salary_month)) = trim(lower(v_mon_short))
              )
        LEFT JOIN LATERAL (
            SELECT t.amount, t.date
            FROM public.transactions t
            WHERE t.gym_id = p_gym_id
              AND (t.category ILIKE '%Salaries%' OR t.category ILIKE '%Salary%' OR t.title ILIKE '%Salary%')
              AND t.title ILIKE '%' || s.name || '%'
              AND (to_char(t.date, 'FMMonth YYYY') = trim(v_month_str) OR to_char(t.date, 'Mon YYYY') = trim(v_mon_short))
            LIMIT 1
        ) tx ON TRUE
        LEFT JOIN LATERAL (
            SELECT e.amount, e.date
            FROM public.expenses e
            WHERE e.gym_id = p_gym_id
              AND (e.category ILIKE '%Salaries%' OR e.category ILIKE '%Salary%' OR e.title ILIKE '%Salary%')
              AND e.title ILIKE '%' || s.name || '%'
              AND (to_char(e.date, 'FMMonth YYYY') = trim(v_month_str) OR to_char(e.date, 'Mon YYYY') = trim(v_mon_short))
            LIMIT 1
        ) exp ON TRUE
        WHERE s.gym_id = p_gym_id
          AND (
            lower(sd.status::TEXT) = 'paid'
            OR sd.paid_transaction_id IS NOT NULL
            OR tx.amount IS NOT NULL
            OR exp.amount IS NOT NULL
          )
    )
    SELECT 
        s.id AS staff_id,
        s.name,
        s.role,
        COALESCE(s.avatar, '') AS avatar,
        s.status,
        CASE 
            WHEN COALESCE(pd.is_paid, FALSE) = TRUE THEN 0.0
            ELSE GREATEST(0.0, COALESCE(s.salary, 0.0) - COALESCE((
                SELECT SUM(sa.remaining_amount) 
                FROM public.salary_advance_ledger sa 
                WHERE sa.staff_id = s.id 
                  AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
                  AND (
                    trim(lower(sa.salary_month)) = trim(lower(v_month_str))
                    OR (
                      (sa.salary_month IS NULL OR sa.salary_month = '') 
                      AND to_char(sa.given_date, 'FMMonth YYYY') = trim(v_month_str)
                    )
                  )
            ), 0.0))
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


-- 2. UPDATE FUNCTION: get_staff_pending_salary
DROP FUNCTION IF EXISTS public.get_staff_pending_salary(UUID);

CREATE OR REPLACE FUNCTION public.get_staff_pending_salary(p_staff_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_curr_month TEXT := to_char(CURRENT_DATE, 'FMMonth YYYY');
    v_curr_mon_short TEXT := to_char(CURRENT_DATE, 'Mon YYYY');
    v_base_salary NUMERIC(12,2) := 0.0;
    v_is_paid BOOLEAN := FALSE;
    s_name TEXT;
    v_advances_deduction NUMERIC(12,2) := 0.0;
    v_gym_id UUID;
BEGIN
    SELECT name, gym_id, COALESCE(salary, 0.0) INTO s_name, v_gym_id, v_base_salary
    FROM public.staff
    WHERE id = p_staff_id;

    IF s_name IS NULL THEN
        RETURN 0.0;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.salary_drafts
        WHERE staff_id = p_staff_id
          AND (
            trim(lower(salary_month)) = trim(lower(v_curr_month))
            OR trim(lower(salary_month)) = trim(lower(v_curr_mon_short))
          )
          AND (lower(status::TEXT) = 'paid' OR paid_transaction_id IS NOT NULL)
    ) OR EXISTS (
        SELECT 1 FROM public.transactions t
        WHERE t.gym_id = v_gym_id
          AND (t.category ILIKE '%Salaries%' OR t.category ILIKE '%Salary%' OR t.title ILIKE '%Salary%')
          AND t.title ILIKE '%' || s_name || '%'
          AND (to_char(t.date, 'FMMonth YYYY') = trim(v_curr_month) OR to_char(t.date, 'Mon YYYY') = trim(v_curr_mon_short))
    ) OR EXISTS (
        SELECT 1 FROM public.expenses e
        WHERE e.gym_id = v_gym_id
          AND (e.category ILIKE '%Salaries%' OR e.category ILIKE '%Salary%' OR e.title ILIKE '%Salary%')
          AND e.title ILIKE '%' || s_name || '%'
          AND (to_char(e.date, 'FMMonth YYYY') = trim(v_curr_month) OR to_char(e.date, 'Mon YYYY') = trim(v_curr_mon_short))
    ) THEN
        v_is_paid := TRUE;
    END IF;

    IF v_is_paid THEN
        RETURN 0.0;
    END IF;

    -- Calculate pending advance deduction
    SELECT COALESCE(SUM(sa.remaining_amount), 0.0)
    INTO v_advances_deduction
    FROM public.salary_advance_ledger sa
    WHERE sa.staff_id = p_staff_id
      AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
      AND (
        trim(lower(sa.salary_month)) = trim(lower(v_curr_month))
        OR (
          (sa.salary_month IS NULL OR sa.salary_month = '')
          AND to_char(sa.given_date, 'FMMonth YYYY') = trim(v_curr_month)
        )
      );

    RETURN GREATEST(0.0, v_base_salary - v_advances_deduction);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_staff_pending_salary(UUID) TO anon, authenticated, service_role;


-- 3. UPDATE FUNCTION: get_staff_pending_salary_for_month
DROP FUNCTION IF EXISTS public.get_staff_pending_salary_for_month(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.get_staff_pending_salary_for_month(p_staff_id UUID, p_salary_month TEXT)
RETURNS NUMERIC AS $$
DECLARE
    v_base_salary NUMERIC(12,2) := 0.0;
    v_is_paid BOOLEAN := FALSE;
    s_name TEXT;
    v_gym_id UUID;
    v_advances_deduction NUMERIC(12,2) := 0.0;
BEGIN
    SELECT name, gym_id, COALESCE(salary, 0.0) INTO s_name, v_gym_id, v_base_salary
    FROM public.staff
    WHERE id = p_staff_id;

    IF s_name IS NULL THEN
        RETURN 0.0;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.salary_drafts
        WHERE staff_id = p_staff_id
          AND trim(lower(salary_month)) = trim(lower(p_salary_month))
          AND (lower(status::TEXT) = 'paid' OR paid_transaction_id IS NOT NULL)
    ) OR EXISTS (
        SELECT 1 FROM public.transactions t
        WHERE t.gym_id = v_gym_id
          AND (t.category ILIKE '%Salaries%' OR t.category ILIKE '%Salary%' OR t.title ILIKE '%Salary%')
          AND t.title ILIKE '%' || s_name || '%'
          AND to_char(t.date, 'FMMonth YYYY') = trim(p_salary_month)
    ) OR EXISTS (
        SELECT 1 FROM public.expenses e
        WHERE e.gym_id = v_gym_id
          AND (e.category ILIKE '%Salaries%' OR e.category ILIKE '%Salary%' OR e.title ILIKE '%Salary%')
          AND e.title ILIKE '%' || s_name || '%'
          AND to_char(e.date, 'FMMonth YYYY') = trim(p_salary_month)
    ) THEN
        v_is_paid := TRUE;
    END IF;

    IF v_is_paid THEN
        RETURN 0.0;
    END IF;

    SELECT COALESCE(SUM(sa.remaining_amount), 0.0)
    INTO v_advances_deduction
    FROM public.salary_advance_ledger sa
    WHERE sa.staff_id = p_staff_id
      AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
      AND (
        trim(lower(sa.salary_month)) = trim(lower(p_salary_month))
        OR (
          (sa.salary_month IS NULL OR sa.salary_month = '')
          AND to_char(sa.given_date, 'FMMonth YYYY') = trim(p_salary_month)
        )
      );

    RETURN GREATEST(0.0, v_base_salary - v_advances_deduction);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_staff_pending_salary_for_month(UUID, TEXT) TO anon, authenticated, service_role;


-- 4. UPDATE FUNCTION: get_paid_salary_draft_details (Supports both UUID and TEXT ID)
DROP FUNCTION IF EXISTS public.get_paid_salary_draft_details(UUID);
DROP FUNCTION IF EXISTS public.get_paid_salary_draft_details(TEXT);

CREATE OR REPLACE FUNCTION public.get_paid_salary_draft_details(
    p_draft_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_draft RECORD;
    v_commissions JSONB := '[]'::JSONB;
    v_advances JSONB := '[]'::JSONB;
    v_adjustments JSONB := '[]'::JSONB;
    v_tx RECORD;
    v_real_uuid UUID;
    v_comm_sum NUMERIC := 0.0;
    v_adv_sum NUMERIC := 0.0;
    v_gross NUMERIC := 0.0;
BEGIN
    BEGIN
        v_real_uuid := p_draft_id::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_real_uuid := NULL;
    END;

    IF v_real_uuid IS NOT NULL THEN
        SELECT id, gym_id, staff_id, salary_month, base_salary, commission_amount, advance_deduction, other_additions, other_deductions, net_salary, gross_salary, status, created_at, paid_transaction_id
        INTO v_draft
        FROM public.salary_drafts
        WHERE id = v_real_uuid;
    END IF;

    IF v_draft.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'Salary draft not found'
        );
    END IF;

    IF v_draft.paid_transaction_id IS NOT NULL THEN
        SELECT payment_mode, date INTO v_tx FROM public.transactions WHERE id = v_draft.paid_transaction_id;
    END IF;

    -- Commissions
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'created_at', to_char(created_at AT TIME ZONE 'Asia/Kolkata', 'dd MMM yyyy'),
        'payment_id', payment_id,
        'payment_received', payment_received,
        'commission_rate', commission_rate,
        'amount', amount
    ) ORDER BY created_at ASC), '[]'::JSONB),
    COALESCE(SUM(amount), 0.0)
    INTO v_commissions, v_comm_sum
    FROM public.commission_ledger
    WHERE salary_payment_id = v_draft.id
       OR (staff_id = v_draft.staff_id AND trim(lower(salary_month)) = trim(lower(v_draft.salary_month)) AND status = 'Paid');

    -- Advances
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'given_date', to_char(given_date, 'dd MMM yyyy'),
        'reason', reason,
        'advance_amount', advance_amount,
        'recovered_amount', recovered_amount,
        'remaining_amount', remaining_amount,
        'status', status
    ) ORDER BY given_date ASC), '[]'::JSONB),
    COALESCE(SUM(recovered_amount), 0.0)
    INTO v_advances, v_adv_sum
    FROM public.salary_advance_ledger
    WHERE salary_payment_id = v_draft.id
       OR (
          staff_id = v_draft.staff_id 
          AND status = 'Recovered'::public.advance_status
          AND (
            trim(lower(salary_month)) = trim(lower(v_draft.salary_month))
            OR to_char(given_date, 'FMMonth YYYY') = trim(v_draft.salary_month)
          )
       );

    -- Adjustments
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'reason', reason,
        'amount', amount,
        'type', type
    ) ORDER BY created_at ASC), '[]'::JSONB)
    INTO v_adjustments
    FROM public.salary_adjustments
    WHERE salary_draft_id = v_draft.id;

    -- Compute final gross: Base + Commission + Additions - Deductions
    v_gross := GREATEST(
        COALESCE(v_draft.gross_salary, 0.0),
        COALESCE(v_draft.base_salary, 0.0) + GREATEST(COALESCE(v_draft.commission_amount, 0.0), v_comm_sum) + COALESCE(v_draft.other_additions, 0.0) - COALESCE(v_draft.other_deductions, 0.0),
        COALESCE(v_draft.net_salary, 0.0) + GREATEST(COALESCE(v_draft.advance_deduction, 0.0), v_adv_sum)
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'draft_id', v_draft.id,
        'gym_id', v_draft.gym_id,
        'staff_id', v_draft.staff_id,
        'salary_month', v_draft.salary_month,
        'base_salary', v_draft.base_salary,
        'commission_amount', GREATEST(COALESCE(v_draft.commission_amount, 0.0), v_comm_sum),
        'advance_deduction', GREATEST(COALESCE(v_draft.advance_deduction, 0.0), v_adv_sum),
        'other_additions', v_draft.other_additions,
        'other_deductions', v_draft.other_deductions,
        'net_salary', v_draft.net_salary,
        'gross_salary', v_gross,
        'paid_on', to_char(v_draft.created_at AT TIME ZONE 'Asia/Kolkata', 'dd MMM yyyy'),
        'payment_mode', COALESCE(v_tx.payment_mode::TEXT, 'UPI'),
        'commissions', v_commissions,
        'advances', v_advances,
        'adjustments', v_adjustments
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_paid_salary_draft_details(TEXT) TO anon, authenticated, service_role;
