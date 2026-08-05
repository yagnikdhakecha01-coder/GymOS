-- =========================================================================
-- GYMOS MIGRATION: STAFF LEAVE ATTENDANCE, ADVANCE EXPENSES & ANNOUNCEMENTS
-- =========================================================================

-- 1. ANNOUNCEMENTS TABLE SCHEMA & RLS POLICIES
CREATE TABLE IF NOT EXISTS public.announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    image TEXT,
    audience TEXT NOT NULL DEFAULT 'All Staff', -- 'All Staff', 'All Members', 'Everyone'
    status TEXT NOT NULL DEFAULT 'Sent', -- 'Sent', 'Draft', 'Scheduled'
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_announcements_gym ON public.announcements(gym_id, created_at DESC);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS announcements_isolation_policy ON public.announcements;
CREATE POLICY announcements_isolation_policy ON public.announcements
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

GRANT ALL ON TABLE public.announcements TO anon, authenticated, service_role;


-- 2. AUTOMATIC ATTENDANCE LOG GENERATION ON APPROVED LEAVE
CREATE OR REPLACE FUNCTION public.fn_process_approved_leave()
RETURNS TRIGGER AS $$
DECLARE
    v_curr_date DATE;
    v_date_str TEXT;
    v_user_id UUID;
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
BEGIN
    IF (NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status)) AND 
       (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('Approved'::public.advance_status, 'Given'::public.advance_status))) THEN
       
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Record Expense entry in public.expenses table
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

        -- Record Expense entry in public.transactions table if table exists
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'transactions') THEN
            IF NOT EXISTS (SELECT 1 FROM public.transactions WHERE reference_id = NEW.id) THEN
                INSERT INTO public.transactions (
                    gym_id,
                    type,
                    title,
                    amount,
                    category,
                    date,
                    payment_mode,
                    reference_id
                ) VALUES (
                    NEW.gym_id,
                    'Expense',
                    'Staff Salary Advance - ' || COALESCE(s_name, 'Staff'),
                    NEW.advance_amount,
                    'Salary Advance',
                    NEW.given_date,
                    'Cash',
                    NEW.id
                );
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_advance_ledger_created ON public.salary_advance_ledger;
CREATE TRIGGER trg_on_advance_ledger_created
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_ledger_created();
