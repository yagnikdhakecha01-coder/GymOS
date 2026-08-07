-- ====================================================================
-- GYMOS: STAFF COMMISSION ARCHITECTURE REDESIGN MIGRATION
-- ====================================================================

-- 1. Create Enums safely
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'commission_status') THEN
        CREATE TYPE public.commission_status AS ENUM ('Pending', 'Paid', 'Cancelled', 'Reversed', 'Void');
    ELSE
        -- Add any missing enum values if exists
        ALTER TYPE public.commission_status ADD VALUE IF NOT EXISTS 'Reversed';
        ALTER TYPE public.commission_status ADD VALUE IF NOT EXISTS 'Void';
    END IF;
END
$$;

-- 2. Create Personal Trainer Assignment Table
CREATE TABLE IF NOT EXISTS public.pt_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    commission_percentage NUMERIC(5, 2) NOT NULL DEFAULT 0.0 CHECK (commission_percentage >= 0),
    assignment_status TEXT NOT NULL DEFAULT 'Active' CHECK (assignment_status IN ('Active', 'Inactive')),
    pt_start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    deleted_at TIMESTAMPTZ
);

-- Indexing for assignments
CREATE INDEX IF NOT EXISTS idx_pt_assignments_lookup ON public.pt_assignments (member_id, staff_id, assignment_status);
CREATE INDEX IF NOT EXISTS idx_pt_assignments_gym ON public.pt_assignments (gym_id);

-- Enable RLS for assignments
ALTER TABLE public.pt_assignments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'pt_assignments' AND policyname = 'pt_assignments_isolation'
    ) THEN
        CREATE POLICY pt_assignments_isolation ON public.pt_assignments 
            FOR ALL TO authenticated
            USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));
    END IF;
END
$$;

-- 3. Junction table mapping salary payment to multiple commission ledger entries
CREATE TABLE IF NOT EXISTS public.salary_payment_commissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    salary_payment_id UUID NOT NULL REFERENCES public.salary_drafts(id) ON DELETE CASCADE,
    commission_ledger_id UUID NOT NULL, -- References commission_ledger(id) but decoupled for constraint flexibility if dropped
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing junction table
CREATE INDEX IF NOT EXISTS idx_sal_pay_comm_payment ON public.salary_payment_commissions (salary_payment_id);
CREATE INDEX IF NOT EXISTS idx_sal_pay_comm_ledger ON public.salary_payment_commissions (commission_ledger_id);

-- Enable RLS
ALTER TABLE public.salary_payment_commissions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'salary_payment_commissions' AND policyname = 'salary_payment_commissions_isolation'
    ) THEN
        CREATE POLICY salary_payment_commissions_isolation ON public.salary_payment_commissions 
            FOR ALL TO authenticated
            USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));
    END IF;
END
$$;

-- 4. Recreate/Enhance Commission Ledger to match details
-- Check if table needs modification
DO $$
BEGIN
    -- Add rule_version
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='rule_version') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN rule_version TEXT DEFAULT 'v1';
    END IF;

    -- Add calculation_base
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='calculation_base') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN calculation_base TEXT DEFAULT 'Received Payment';
    END IF;

    -- Add source_type
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='source_type') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN source_type TEXT DEFAULT 'Membership';
    END IF;

    -- Add source_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='source_id') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN source_id UUID;
    END IF;

    -- Add member_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='member_id') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN member_id UUID REFERENCES public.members(id) ON DELETE CASCADE;
    END IF;

    -- Add salary_month
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='salary_month') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN salary_month TEXT;
    END IF;

    -- Add included_in_salary
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='included_in_salary') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN included_in_salary BOOLEAN DEFAULT FALSE NOT NULL;
    END IF;

    -- Add salary_payment_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='salary_payment_id') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN salary_payment_id UUID REFERENCES public.salary_drafts(id) ON DELETE SET NULL;
    END IF;

    -- Add settlement_batch_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='settlement_batch_id') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN settlement_batch_id UUID;
    END IF;

    -- Add updated_at
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='updated_at') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();
    END IF;
END
$$;

-- 5. Trigger to Automatically Generate Commission on Payment Received
CREATE OR REPLACE FUNCTION public.fn_generate_commission_entry()
RETURNS TRIGGER AS $$
DECLARE
    v_staff_id UUID;
    v_comm_rate NUMERIC(5,2);
    v_salary_type TEXT;
    v_member_id UUID;
    v_payment_month TEXT;
