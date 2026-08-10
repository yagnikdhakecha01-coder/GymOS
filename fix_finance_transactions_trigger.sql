-- ====================================================
-- GYMOS - FIX FINANCE TRANSACTIONS TRIGGER (TARGET RIGHT TABLE)
-- ====================================================
-- Run this in your Supabase SQL Editor to solve:
-- "column 'notes' of relation 'transactions' does not exist"

-- 1. Ensure `finance_transactions` table exists
CREATE TABLE IF NOT EXISTS public.finance_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    type TEXT NOT NULL CHECK (type IN ('Revenue', 'Expense')),
    category TEXT NOT NULL,
    payment_method TEXT DEFAULT 'Cash' NOT NULL,
    transaction_date TIMESTAMPTZ DEFAULT now() NOT NULL,
    reference_id TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Grant privileges
GRANT ALL ON TABLE public.finance_transactions TO anon, authenticated, service_role;

-- 2. Trigger Function inserting into `finance_transactions` (Correct table with notes column)
CREATE OR REPLACE FUNCTION public.fn_on_advance_salary_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status) THEN
        -- Fetch Staff Name
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Insert Expense record into `finance_transactions`
        INSERT INTO public.finance_transactions (
            gym_id, 
            type, 
            category, 
            amount, 
            payment_method, 
            reference_id, 
            notes
        )
        VALUES (
            NEW.gym_id,
            'Expense',
            'Salary',
            NEW.amount,
            'Cash',
            NEW.staff_id::TEXT,
            'Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || NEW.reason || ')', '')
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach trigger to salary_advances table
DROP TRIGGER IF EXISTS trg_on_advance_salary_created ON public.salary_advances;
CREATE TRIGGER trg_on_advance_salary_created
AFTER INSERT OR UPDATE ON public.salary_advances
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_salary_created();


-- 3. Trigger Function on inserting into finance_transactions to compute commissions
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_inserted()
RETURNS TRIGGER AS $$
DECLARE
    v_member_membership_id UUID;
    v_payment_id UUID;
    v_salary_type TEXT;
    v_staff_id UUID;
    v_comm_rate NUMERIC(5,2);
    v_payment_month TEXT;
    v_ref_uuid UUID;
BEGIN
    -- Check if this transaction is revenue for membership and has a valid member reference_id
    IF NEW.type = 'Revenue' AND NEW.category = 'Membership' AND NEW.reference_id IS NOT NULL THEN
        -- Safely cast reference_id to UUID if it matches UUID format
        IF NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_ref_uuid := NEW.reference_id::UUID;
        ELSE
            RETURN NEW;
        END IF;

        -- Find the active member membership plan
        SELECT id INTO v_member_membership_id 
        FROM public.member_memberships 
        WHERE member_id = v_ref_uuid
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
                v_ref_uuid,
                (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1),
                CURRENT_DATE,
                CURRENT_DATE + (
                    COALESCE(
                        (SELECT duration_days FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        (SELECT COALESCE(duration_months, 1) * 30 FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
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
        WHERE member_id = v_ref_uuid AND assignment_status = 'Active'
        LIMIT 1;

        -- Fallback check
        IF v_staff_id IS NULL THEN
            SELECT pt_trainer INTO v_staff_id FROM public.members WHERE id = v_ref_uuid;
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
                    v_ref_uuid,
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

-- Recreate trigger on finance_transactions
DROP TRIGGER IF EXISTS trg_on_finance_transaction_inserted ON public.finance_transactions;
CREATE TRIGGER trg_on_finance_transaction_inserted
AFTER INSERT ON public.finance_transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_on_finance_transaction_inserted();
