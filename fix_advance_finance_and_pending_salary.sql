-- =========================================================================
-- DATABASE PATCH: fix_advance_finance_and_pending_salary.sql
-- Run this script in your Supabase SQL Editor to sync salary advances
-- with finance_transactions and fix all pending salary calculations.
-- =========================================================================

-- 1. UPDATE FUNCTION: fn_on_advance_ledger_created
-- Direct integration to finance_transactions (category: 'Salary', type: 'Expense')
CREATE OR REPLACE FUNCTION public.fn_on_advance_ledger_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
    v_pay_method TEXT := 'Cash';
BEGIN
    IF (NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status)) AND 
       (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('Approved'::public.advance_status, 'Given'::public.advance_status))) THEN
       
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Safe insert into public.expenses (legacy support)
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'expenses') THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.expenses 
                WHERE gym_id = NEW.gym_id 
                  AND category = 'Salary Advance' 
                  AND amount = NEW.advance_amount 
                  AND date = NEW.given_date 
                  AND title LIKE '%' || COALESCE(s_name, 'Staff') || '%'
            ) THEN
                INSERT INTO public.expenses (
                    gym_id,
                    title,
                    amount,
                    category,
                    date,
                    notes
                ) VALUES (
                    NEW.gym_id,
                    'Staff Salary Advance - ' || COALESCE(s_name, 'Staff'),
                    NEW.advance_amount,
                    'Salary Advance',
                    NEW.given_date,
                    COALESCE(NEW.reason, NEW.notes, 'Staff Advance Payment Approved')
                );
            END IF;
        END IF;

        -- Direct insert into public.finance_transactions (modern accounting ledger)
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'finance_transactions') THEN
            IF NOT EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = NEW.id::TEXT) THEN
                -- Match payment method enum check constraints
                v_pay_method := COALESCE(NEW.payment_method, 'Cash');
                IF v_pay_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
                    v_pay_method := 'Other';
                END IF;

                INSERT INTO public.finance_transactions (
                    gym_id,
                    amount,
                    type,
                    category,
                    payment_method,
                    transaction_date,
                    expense_date,
                    entry_date,
                    reference_id,
                    notes
                ) VALUES (
                    NEW.gym_id,
                    NEW.advance_amount,
                    'Expense',
                    'Salary', -- Check constraint: Salary
                    v_pay_method,
                    NEW.given_date::TIMESTAMPTZ, -- Logs on the exact date of advance
                    NEW.given_date,
                    NEW.given_date,
                    NEW.id::TEXT,
                    'Staff Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || NEW.reason || ')', '')
                );
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on salary_advance_ledger
DROP TRIGGER IF EXISTS trg_on_advance_ledger_created ON public.salary_advance_ledger;
CREATE TRIGGER trg_on_advance_ledger_created
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_ledger_created();