BEGIN
    -- Get member_id from member_memberships
    SELECT member_id INTO v_member_id 
    FROM public.member_memberships 
    WHERE id = NEW.member_membership_id;

    -- Find the active PT assignment for this member to retrieve snapshotted commission rate and staff_id
    SELECT staff_id, commission_percentage 
    INTO v_staff_id, v_comm_rate
    FROM public.pt_assignments
    WHERE member_id = v_member_id AND assignment_status = 'Active'
    LIMIT 1;

    -- If no PT Assignment is found, check member table pt_trainer (fallback/compatibility)
    IF v_staff_id IS NULL THEN
        SELECT pt_trainer INTO v_staff_id FROM public.members WHERE id = v_member_id;
        IF v_staff_id IS NOT NULL THEN
            SELECT commission_percentage INTO v_comm_rate FROM public.staff WHERE id = v_staff_id;
        END IF;
    END IF;

    -- Process only if assigned staff has valid salary type that supports commission
    IF v_staff_id IS NOT NULL AND v_comm_rate IS NOT NULL AND v_comm_rate > 0 THEN
        SELECT salary_type INTO v_salary_type FROM public.staff WHERE id = v_staff_id;

        IF v_salary_type IN ('Commission Based', 'Fixed + Commission', 'Percentage', 'Both') THEN
            v_payment_month := to_char(NEW.payment_date, 'Month YYYY');

            INSERT INTO public.commission_ledger (
                gym_id,
                staff_id,
                member_id,
                payment_id,
                payment_received,
                commission_rate,
                amount,
                status,
                source_type,
                source_id,
                rule_version,
                calculation_base,
                salary_month,
                included_in_salary,
                created_at,
                updated_at
            )
            VALUES (
                NEW.gym_id,
                v_staff_id,
                v_member_id,
                NEW.id,
                NEW.amount,
                v_comm_rate,
                (NEW.amount * v_comm_rate / 100.0),
                'Pending'::public.commission_status,
                'Membership',
                NEW.id,
                'v1',
                'Received Payment',
                v_payment_month,
                FALSE,
                now(),
                now()
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.1 Transaction generator on Membership Payment insertion or Finance Transaction insertion
-- We will modify the triggers to automatically generate membership payments and link them to commission calculations when transactions are inserted in finance_transactions.
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_inserted()
RETURNS TRIGGER AS $$
DECLARE
    v_member_membership_id UUID;
    v_payment_id UUID;
    v_salary_type TEXT;
    v_staff_id UUID;
    v_comm_rate NUMERIC(5,2);
    v_payment_month TEXT;
BEGIN
    -- Check if this transaction is revenue for membership and has a valid member reference_id
    IF NEW.type = 'Revenue' AND NEW.category = 'Membership' AND NEW.reference_id IS NOT NULL THEN
        -- Find the active member membership plan
        SELECT id INTO v_member_membership_id 
        FROM public.member_memberships 
        WHERE member_id = NEW.reference_id
        ORDER BY created_at DESC 
        LIMIT 1;

        -- If no active membership plan exists, create a default dummy membership linking record
        IF v_member_membership_id IS NULL THEN
            INSERT INTO public.member_memberships (
                gym_id,
                member_id,
                plan_id,
                start_date,
                end_date,
                total_amount,
                paid_amount,
                payment_status
            )
            VALUES (
                NEW.gym_id,
                NEW.reference_id,
                (SELECT membership_plan_id FROM public.members WHERE id = NEW.reference_id LIMIT 1),
                CURRENT_DATE,
                CURRENT_DATE + (
                    COALESCE(
                        (SELECT duration_days FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = NEW.reference_id LIMIT 1) LIMIT 1),
                        (SELECT COALESCE(duration_months, 1) * 30 FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = NEW.reference_id LIMIT 1) LIMIT 1),
                        30
                    ) || ' days'
                )::INTERVAL,
                NEW.amount,
                0.0,
                'Unpaid'
            ) RETURNING id INTO v_member_membership_id;
        END IF;

        -- Insert record into membership_payments to register actual received payment details
        INSERT INTO public.membership_payments (
            gym_id,
            member_membership_id,
            amount,
            payment_mode,
            transaction_id,
            payment_date
        )
        VALUES (
            NEW.gym_id,
            v_member_membership_id,
            NEW.amount,
            COALESCE(NEW.payment_method::public.payment_mode, 'Cash'::public.payment_mode),
            NEW.id,
            CURRENT_DATE
        ) RETURNING id INTO v_payment_id;

        -- Directly process commission ledger insertion in trigger logic for safety
        SELECT staff_id, commission_percentage 
        INTO v_staff_id, v_comm_rate
        FROM public.pt_assignments
        WHERE member_id = NEW.reference_id AND assignment_status = 'Active'
        LIMIT 1;

        -- Fallback check
        IF v_staff_id IS NULL THEN
            SELECT pt_trainer INTO v_staff_id FROM public.members WHERE id = NEW.reference_id;
            IF v_staff_id IS NOT NULL THEN
                SELECT commission_percentage INTO v_comm_rate FROM public.staff WHERE id = v_staff_id;
            END IF;
        END IF;

        -- Generate ledger entry if conditions match
        IF v_staff_id IS NOT NULL AND v_comm_rate IS NOT NULL AND v_comm_rate > 0 THEN
            SELECT salary_type INTO v_salary_type FROM public.staff WHERE id = v_staff_id;

            IF v_salary_type IN ('Commission Based', 'Fixed + Commission', 'Percentage', 'Both') THEN
                v_payment_month := to_char(CURRENT_DATE, 'Month YYYY');

                INSERT INTO public.commission_ledger (
                    gym_id,
                    staff_id,
                    member_id,
                    payment_id,
                    payment_received,
                    commission_rate,
                    amount,
                    status,
                    source_type,
                    source_id,
                    rule_version,
                    calculation_base,
                    salary_month,
                    included_in_salary,
                    created_at,
                    updated_at
                )
                VALUES (
                    NEW.gym_id,
                    v_staff_id,
                    NEW.reference_id,
                    v_payment_id,
                    NEW.amount,
                    v_comm_rate,
                    (NEW.amount * v_comm_rate / 100.0),
                    'Pending'::public.commission_status,
                    'Membership',
                    NEW.id,
                    'v1',
                    'Received Payment',
                    v_payment_month,
                    FALSE,
                    now(),
                    now()
                );
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger
DROP TRIGGER IF EXISTS trg_on_finance_transaction_inserted ON public.finance_transactions;
CREATE TRIGGER trg_on_finance_transaction_inserted
AFTER INSERT ON public.finance_transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_on_finance_transaction_inserted();


