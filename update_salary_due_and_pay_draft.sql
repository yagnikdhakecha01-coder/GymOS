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
      )
      AND NOT EXISTS (
          SELECT 1 FROM public.expenses e
          WHERE e.gym_id = p_gym_id
            AND e.category = 'Salaries'
            AND e.title LIKE '%Salary Payment%'
            AND to_char(e.date, 'FMMonth YYYY') = trim(v_month_str)
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
            s.id AS s_id,
            TRUE AS is_paid,
            COALESCE(sd.net_salary, s.salary, 0.0) AS amount
        FROM public.staff s
        LEFT JOIN public.salary_drafts sd
               ON sd.staff_id = s.id
              AND trim(sd.salary_month) = trim(v_month_str)
              AND sd.status = 'Paid'::public.draft_status
        WHERE s.gym_id = p_gym_id
          AND (
            sd.id IS NOT NULL OR EXISTS (
                SELECT 1 FROM public.expenses e
                WHERE e.gym_id = p_gym_id
                  AND e.category = 'Salaries'
                  AND e.title LIKE '%' || s.name || '%'
                  AND to_char(e.date, 'FMMonth YYYY') = trim(v_month_str)
            )
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


-- 3. AUTOMATIC NEXT-MONTH ADVANCE ASSIGNMENT TRIGGER FUNCTION
-- If current month salary has already been paid for this staff, any advance taken in this month gets assigned to next month!
CREATE OR REPLACE FUNCTION public.fn_assign_advance_salary_month()
RETURNS TRIGGER AS $$
DECLARE
    v_curr_month TEXT;
    v_next_month TEXT;
    v_is_curr_paid BOOLEAN := FALSE;
BEGIN
    v_curr_month := to_char(COALESCE(NEW.given_date, CURRENT_DATE), 'FMMonth YYYY');
    v_next_month := to_char(COALESCE(NEW.given_date, CURRENT_DATE) + INTERVAL '1 month', 'FMMonth YYYY');

    -- Check if current month salary is paid
    IF EXISTS (
        SELECT 1 FROM public.salary_drafts 
        WHERE staff_id = NEW.staff_id 
          AND trim(salary_month) = trim(v_curr_month) 
          AND status = 'Paid'::public.draft_status
    ) OR EXISTS (
        SELECT 1 FROM public.expenses 
        WHERE category = 'Salaries' 
          AND title LIKE '%Salary Payment%' 
          AND to_char(date, 'FMMonth YYYY') = trim(v_curr_month)
    ) THEN
        v_is_curr_paid := TRUE;
    END IF;

    IF v_is_curr_paid THEN
        NEW.salary_month := v_next_month;
    ELSE
        IF NEW.salary_month IS NULL OR NEW.salary_month = '' THEN
            NEW.salary_month := v_curr_month;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_assign_advance_salary_month ON public.salary_advance_ledger;
CREATE TRIGGER trg_assign_advance_salary_month
BEFORE INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW
EXECUTE FUNCTION public.fn_assign_advance_salary_month();


-- 4. FIX RPC: get_or_create_salary_draft
CREATE OR REPLACE FUNCTION public.get_or_create_salary_draft(
    p_gym_id UUID,
    p_staff_id UUID,
    p_salary_month TEXT
)
RETURNS TABLE (
    id UUID,
    gym_id UUID,
    staff_id UUID,
    salary_month TEXT,
    base_salary NUMERIC,
    commission_amount NUMERIC,
    advance_deduction NUMERIC,
    other_additions NUMERIC,
    other_deductions NUMERIC,
    net_salary NUMERIC,
    status public.draft_status,
    created_at TIMESTAMPTZ
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_draft_id UUID;
    v_base_salary NUMERIC(12,2) := 0.0;
    v_is_paid BOOLEAN := FALSE;
    s_name TEXT;
BEGIN
    SELECT name INTO s_name FROM public.staff WHERE id = p_staff_id;

    -- Check if draft already exists
    SELECT sd.id, (sd.status = 'Paid'::public.draft_status) INTO v_draft_id, v_is_paid
    FROM public.salary_drafts sd
    WHERE sd.gym_id = p_gym_id 
      AND sd.staff_id = p_staff_id 
      AND trim(sd.salary_month) = trim(p_salary_month);

    -- Check if salary payment exists in expenses
    IF NOT v_is_paid AND EXISTS (
        SELECT 1 FROM public.expenses 
        WHERE gym_id = p_gym_id 
          AND category = 'Salaries' 
          AND (title LIKE '%Salary Payment%' OR (s_name IS NOT NULL AND title LIKE '%' || s_name || '%'))
          AND to_char(date, 'FMMonth YYYY') = trim(p_salary_month)
    ) THEN
        v_is_paid := TRUE;
    END IF;

    IF v_draft_id IS NOT NULL THEN
        IF v_is_paid THEN
            UPDATE public.salary_drafts 
            SET status = 'Paid'::public.draft_status 
            WHERE id = v_draft_id AND status <> 'Paid'::public.draft_status;
        END IF;
    ELSE
        SELECT COALESCE(salary, 0.0) INTO v_base_salary
        FROM public.staff
        WHERE id = p_staff_id;

        INSERT INTO public.salary_drafts (
            gym_id,
            staff_id,
            salary_month,
            base_salary,
            net_salary,
            status
        ) VALUES (
            p_gym_id,
            p_staff_id,
            p_salary_month,
            v_base_salary,
            v_base_salary,
            CASE WHEN v_is_paid THEN 'Paid'::public.draft_status ELSE 'Draft'::public.draft_status END
        )
        RETURNING id INTO v_draft_id;
    END IF;

    RETURN QUERY
    SELECT 
        sd.id,
        sd.gym_id,
        sd.staff_id,
        sd.salary_month,
        sd.base_salary,
        sd.commission_amount,
        sd.advance_deduction,
        sd.other_additions,
        sd.other_deductions,
        sd.net_salary,
        sd.status,
        sd.created_at
    FROM public.salary_drafts sd
    WHERE sd.id = v_draft_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_salary_draft(UUID, UUID, TEXT) TO anon, authenticated, service_role;


-- 5. FIX SALARY DRAFT TOTALS CALCULATOR TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    IF NEW.status = 'Paid'::public.draft_status OR (TG_OP = 'UPDATE' AND OLD.status = 'Paid'::public.draft_status) THEN
        RETURN NEW;
    END IF;

    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    -- Only include advances whose salary_month matches this draft's month
    SELECT COALESCE(SUM(remaining_amount), 0.0) INTO adv_total 
    FROM public.salary_advance_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
      AND (
        trim(salary_month) = trim(NEW.salary_month)
        OR (
          (salary_month IS NULL OR salary_month = '') 
          AND to_char(given_date, 'FMMonth YYYY') = trim(NEW.salary_month)
        )
      );

    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;

    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    NEW.net_salary := GREATEST(0.0, (NEW.base_salary + comm_total + adj_add) - (adv_total + adj_ded));

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;
CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW
EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();


-- 6. FIX RPC: pay_salary_draft
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
    SELECT gym_id, staff_id, net_salary, advance_deduction, salary_month
    INTO v_gym_id, v_staff_id, v_net_salary, v_advance_deduction, v_salary_month
    FROM public.salary_drafts
    WHERE id = p_draft_id AND status <> 'Paid'::public.draft_status;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT name INTO s_name FROM public.staff WHERE id = v_staff_id;

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

    UPDATE public.commission_ledger
    SET status = 'Paid'::public.commission_status,
        paid_at = NOW()
    WHERE staff_id = v_staff_id AND status = 'Pending'::public.commission_status;

    v_to_recover := COALESCE(v_advance_deduction, 0.0);
    IF v_to_recover > 0 THEN
        FOR r_advance IN 
            SELECT id, remaining_amount, recovered_amount, advance_amount
            FROM public.salary_advance_ledger
            WHERE staff_id = v_staff_id 
              AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
              AND (
                trim(salary_month) = trim(v_salary_month)
                OR (
                  (salary_month IS NULL OR salary_month = '') 
                  AND to_char(given_date, 'FMMonth YYYY') = trim(v_salary_month)
                )
              )
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

    UPDATE public.salary_drafts
    SET status = 'Paid'::public.draft_status,
        paid_transaction_id = v_tx_id,
        created_at = NOW()
    WHERE id = p_draft_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.pay_salary_draft(UUID, TEXT, TEXT) TO anon, authenticated, service_role;
