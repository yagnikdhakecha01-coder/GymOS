-- =========================================================================
-- COMPLETE FIX FOR PAY SALARY RPC & COALESCE TYPE MISMATCH ERROR
-- Run this in your Supabase SQL Editor
-- =========================================================================

-- 1. DROP OLD FUNCTIONS TO AVOID SIGNATURE CONFLICTS
DROP FUNCTION IF EXISTS public.pay_salary_draft_v2(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.pay_salary_draft_v2(UUID, TEXT);
DROP FUNCTION IF EXISTS public.pay_salary_draft_v2(UUID);
DROP FUNCTION IF EXISTS public.pay_salary_draft(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.pay_salary_draft(UUID, TEXT);
DROP FUNCTION IF EXISTS public.pay_salary_draft(UUID);

-- 2. REBUILD fn_sync_transactions_to_finance TRIGGER FUNCTION SAFELY
CREATE OR REPLACE FUNCTION public.fn_sync_transactions_to_finance()
RETURNS TRIGGER AS $$
DECLARE
    v_category TEXT;
    v_payment_method TEXT;
    v_expense_date DATE;
    v_revenue_date DATE;
    v_draft_month TEXT;
    v_notes TEXT;
BEGIN
    -- Prevent infinite trigger recursion / duplicates
    IF EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = NEW.id::TEXT) THEN
        RETURN NEW;
    END IF;

    -- Map category to allowed enum check constraints in public.finance_transactions
    v_category := COALESCE(NEW.category::TEXT, 'Other'::TEXT);
    IF v_category IN ('Salaries', 'Salary', 'Salary Advance') THEN
        v_category := 'Salary';
    ELSIF v_category NOT IN ('Membership', 'Salary', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other') THEN
        v_category := 'Other';
    END IF;

    -- Map payment mode to payment method
    BEGIN
        v_payment_method := COALESCE(NEW.payment_mode::TEXT, 'Cash'::TEXT);
        IF v_payment_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
            v_payment_method := 'Other';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_payment_method := 'Cash';
    END;

    -- Calculate expense_date and revenue_date
    v_expense_date := NEW.date;
    
    -- If category is Salary and reference_id is not null
    IF v_category = 'Salary' AND NEW.reference_id IS NOT NULL THEN
        BEGIN
            SELECT salary_month INTO v_draft_month
            FROM public.salary_drafts
            WHERE id::TEXT = NEW.reference_id::TEXT;

            IF v_draft_month IS NOT NULL THEN
                v_expense_date := to_date(v_draft_month, 'Month YYYY');
            END IF;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    IF NEW.type = 'Revenue' THEN
        v_revenue_date := NEW.date;
    ELSE
        v_revenue_date := NULL;
    END IF;

    v_notes := COALESCE(NEW.title::TEXT, ''::TEXT);

    BEGIN
        INSERT INTO public.finance_transactions (
            gym_id,
            amount,
            type,
            category,
            payment_method,
            transaction_date,
            expense_date,
            revenue_date,
            entry_date,
            reference_id,
            created_by,
            notes
        )
        VALUES (
            NEW.gym_id,
            NEW.amount,
            NEW.type,
            v_category,
            v_payment_method,
            NEW.date::TIMESTAMPTZ,
            v_expense_date,
            v_revenue_date,
            NEW.date,
            NEW.id::TEXT,
            NEW.user_id,
            v_notes
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_transactions_to_finance ON public.transactions;
CREATE TRIGGER trg_sync_transactions_to_finance
AFTER INSERT OR UPDATE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_sync_transactions_to_finance();


-- 3. CREATE UNIVERSAL pay_salary_draft_v2 RPC
CREATE OR REPLACE FUNCTION public.pay_salary_draft_v2(
    p_draft_id UUID,
    p_payment_mode TEXT DEFAULT 'Cash',
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB AS $$
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
    WHERE id = p_draft_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Salary draft not found');
    END IF;

    SELECT name INTO s_name FROM public.staff WHERE id = v_staff_id;
    v_settlement_batch_id := gen_random_uuid();

    -- 1. Create Transaction record in public.transactions
    BEGIN
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
            'Salary Payment - ' || COALESCE(s_name, 'Staff'::TEXT),
            v_net_salary,
            'Salaries',
            CURRENT_DATE,
            COALESCE(p_payment_mode::public.payment_mode, 'Cash'::public.payment_mode),
            p_draft_id::TEXT
        ) RETURNING id INTO v_tx_id;
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            INSERT INTO public.transactions (
                gym_id,
                type,
                title,
                amount,
                category,
                date
            )
            VALUES (
                v_gym_id,
                'Expense',
                'Salary Payment - ' || COALESCE(s_name, 'Staff'::TEXT),
                v_net_salary,
                'Salaries',
                CURRENT_DATE
            ) RETURNING id INTO v_tx_id;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END;

    -- 2. Also insert directly into public.expenses for legacy fallback
    BEGIN
        INSERT INTO public.expenses (
            gym_id,
            title,
            category,
            amount,
            date,
            notes
        ) VALUES (
            v_gym_id,
            'Salary Payment - ' || COALESCE(s_name, 'Staff'::TEXT),
            'Salaries',
            v_net_salary,
            CURRENT_DATE,
            COALESCE(p_notes::TEXT, ('Salary payment for ' || COALESCE(v_salary_month, ''))::TEXT)
        );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- 3. Mark Commission ledger entries to Paid (if table exists)
    BEGIN
        FOR r_commission IN 
            SELECT id 
            FROM public.commission_ledger 
            WHERE staff_id = v_staff_id 
              AND status = 'Pending'::public.commission_status
        LOOP
            BEGIN
                INSERT INTO public.salary_payment_commissions (
                    gym_id,
                    salary_payment_id,
                    commission_ledger_id
                )
                VALUES (
                    v_gym_id,
                    p_draft_id,
                    r_commission.id
                ) ON CONFLICT DO NOTHING;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;

            UPDATE public.commission_ledger
            SET status = 'Paid'::public.commission_status,
                included_in_salary = TRUE,
                salary_payment_id = p_draft_id,
                settlement_batch_id = v_settlement_batch_id,
                paid_at = NOW(),
                updated_at = NOW()
            WHERE id = r_commission.id;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- 4. Recover advances dynamically from salary_advance_ledger
    v_to_recover := COALESCE(v_advance_deduction, 0.0);
    IF v_to_recover > 0 THEN
        BEGIN
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
                    SET recovered_amount = COALESCE(r_advance.recovered_amount, 0.0) + v_to_recover,
                        remaining_amount = r_advance.remaining_amount - v_to_recover,
                        salary_payment_id = p_draft_id,
                        updated_at = NOW()
                    WHERE id = r_advance.id;
                    
                    v_to_recover := 0.0;
                END IF;
            END LOOP;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    -- 5. Mark Salary Draft as Paid
    UPDATE public.salary_drafts
    SET status = 'Paid'::public.draft_status,
        paid_transaction_id = v_tx_id,
        created_at = NOW()
    WHERE id = p_draft_id;

    RETURN jsonb_build_object(
        'success', true,
        'draft_id', p_draft_id,
        'net_salary', v_net_salary,
        'message', 'Salary paid successfully'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.pay_salary_draft_v2(UUID, TEXT, TEXT) TO anon, authenticated, service_role;


-- 4. CREATE pay_salary_draft AS ALIAS TO pay_salary_draft_v2
CREATE OR REPLACE FUNCTION public.pay_salary_draft(
    p_draft_id UUID,
    p_payment_mode TEXT DEFAULT 'Cash',
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB AS $$
BEGIN
    RETURN public.pay_salary_draft_v2(p_draft_id, p_payment_mode, p_notes);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.pay_salary_draft(UUID, TEXT, TEXT) TO anon, authenticated, service_role;
