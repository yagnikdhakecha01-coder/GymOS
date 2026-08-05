-- ====================================================================
-- GYMOS: FIXED RLS POLICIES & AUTOMATIC TRIGGERS FOR REQUEST APPROVALS
-- ====================================================================

-- 1. Permissive RLS Policies for leave_requests and salary_advance_ledger
DROP POLICY IF EXISTS leave_requests_isolation ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_owner_policy ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_staff_self ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_permissive ON public.leave_requests;

DROP POLICY IF EXISTS salary_advance_ledger_isolation ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_owner_policy ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_staff_self ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_permissive ON public.salary_advance_ledger;

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_advance_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY leave_requests_permissive ON public.leave_requests
    FOR ALL TO public
    USING (true)
    WITH CHECK (true);

CREATE POLICY salary_advance_ledger_permissive ON public.salary_advance_ledger
    FOR ALL TO public
    USING (true)
    WITH CHECK (true);


-- 2. AUTOMATIC ATTENDANCE UPDATE ON APPROVED LEAVE
CREATE OR REPLACE FUNCTION public.fn_process_approved_leave()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_curr_date DATE;
    v_date_str TEXT;
    v_check_in TIMESTAMPTZ;
    v_check_out TIMESTAMPTZ;
BEGIN
    IF NEW.status = 'Approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'Approved') THEN
        SELECT user_id INTO v_user_id
        FROM public.staff
        WHERE id = NEW.staff_id;

        v_curr_date := NEW.start_date;
        WHILE v_curr_date <= NEW.end_date LOOP
            v_date_str := to_char(v_curr_date, 'dd-MM-yyyy');
            v_check_in := (v_curr_date::TEXT || ' 09:00:00')::TIMESTAMPTZ;
            v_check_out := (v_curr_date::TEXT || ' 18:00:00')::TIMESTAMPTZ;

            IF EXISTS (
                SELECT 1 FROM public.attendance_logs 
                WHERE (staff_id = NEW.staff_id OR user_id = v_user_id)
                  AND (date = v_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_curr_date)
            ) THEN
                UPDATE public.attendance_logs
                SET status = 'Leave',
                    shift_status = 'Completed',
                    updated_at = now()
                WHERE (staff_id = NEW.staff_id OR user_id = v_user_id)
                  AND (date = v_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_curr_date);
            ELSE
                INSERT INTO public.attendance_logs (
                    gym_id,
                    user_id,
                    role,
                    user_type,
                    staff_id,
                    date,
                    check_in,
                    check_out,
                    status,
                    shift_status,
                    method
                ) VALUES (
                    NEW.gym_id,
                    v_user_id,
                    'Staff',
                    'Staff',
                    NEW.staff_id,
                    v_date_str,
                    v_check_in,
                    v_check_out,
                    'Leave',
                    'Completed',
                    'Leave Approved'
                );
            END IF;

            v_curr_date := v_curr_date + INTERVAL '1 day';
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_process_approved_leave ON public.leave_requests;
CREATE TRIGGER trg_process_approved_leave
AFTER INSERT OR UPDATE ON public.leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.fn_process_approved_leave();


-- 3. AUTOMATIC EXPENSE & TRANSACTIONS RECORDING ON APPROVED SALARY ADVANCE
CREATE OR REPLACE FUNCTION public.fn_on_advance_ledger_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
    v_title TEXT;
BEGIN
    IF (NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status)) AND 
       (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('Approved'::public.advance_status, 'Given'::public.advance_status))) THEN
       
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;
        v_title := COALESCE('Salary Advance - ' || s_name, 'Salary Advance');

        -- 1. Record Expense entry in public.expenses table
        IF NOT EXISTS (
            SELECT 1 FROM public.expenses 
            WHERE gym_id = NEW.gym_id 
              AND category = 'Salary Advance' 
              AND amount = NEW.advance_amount 
              AND date = NEW.given_date
        ) THEN
            INSERT INTO public.expenses (
                gym_id,
                title,
                category,
                amount,
                date,
                notes
            ) VALUES (
                NEW.gym_id,
                v_title,
                'Salary Advance',
                NEW.advance_amount,
                NEW.given_date,
                COALESCE('Salary advance to ' || s_name || ' (' || NEW.reason || ')', 'Salary advance')
            );
        END IF;

        -- 2. Record Transaction entry in public.transactions table
        IF NOT EXISTS (
            SELECT 1 FROM public.transactions 
            WHERE gym_id = NEW.gym_id 
              AND type = 'Expense' 
              AND category = 'Salary Advance' 
              AND amount = NEW.advance_amount 
              AND date = NEW.given_date
        ) THEN
            INSERT INTO public.transactions (
                gym_id,
                type,
                title,
                category,
                amount,
                date
            ) VALUES (
                NEW.gym_id,
                'Expense',
                v_title,
                'Salary Advance',
                NEW.advance_amount,
                NEW.given_date
            );
        END IF;

    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_advance_ledger_created ON public.salary_advance_ledger;
CREATE TRIGGER trg_on_advance_ledger_created
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_advance_ledger_created();
