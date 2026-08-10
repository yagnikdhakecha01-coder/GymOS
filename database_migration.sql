-- ====================================================
-- GYMOS - ADVANCED BACKEND ENGINE & MIGRATION SCHEMA
-- ====================================================

-- 1. ENUMS CREATION
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'leave_type') THEN
        CREATE TYPE public.leave_type AS ENUM ('Casual', 'Sick', 'Unpaid', 'Other');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'leave_status') THEN
        CREATE TYPE public.leave_status AS ENUM ('Pending', 'Approved', 'Rejected');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'draft_status') THEN
        CREATE TYPE public.draft_status AS ENUM ('Draft', 'Approved', 'Paid');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'adjustment_type') THEN
        CREATE TYPE public.adjustment_type AS ENUM ('Addition', 'Deduction');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'advance_status') THEN
        CREATE TYPE public.advance_status AS ENUM ('Pending', 'Approved', 'Rejected', 'Recovered');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'commission_status') THEN
        CREATE TYPE public.commission_status AS ENUM ('Pending', 'Paid', 'Cancelled');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_mode') THEN
        CREATE TYPE public.payment_mode AS ENUM ('Cash', 'UPI', 'Card', 'Bank Transfer');
    END IF;
END
$$;

-- 2. ALTER EXISTING TRANSACTIONS TABLE
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'payment_mode'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN payment_mode public.payment_mode DEFAULT 'Cash'::public.payment_mode;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'transactions' AND column_name = 'reference_id'
    ) THEN
        ALTER TABLE public.transactions ADD COLUMN reference_id UUID;
    END IF;
END
$$;

-- 3. CREATE NEW TABLES

