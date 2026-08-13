-- RUN STEP 3 OPTIONAL SALARY


-- -------------------------------------------------------------------------
-- PART F: SALARY â€” same pending payable formula as Pay Salary screen
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_staff_net_payable(
    p_staff_id UUID,
    p_salary_month TEXT
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_month TEXT := trim(COALESCE(p_salary_month, to_char(CURRENT_DATE, 'FMMonth YYYY')));
    v_base NUMERIC(12,2) := 0;
    v_commission NUMERIC(12,2) := 0;
    v_advances NUMERIC(12,2) := 0;
    v_additions NUMERIC(12,2) := 0;
    v_deductions NUMERIC(12,2) := 0;
    v_draft_id UUID;
    v_gym_id UUID;
    s_name TEXT;
BEGIN
    SELECT COALESCE(s.salary, 0), s.gym_id, s.name
    INTO v_base, v_gym_id, s_name
    FROM public.staff s WHERE s.id = p_staff_id;
    IF s_name IS NULL THEN RETURN 0; END IF;

    IF EXISTS (
        SELECT 1 FROM public.salary_drafts sd
        WHERE sd.staff_id = p_staff_id AND trim(sd.salary_month) = v_month
          AND sd.status = 'Paid'::public.draft_status
    ) OR EXISTS (
        SELECT 1 FROM public.expenses e
        WHERE e.gym_id = v_gym_id AND e.category = 'Salaries'
          AND e.title LIKE '%' || s_name || '%'
          AND to_char(e.date, 'FMMonth YYYY') = v_month
    ) OR EXISTS (
        SELECT 1 FROM public.finance_transactions ft
        WHERE ft.gym_id = v_gym_id AND ft.category = 'Salary' AND ft.type = 'Expense'
          AND ft.title LIKE '%' || s_name || '%'
          AND to_char(ft.transaction_date, 'FMMonth YYYY') = v_month
          AND ft.notes NOT ILIKE '%advance%'
    ) THEN RETURN 0; END IF;

    SELECT sd.id INTO v_draft_id FROM public.salary_drafts sd
    WHERE sd.staff_id = p_staff_id AND trim(sd.salary_month) = v_month LIMIT 1;

    SELECT COALESCE(SUM(cl.amount), 0) INTO v_commission
    FROM public.commission_ledger cl
    WHERE cl.staff_id = p_staff_id AND cl.status = 'Pending'::public.commission_status;

    SELECT COALESCE(SUM(sa.remaining_amount), 0) INTO v_advances
    FROM public.salary_advance_ledger sa
    WHERE sa.staff_id = p_staff_id
      AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
      AND (trim(sa.salary_month) = v_month OR (
          (sa.salary_month IS NULL OR sa.salary_month = '')
          AND to_char(sa.given_date, 'FMMonth YYYY') = v_month
      ));

    IF v_draft_id IS NOT NULL THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_additions FROM public.salary_adjustments
        WHERE salary_draft_id = v_draft_id AND type = 'Addition'::public.adjustment_type;
        SELECT COALESCE(SUM(amount), 0) INTO v_deductions FROM public.salary_adjustments
        WHERE salary_draft_id = v_draft_id AND type = 'Deduction'::public.adjustment_type;
    END IF;

    RETURN GREATEST(0, (v_base + v_commission + v_additions - v_deductions) - v_advances);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_staff_net_payable(UUID, TEXT) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_staff_pending_salary(p_staff_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN RETURN public.fn_staff_net_payable(p_staff_id, to_char(CURRENT_DATE, 'FMMonth YYYY')); END; $$;
GRANT EXECUTE ON FUNCTION public.get_staff_pending_salary(UUID) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_staff_pending_salary_for_month(p_staff_id UUID, p_salary_month TEXT)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN RETURN public.fn_staff_net_payable(p_staff_id, p_salary_month); END; $$;
GRANT EXECUTE ON FUNCTION public.get_staff_pending_salary_for_month(UUID, TEXT) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_total_salary_due(p_gym_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_month TEXT := to_char(CURRENT_DATE, 'FMMonth YYYY'); v_total NUMERIC(12,2) := 0; r RECORD;
BEGIN
    FOR r IN SELECT id FROM public.staff WHERE gym_id = p_gym_id AND status = 'Active'
    LOOP v_total := v_total + public.fn_staff_net_payable(r.id, v_month); END LOOP;
    RETURN GREATEST(0, v_total);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_total_salary_due(UUID) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_gym_member_pending_total(p_gym_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    RETURN COALESCE((SELECT SUM(GREATEST(0, m.pending_amount)) FROM public.members m
        WHERE m.gym_id = p_gym_id AND COALESCE(m.pending_amount, 0) > 0), 0);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_gym_member_pending_total(UUID) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reconcile_member_pending_amounts(p_gym_id UUID DEFAULT NULL)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count INTEGER := 0;
BEGIN
    UPDATE public.members m SET
        total_received_amount = COALESCE(sub.received, m.total_received_amount),
        pending_amount = GREATEST(0, COALESCE(sub.total_due, 0) - COALESCE(sub.received, 0)),
        payment_status = CASE
            WHEN GREATEST(0, COALESCE(sub.total_due, 0) - COALESCE(sub.received, 0)) <= 0 THEN 'Paid'
            WHEN COALESCE(sub.received, 0) > 0 THEN 'Partial'
            ELSE 'Pending'
        END
    FROM (
        SELECT mm.member_id,
            COALESCE(SUM(mm.total_amount), 0) AS total_due,
            COALESCE(SUM(mm.paid_amount), 0) AS received
        FROM public.member_memberships mm GROUP BY mm.member_id
    ) sub
    WHERE m.id = sub.member_id AND (p_gym_id IS NULL OR m.gym_id = p_gym_id);
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END; $$;
GRANT EXECUTE ON FUNCTION public.reconcile_member_pending_amounts(UUID) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_owner_staff_cards_v1(p_gym_id UUID, p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    staff_id UUID, name TEXT, role TEXT, avatar TEXT, status TEXT,
    salary_pending NUMERIC, present_days INT, leave_days INT, early_exit_count INT,
    last_check_in TEXT, is_checked_in BOOLEAN, current_date_str TEXT,
    is_salary_paid BOOLEAN, paid_amount NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_start_of_month DATE := date_trunc('month', p_date)::DATE;
        v_month_str TEXT := to_char(p_date, 'FMMonth YYYY');
BEGIN
    RETURN QUERY
    WITH monthly_attendance AS (
        SELECT s.id AS s_id,
            COUNT(DISTINCT al.check_in::DATE)::INT AS month_present,
            COUNT(DISTINCT CASE WHEN al.status IN ('Leave', 'Half Leave', 'On Leave') THEN al.check_in::DATE END)::INT AS month_leave,
            COUNT(CASE WHEN al.status = 'Early Exit' OR COALESCE(al.early_exit_minutes, 0) > 0 THEN 1 END)::INT AS month_early_exit
        FROM public.staff s
        LEFT JOIN public.attendance_logs al ON (al.user_id = s.user_id OR al.user_id = s.id)
            AND al.gym_id = p_gym_id AND al.user_type = 'Staff'
            AND al.status IN ('Present', 'Late', 'Half Day', 'Overtime', 'Early Exit')
            AND al.check_in::DATE >= v_start_of_month AND al.check_in::DATE <= p_date
        WHERE s.gym_id = p_gym_id GROUP BY s.id
    ),
    today_attendance AS (
        SELECT DISTINCT ON (s.id) s.id AS s_id, al.check_in, al.check_out, (al.check_out IS NULL) AS checked_in
        FROM public.staff s
        JOIN public.attendance_logs al ON (al.user_id = s.user_id OR al.user_id = s.id)
            AND al.gym_id = p_gym_id AND al.user_type = 'Staff' AND al.check_in::DATE = p_date
        WHERE s.gym_id = p_gym_id ORDER BY s.id, al.check_in DESC
    ),
    paid_drafts AS (
        SELECT s.id AS s_id, TRUE AS is_paid, COALESCE(sd.net_salary, s.salary, 0.0) AS amount
        FROM public.staff s
        LEFT JOIN public.salary_drafts sd ON sd.staff_id = s.id
            AND trim(sd.salary_month) = trim(v_month_str) AND sd.status = 'Paid'::public.draft_status
        WHERE s.gym_id = p_gym_id AND (
            sd.id IS NOT NULL OR EXISTS (
                SELECT 1 FROM public.expenses e WHERE e.gym_id = p_gym_id AND e.category = 'Salaries'
                    AND e.title LIKE '%' || s.name || '%' AND to_char(e.date, 'FMMonth YYYY') = trim(v_month_str)
            )
        )
    )
    SELECT s.id, s.name, s.role, COALESCE(s.avatar, ''), s.status,
        CASE WHEN COALESCE(pd.is_paid, FALSE) THEN 0.0 ELSE public.fn_staff_net_payable(s.id, v_month_str) END,
        COALESCE(ma.month_present, 0)::INT, COALESCE(ma.month_leave, 0)::INT, COALESCE(ma.month_early_exit, 0)::INT,
        CASE WHEN ta.check_in IS NOT NULL THEN to_char(ta.check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') ELSE 'N/A' END,
        COALESCE(ta.checked_in, FALSE), to_char(p_date, 'DD Mon YYYY'),
        COALESCE(pd.is_paid, FALSE), COALESCE(pd.amount, 0.0)::NUMERIC
    FROM public.staff s
    LEFT JOIN monthly_attendance ma ON s.id = ma.s_id
    LEFT JOIN today_attendance ta ON s.id = ta.s_id
    LEFT JOIN paid_drafts pd ON s.id = pd.s_id
    WHERE s.gym_id = p_gym_id ORDER BY s.created_at DESC;
END; $$;
GRANT EXECUTE ON FUNCTION public.get_owner_staff_cards_v1(UUID, DATE) TO anon, authenticated, service_role;

-- One-time reconcile (safe to re-run)
SELECT public.reconcile_member_pending_amounts(NULL);
