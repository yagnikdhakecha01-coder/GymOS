-- ====================================================================
-- GYMOS: ADVANCE SALARY LEDGER & MIGRATION SCHEMA (BACKEND REDESIGN)
-- ====================================================================

-- 1. Create enum states and table constraints safely
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'advance_status') THEN
        CREATE TYPE public.advance_status AS ENUM ('Pending', 'Approved', 'Rejected', 'Given', 'Recovered');
    END IF;
END
$$;

-- Rename old table if exists or drop to avoid conflicts
DROP TABLE IF EXISTS public.salary_advances CASCADE;

-- 2. Create Salary Advance Ledger Table
CREATE TABLE public.salary_advance_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    salary_payment_id UUID, -- Links to draft (salary_drafts) when recovered
    advance_amount NUMERIC(12,2) NOT NULL CHECK (advance_amount > 0),
    recovered_amount NUMERIC(12,2) DEFAULT 0.0 NOT NULL CHECK (recovered_amount >= 0),
    remaining_amount NUMERIC(12,2) DEFAULT 0.0 NOT NULL CHECK (remaining_amount >= 0),
    status public.advance_status DEFAULT 'Pending'::public.advance_status NOT NULL,
    given_date DATE NOT NULL,
    salary_month TEXT NOT NULL, -- 'MMMM YYYY' (e.g. 'July 2026')
    payment_method TEXT DEFAULT 'Cash',
    reference_number TEXT,
    notes TEXT,
    reason TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing for fast search queries
CREATE INDEX IF NOT EXISTS idx_sal_adv_ledger_staff ON public.salary_advance_ledger(staff_id, status);

-- Enable RLS
ALTER TABLE public.salary_advance_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY salary_advance_ledger_isolation ON public.salary_advance_ledger 
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- Set remaining_amount equal to advance_amount on creation
CREATE OR REPLACE FUNCTION public.fn_set_remaining_advance_amount()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.remaining_amount := NEW.advance_amount;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_remaining_advance_amount
BEFORE INSERT ON public.salary_advance_ledger
FOR EACH ROW EXECUTE FUNCTION public.fn_set_remaining_advance_amount();


-- 3. Automatic Expense Logger on Advance Salary Handout
CREATE OR REPLACE FUNCTION public.fn_on_advance_ledger_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF (NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status)) AND 
       (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('Approved'::public.advance_status, 'Given'::public.advance_status))) THEN
       
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Record Expense dynamically
        INSERT INTO public.transactions (
            gym_id,
            type,
            title,
            amount,
            category,
            date,
            payment_mode,
            reference_id
        )
        VALUES (
            NEW.gym_id,
            'Expense',
            'Salary Advance - ' || COALESCE(s_name, 'Staff'),
            NEW.advance_amount,
            'Salary Advance',
            NEW.given_date,
            COALESCE(NEW.payment_method::public.payment_mode, 'Cash'::public.payment_mode),
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_advance_ledger_created
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_ledger_created();


-- 4. Update view to calculate Pending Salary accurately
CREATE OR REPLACE VIEW public.vw_pending_salary_list AS
SELECT 
    s.id AS staff_id,
    s.gym_id,
    s.name,
    s.role,
    s.avatar,
    s.salary AS base_salary,
    COALESCE((
        SELECT SUM(cl.amount) 
        FROM public.commission_ledger cl 
        WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
    ), 0.0) AS pending_commission,
    COALESCE((
        SELECT SUM(sa.remaining_amount) 
        FROM public.salary_advance_ledger sa 
        WHERE sa.staff_id = s.id 
          AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
    ), 0.0) AS total_advance,
    GREATEST(
        (s.salary + COALESCE((
            SELECT SUM(cl.amount) 
            FROM public.commission_ledger cl 
            WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
        ), 0.0)) - COALESCE((
            SELECT SUM(sa.remaining_amount) 
            FROM public.salary_advance_ledger sa 
            WHERE sa.staff_id = s.id 
              AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
        ), 0.0), 
        0.0
    ) AS net_pending_salary
FROM public.staff s
WHERE NOT EXISTS (
    SELECT 1 FROM public.salary_drafts sd 
    WHERE sd.staff_id = s.id 
      AND sd.salary_month = to_char(now(), 'Month YYYY')
      AND sd.status = 'Paid'::public.draft_status
);


-- 5. Updated live calculations inside public.salary_drafts
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    SELECT COALESCE(SUM(remaining_amount), 0.0) INTO adv_total 
    FROM public.salary_advance_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    -- Formula: Fixed Salary + Commission + Additions - Deductions - Advance Deduction
    NEW.net_salary := ((NEW.base_salary + comm_total + adj_add) - adj_ded) - adv_total;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;
CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();


-- 6. Stored Procedure (RPC) Transaction to pay salary & recover advances
CREATE OR REPLACE FUNCTION public.pay_salary_draft(
    p_draft_id UUID,
    p_payment_mode TEXT,
    p_notes TEXT
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
    WHERE id = p_draft_id AND status <> 'Paid';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Salary Draft not found or already paid.';
    END IF;

    SELECT name INTO s_name FROM public.staff WHERE id = v_staff_id;

    -- 1. Create Transaction record in public.transactions
    INSERT INTO public.transactions (
        gym_id,
        type,
        title,
        amount,
        category,
        date,
        payment_mode,
        reference_id
    )
    VALUES (
        v_gym_id,
        'Expense',
        'Salary Payment - ' || COALESCE(s_name, 'Staff'),
        v_net_salary,
        'Salaries',
        CURRENT_DATE,
        COALESCE(p_payment_mode::public.payment_mode, 'Cash'::public.payment_mode),
        p_draft_id
    ) RETURNING id INTO v_tx_id;

    -- 2. Mark Commissions included as Paid
    UPDATE public.commission_ledger
    SET status = 'Paid'::public.commission_status,
        paid_at = NOW()
    WHERE staff_id = v_staff_id AND status = 'Pending'::public.commission_status;

    -- 3. Recover advances dynamically
    v_to_recover := v_advance_deduction;
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
                -- Full recovery for this record
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
                -- Partial recovery for this record
                UPDATE public.salary_advance_ledger
                SET recovered_amount = r_advance.recovered_amount + v_to_recover,
                    remaining_amount = r_advance.remaining_amount - v_to_recover,
                    salary_payment_id = p_draft_id,
                    updated_at = NOW()
                WHERE id = r_advance.id;
                
                v_to_recover := 0.0;
            END IF;
        END LOOP;
    END IF;

    -- 4. Mark draft as Paid
    UPDATE public.salary_drafts
    SET status = 'Paid'::public.draft_status,
        paid_transaction_id = v_tx_id,
        created_at = NOW()
    WHERE id = p_draft_id;

    -- 5. Create Audit Log Entry
    INSERT INTO public.audit_logs (
        gym_id,
        action,
        table_name,
        reference_id,
        payload
    )
    VALUES (
        v_gym_id,
        'Pay Salary Draft',
        'salary_drafts',
        p_draft_id,
        jsonb_build_object(
            'staff_id', v_staff_id,
            'net_salary', v_net_salary,
            'advance_deduction', v_advance_deduction,
            'transaction_id', v_tx_id
        )
    );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