-- 3.1 Leave Requests Table
CREATE TABLE IF NOT EXISTS public.leave_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE NOT NULL,
    leave_type public.leave_type NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    status public.leave_status DEFAULT 'Pending'::public.leave_status NOT NULL,
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3.2 Member Memberships Table
CREATE TABLE IF NOT EXISTS public.member_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    member_id UUID REFERENCES public.members(id) ON DELETE CASCADE NOT NULL,
    plan_id TEXT REFERENCES public.membership_plans(id) ON DELETE CASCADE NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    total_amount NUMERIC(12, 2) NOT NULL,
    paid_amount NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    pending_amount NUMERIC(12, 2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
    payment_status TEXT NOT NULL DEFAULT 'Unpaid' CHECK (payment_status IN ('Unpaid', 'Partially Paid', 'Fully Paid')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3.3 Membership Payments Table
CREATE TABLE IF NOT EXISTS public.membership_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    member_membership_id UUID REFERENCES public.member_memberships(id) ON DELETE CASCADE NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    payment_mode public.payment_mode NOT NULL,
    transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
    payment_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3.4 Salary Advances Table
CREATE TABLE IF NOT EXISTS public.salary_advances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    reason TEXT,
    status public.advance_status DEFAULT 'Pending'::public.advance_status NOT NULL,
    requested_date DATE NOT NULL,
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    recovered_in_draft_id UUID, -- Links to draft where this was recovered
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3.5 Commission Ledger Table
CREATE TABLE IF NOT EXISTS public.commission_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE NOT NULL,
    payment_id UUID REFERENCES public.membership_payments(id) ON DELETE CASCADE,
    payment_received NUMERIC(12, 2) NOT NULL,
    commission_rate NUMERIC(5, 2) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    status public.commission_status DEFAULT 'Pending'::public.commission_status NOT NULL,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3.6 Salary Drafts Table
CREATE TABLE IF NOT EXISTS public.salary_drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE NOT NULL,
    salary_month TEXT NOT NULL, -- Format: 'MMMM YYYY' (e.g. 'May 2026')
    base_salary NUMERIC(12, 2) NOT NULL,
    commission_amount NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    advance_deduction NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    other_additions NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    other_deductions NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    net_salary NUMERIC(12, 2) NOT NULL,
    status public.draft_status DEFAULT 'Draft'::public.draft_status NOT NULL,
    paid_transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT uniq_staff_month UNIQUE (staff_id, salary_month)
);

-- 3.7 Salary Adjustments Table
CREATE TABLE IF NOT EXISTS public.salary_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    salary_draft_id UUID REFERENCES public.salary_drafts(id) ON DELETE CASCADE NOT NULL,
    type public.adjustment_type NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    reason TEXT NOT NULL,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3.8 Audit Logs Table
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    table_name TEXT NOT NULL,
    reference_id UUID,
    payload JSONB,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 4. ENABLE RLS ON ALL NEW TABLES
ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_advances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commission_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- 5. RLS ISOLATION POLICIES (DYNAMIC GYM ISOLATION)
CREATE POLICY leave_requests_isolation ON public.leave_requests FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY member_memberships_isolation ON public.member_memberships FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY membership_payments_isolation ON public.membership_payments FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY salary_advances_isolation ON public.salary_advances FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY commission_ledger_isolation ON public.commission_ledger FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY salary_drafts_isolation ON public.salary_drafts FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY salary_adjustments_isolation ON public.salary_adjustments FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY audit_logs_isolation ON public.audit_logs FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- 6. AUTOMATED DB TRIGGERS & FUNCTIONS

-- 6.1 Transaction generator on Membership Payment insertion
CREATE OR REPLACE FUNCTION public.fn_generate_membership_transaction()
RETURNS TRIGGER AS $$
DECLARE
    m_name TEXT;
    p_title TEXT;
    t_id UUID;
BEGIN
    -- If transaction_id is already set, update paid_amount and skip creating transactions
    IF NEW.transaction_id IS NOT NULL THEN
        UPDATE public.member_memberships 
        SET paid_amount = paid_amount + NEW.amount,
            payment_status = CASE 
                WHEN paid_amount + NEW.amount >= total_amount THEN 'Fully Paid'
                ELSE 'Partially Paid'
            END
        WHERE id = NEW.member_membership_id;
        RETURN NEW;
    END IF;

    -- Fetch Member name
    SELECT name INTO m_name FROM public.members WHERE id = (
        SELECT member_id FROM public.member_memberships WHERE id = NEW.member_membership_id
    );
    -- Fetch Plan title
    SELECT title INTO p_title FROM public.membership_plans WHERE id = (
        SELECT plan_id FROM public.member_memberships WHERE id = NEW.member_membership_id
    );

    -- Insert Transaction record
    INSERT INTO public.transactions (gym_id, type, title, amount, category, date, payment_mode, reference_id)
    VALUES (
        NEW.gym_id,
        'Revenue',
        'Membership Payment - ' || coalesce(m_name, 'Member') || ' (' || coalesce(p_title, 'Plan') || ')',
        NEW.amount,
        'Membership',
        NEW.payment_date,
        NEW.payment_mode,
        NEW.id
    ) RETURNING id INTO t_id;

    -- Update Transaction ID link
    UPDATE public.membership_payments SET transaction_id = t_id WHERE id = NEW.id;

    -- Update member's paid amount and payment status
    UPDATE public.member_memberships 
    SET paid_amount = paid_amount + NEW.amount,
        payment_status = CASE 
            WHEN paid_amount + NEW.amount >= total_amount THEN 'Fully Paid'
            ELSE 'Partially Paid'
        END
    WHERE id = NEW.member_membership_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_generate_membership_transaction
AFTER INSERT ON public.membership_payments
FOR EACH ROW EXECUTE FUNCTION public.fn_generate_membership_transaction();


-- 6.2 Commission ledger entry generator on Payment insertion
CREATE OR REPLACE FUNCTION public.fn_generate_commission_entry()
RETURNS TRIGGER AS $$
DECLARE
    t_id UUID;
    c_rate NUMERIC(5,2);
    m_id UUID;
BEGIN
    -- Check if membership has a PT trainer assigned
    SELECT pt_trainer, id INTO t_id, m_id FROM public.members WHERE id = (
        SELECT member_id FROM public.member_memberships WHERE id = NEW.member_membership_id
    );

    IF t_id IS NOT NULL THEN
        -- Fetch Commission Percentage of PT Trainer
        SELECT commission_percentage INTO c_rate FROM public.staff WHERE id = t_id;

        IF c_rate IS NOT NULL AND c_rate > 0 THEN
            INSERT INTO public.commission_ledger (gym_id, staff_id, payment_id, payment_received, commission_rate, amount, status)
            VALUES (
                NEW.gym_id,
                t_id,
                NEW.id,
                NEW.amount,
                c_rate,
                (NEW.amount * c_rate / 100.0),
                'Pending'::public.commission_status
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_generate_commission_entry
AFTER INSERT ON public.membership_payments
FOR EACH ROW EXECUTE FUNCTION public.fn_generate_commission_entry();


-- 6.3 Update Salary Draft Live Calculations Trigger
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- Calculate pending commission amount
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    -- Calculate pending advance salary amount
    SELECT COALESCE(SUM(amount), 0.0) INTO adv_total 
    FROM public.salary_advances 
    WHERE staff_id = NEW.staff_id AND status = 'Approved'::public.advance_status;

    -- Calculate manual adjustments
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;

    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    -- Update Draft values
    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    NEW.net_salary := (NEW.base_salary + comm_total + adj_add) - (adv_total + adj_ded);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();


-- 6.4 Auto Log Audit Events Trigger function
CREATE OR REPLACE FUNCTION public.fn_audit_log_event()
RETURNS TRIGGER AS $$
DECLARE
    g_id UUID;
    u_id UUID;
    payload_val JSONB;
BEGIN
    IF TG_OP = 'DELETE' THEN
        g_id := OLD.gym_id;
        payload_val := to_jsonb(OLD);
    ELSE
        g_id := NEW.gym_id;
        payload_val := to_jsonb(NEW);
    END IF;

    -- Try to capture user id
    u_id := auth.uid();

    INSERT INTO public.audit_logs (gym_id, user_id, action, table_name, reference_id, payload)
    VALUES (
        g_id,
        u_id,
        TG_OP || ' on ' || TG_TABLE_NAME,
        TG_TABLE_NAME,
        coalesce(NEW.id, OLD.id),
        payload_val
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Attach audit trigger to transactions, salary_drafts, leave_requests
CREATE OR REPLACE TRIGGER trg_audit_transactions
AFTER INSERT OR UPDATE OR DELETE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log_event();

CREATE OR REPLACE TRIGGER trg_audit_salary_drafts
AFTER INSERT OR UPDATE OR DELETE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log_event();

CREATE OR REPLACE TRIGGER trg_audit_leave_requests
AFTER INSERT OR UPDATE OR DELETE ON public.leave_requests
FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log_event();


-- 7. SQL VIEWS & SUMMARY QUERIES

-- 7.1 Dashboard Stats View
CREATE OR REPLACE VIEW public.vw_dashboard_stats AS
SELECT 
    g.id AS gym_id,
    (SELECT COUNT(*) FROM public.members m WHERE m.gym_id = g.id AND m.status = 'Active') AS active_members,
    (SELECT COUNT(*) FROM public.staff s WHERE s.gym_id = g.id AND s.status = 'Active') AS active_staff,
    COALESCE((SELECT SUM(amount) FROM public.transactions t WHERE t.gym_id = g.id AND t.type = 'Revenue'), 0.0) AS total_revenue,
    COALESCE((SELECT SUM(amount) FROM public.transactions t WHERE t.gym_id = g.id AND t.type = 'Expense'), 0.0) AS total_expense,
    (COALESCE((SELECT SUM(amount) FROM public.transactions t WHERE t.gym_id = g.id AND t.type = 'Revenue'), 0.0) - 
     COALESCE((SELECT SUM(amount) FROM public.transactions t WHERE t.gym_id = g.id AND t.type = 'Expense'), 0.0)) AS net_profit,
    COALESCE((SELECT SUM(pending_amount) FROM public.member_memberships mm WHERE mm.gym_id = g.id), 0.0) AS total_pending_dues
FROM public.gyms g;

-- 7.2 Pending Salary List View
CREATE OR REPLACE VIEW public.vw_pending_salary_list AS
SELECT 
    s.id AS staff_id,
    s.gym_id,
    s.name,
    s.role,
    s.avatar,
    s.salary AS base_salary,
    COALESCE((SELECT SUM(amount) FROM public.commission_ledger cl WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status), 0.0) AS pending_commission
FROM public.staff s
WHERE NOT EXISTS (
    SELECT 1 FROM public.salary_drafts sd 
    WHERE sd.staff_id = s.id 
      AND sd.salary_month = to_char(now(), 'Month YYYY')
      AND sd.status = 'Paid'::public.draft_status
);

-- 8. PERFORMANCE INDEXES
CREATE INDEX IF NOT EXISTS idx_leaves_staff_dates ON public.leave_requests(staff_id, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_member_membership_plan ON public.member_memberships(member_id, plan_id);
CREATE INDEX IF NOT EXISTS idx_membership_payments_date ON public.membership_payments(payment_date DESC);
CREATE INDEX IF NOT EXISTS idx_salary_advances_staff ON public.salary_advances(staff_id, status);
CREATE INDEX IF NOT EXISTS idx_commission_ledger_staff ON public.commission_ledger(staff_id, status);
CREATE INDEX IF NOT EXISTS idx_salary_drafts_month ON public.salary_drafts(salary_month);
CREATE INDEX IF NOT EXISTS idx_audit_logs_gym_created ON public.audit_logs(gym_id, created_at DESC);

-- 9. GRANT TABLE PRIVILEGES TO AUTHENTICATED & ANON ROLES
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