-- 2. UPDATE FUNCTION: get_staff_pending_salary
-- Deducts active salary advances of the current month
CREATE OR REPLACE FUNCTION public.get_staff_pending_salary(p_staff_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_curr_month TEXT := to_char(CURRENT_DATE, 'FMMonth YYYY');
    v_base_salary NUMERIC(12,2) := 0.0;
    v_is_paid BOOLEAN := FALSE;
    v_advance_deduction NUMERIC(12,2) := 0.0;
    s_name TEXT;
    v_gym_id UUID;
BEGIN
    SELECT name, COALESCE(salary, 0.0), gym_id INTO s_name, v_base_salary, v_gym_id
    FROM public.staff
    WHERE id = p_staff_id;

    IF s_name IS NULL THEN
        RETURN 0.0;
    END IF;

    -- Check if paid in salary_drafts
    IF EXISTS (
        SELECT 1 FROM public.salary_drafts
        WHERE staff_id = p_staff_id
          AND trim(salary_month) = trim(v_curr_month)
          AND status = 'Paid'::public.draft_status
    ) OR EXISTS (
        SELECT 1 FROM public.expenses
        WHERE gym_id = v_gym_id
          AND category = 'Salaries'
          AND title LIKE '%' || s_name || '%'
          AND to_char(date, 'FMMonth YYYY') = trim(v_curr_month)
    ) OR EXISTS (
        SELECT 1 FROM public.transactions
        WHERE gym_id = v_gym_id
          AND category = 'Salaries'
          AND type = 'Expense'
          AND title LIKE '%' || s_name || '%'
          AND to_char(date, 'FMMonth YYYY') = trim(v_curr_month)
    ) OR EXISTS (
        SELECT 1 FROM public.finance_transactions
        WHERE gym_id = v_gym_id
          AND category = 'Salary'
          AND type = 'Expense'
          AND title LIKE '%' || s_name || '%'
          AND to_char(transaction_date, 'FMMonth YYYY') = trim(v_curr_month)
    ) THEN
        v_is_paid := TRUE;
    END IF;

    IF v_is_paid THEN
        RETURN 0.0;
    ELSE
        -- Sum remaining amount of active advances assigned to this month
        SELECT COALESCE(SUM(sa.remaining_amount), 0.0) INTO v_advance_deduction
        FROM public.salary_advance_ledger sa 
        WHERE sa.staff_id = p_staff_id 
          AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
          AND (
            trim(sa.salary_month) = trim(v_curr_month)
            OR (
              (sa.salary_month IS NULL OR sa.salary_month = '') 
              AND to_char(sa.given_date, 'FMMonth YYYY') = trim(v_curr_month)
            )
          );

        RETURN GREATEST(0.0, v_base_salary - v_advance_deduction);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_staff_pending_salary(UUID) TO anon, authenticated, service_role;


-- 3. UPDATE FUNCTION: get_total_salary_due
-- Deducts active salary advances of the current month from active unpaid staff total
CREATE OR REPLACE FUNCTION public.get_total_salary_due(p_gym_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_month_str TEXT := to_char(CURRENT_DATE, 'FMMonth YYYY');
    v_total_due NUMERIC(12,2) := 0.0;
    v_total_advances NUMERIC(12,2) := 0.0;
BEGIN
    -- Sum base salaries of unpaid active staff
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

    -- Sum remaining amount of active advances of these unpaid staff
    SELECT COALESCE(SUM(sa.remaining_amount), 0.0) INTO v_total_advances
    FROM public.salary_advance_ledger sa
    JOIN public.staff s ON sa.staff_id = s.id
    WHERE s.gym_id = p_gym_id
      AND s.status = 'Active'
      AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
      AND (
        trim(sa.salary_month) = trim(v_month_str)
        OR (
          (sa.salary_month IS NULL OR sa.salary_month = '') 
          AND to_char(sa.given_date, 'FMMonth YYYY') = trim(v_month_str)
        )
      )
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

    RETURN GREATEST(0.0, v_total_due - v_total_advances);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_total_salary_due(UUID) TO anon, authenticated, service_role;


-- 4. UPDATE FUNCTION: get_owner_staff_cards_v1
-- Deducts active salary advances from the salary_pending field
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
            ELSE GREATEST(0.0, COALESCE(s.salary, 0.0) - COALESCE((
                SELECT SUM(sa.remaining_amount) 
                FROM public.salary_advance_ledger sa 
                WHERE sa.staff_id = s.id 
                  AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
                  AND (
                    trim(sa.salary_month) = trim(v_month_str)
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


-- 5. BACKFILL: Sync existing historical advances to finance_transactions (if not synced)
DO $$
DECLARE
    r_adv RECORD;
    s_name TEXT;
    v_pay_method TEXT;
BEGIN
    FOR r_adv IN 
        SELECT * FROM public.salary_advance_ledger 
        WHERE status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Recovered'::public.advance_status)
    LOOP
        -- If transaction doesn't exist for this advance, backfill it using the exact given_date
        IF NOT EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = r_adv.id::TEXT) THEN
            SELECT name INTO s_name FROM public.staff WHERE id = r_adv.staff_id;
            
            v_pay_method := COALESCE(r_adv.payment_method, 'Cash');
            IF v_pay_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
                v_pay_method := 'Other';
            END IF;

            INSERT INTO public.finance_transactions (
                gym_id,
                amount,
                type,
                category,
                payment_method,
                transaction_date,
                expense_date,
                entry_date,
                reference_id,
                notes
            ) VALUES (
                r_adv.gym_id,
                r_adv.advance_amount,
                'Expense',
                'Salary',
                v_pay_method,
                r_adv.given_date::TIMESTAMPTZ, -- Logs on the exact date of advance
                r_adv.given_date,
                r_adv.given_date,
                r_adv.id::TEXT,
                'Staff Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || r_adv.reason || ')', '')
            );
        END IF;
    END LOOP;
END
$$;