-- 6. Trigger to reverse commission on refund / payment deletion
CREATE OR REPLACE FUNCTION public.fn_reverse_commission_on_payment_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.commission_ledger
    SET status = 'Cancelled'::public.commission_status,
        updated_at = now()
    WHERE payment_id = OLD.id AND status = 'Pending'::public.commission_status;
    
    -- For already paid ones, mark as Reversed
    UPDATE public.commission_ledger
    SET status = 'Reversed'::public.commission_status,
        updated_at = now()
    WHERE payment_id = OLD.id AND status = 'Paid'::public.commission_status;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_reverse_commission_on_payment_delete ON public.membership_payments;
CREATE TRIGGER trg_reverse_commission_on_payment_delete
AFTER DELETE ON public.membership_payments
FOR EACH ROW EXECUTE FUNCTION public.fn_reverse_commission_on_payment_delete();

-- 7. Update Live Calculations Inside public.salary_drafts
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- Sum of pending commission entries for this staff that are not paid yet
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status = 'Pending'::public.commission_status
      AND included_in_salary = FALSE;

    -- Sum of pending advances
    SELECT COALESCE(SUM(remaining_amount), 0.0) INTO adv_total 
    FROM public.salary_advance_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- Manual adjustments
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    NEW.net_salary := ((NEW.base_salary + comm_total + adj_add) - adj_ded) - adv_total;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;
CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();

-- 8. Transaction-Safe Stored Procedure (RPC) to Pay Salary and Map Ledgers
CREATE OR REPLACE FUNCTION public.pay_salary_draft_v2(
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
    r_commission RECORD;
    v_to_recover NUMERIC(12,2) := 0.0;
    v_recovered_temp NUMERIC(12,2) := 0.0;
    v_settlement_batch_id UUID;
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
    v_settlement_batch_id := gen_random_uuid();

    -- 1. Create Transaction record in public.transactions (Create Salary Expense)
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

    -- 2. Junction map and update commission ledger entries to Paid
    FOR r_commission IN 
        SELECT id 
        FROM public.commission_ledger 
        WHERE staff_id = v_staff_id 
          AND status = 'Pending'::public.commission_status
          AND included_in_salary = FALSE
    LOOP
        -- Insert junction record
        INSERT INTO public.salary_payment_commissions (
            gym_id,
            salary_payment_id,
            commission_ledger_id
        )
        VALUES (
            v_gym_id,
            p_draft_id,
            r_commission.id
        );

        -- Update Ledger entry status
        UPDATE public.commission_ledger
        SET status = 'Paid'::public.commission_status,
            included_in_salary = TRUE,
            salary_payment_id = p_draft_id,
            settlement_batch_id = v_settlement_batch_id,
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = r_commission.id;
    END LOOP;

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
        'PAID SALARY V2',
        'salary_drafts',
        p_draft_id,
        jsonb_build_object(
            'staff_id', v_staff_id,
            'net_salary', v_net_salary,
            'settlement_batch_id', v_settlement_batch_id,
            'paid_transaction_id', v_tx_id
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Grant privileges for newly created tables
GRANT ALL ON TABLE public.pt_assignments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.salary_payment_commissions TO anon, authenticated, service_role;

