-- =========================================================================
-- DATABASE MIGRATION: redeploy_finance_sync_accruals.sql
-- Run this script in your Supabase SQL Editor to link salary payments 
-- to their target accrual months and sync all records with finance_transactions.
-- =========================================================================

-- 1. Create or replace the sync trigger function
CREATE OR REPLACE FUNCTION public.fn_sync_transactions_to_finance()
RETURNS TRIGGER AS $$
DECLARE
    v_payment_method TEXT := 'Cash';
    v_category TEXT := 'Other';
    v_expense_date DATE;
    v_revenue_date DATE;
    v_draft_month TEXT;
    v_notes TEXT;
BEGIN
    -- Avoid duplicate syncs if we insert directly or if it already exists
    IF EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = NEW.id::TEXT) THEN
        RETURN NEW;
    END IF;

    -- Map category to allowed enum check constraints in public.finance_transactions
    v_category := COALESCE(NEW.category, 'Other');
    IF v_category IN ('Salaries', 'Salary', 'Salary Advance') THEN
        v_category := 'Salary';
    ELSIF v_category NOT IN ('Membership', 'Salary', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other') THEN
        v_category := 'Other';
    END IF;

    -- Map payment mode to payment method
    BEGIN
        v_payment_method := COALESCE(NEW.payment_mode::TEXT, 'Cash');
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
        -- Try to fetch salary month from salary drafts
        SELECT salary_month INTO v_draft_month
        FROM public.salary_drafts
        WHERE id = NEW.reference_id;

        IF v_draft_month IS NOT NULL THEN
            v_expense_date := to_date(v_draft_month, 'Month YYYY');
        END IF;
    END IF;

    -- If category is Salary and is an Advance (reference_id is linked to salary_advance_ledger)
    IF v_expense_date = NEW.date AND v_category = 'Salary' AND NEW.reference_id IS NOT NULL THEN
        SELECT given_date INTO v_expense_date
        FROM public.salary_advance_ledger
        WHERE id = NEW.reference_id;
        
        -- Fallback to date if not found
        IF v_expense_date IS NULL THEN
            v_expense_date := NEW.date;
        END IF;
    END IF;

    IF NEW.type = 'Revenue' THEN
        v_revenue_date := NEW.date;
    ELSE
        v_revenue_date := NULL;
    END IF;

    v_notes := COALESCE(NEW.title, '');

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
        NEW.date::TIMESTAMPTZ, -- transaction_date (payment date shown in list)
        v_expense_date,        -- expense_date (accrual month for expense summation)
        v_revenue_date,        -- revenue_date (accrual month for revenue summation)
        NEW.date,
        NEW.id::TEXT,
        NEW.user_id,
        v_notes
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Drop and recreate the trigger on public.transactions
DROP TRIGGER IF EXISTS trg_sync_transactions_to_finance ON public.transactions;
CREATE TRIGGER trg_sync_transactions_to_finance
AFTER INSERT OR UPDATE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_sync_transactions_to_finance();

-- 3. Update get_finance_summary to calculate revenues and expenses using accrual dates (expense_date / revenue_date)
CREATE OR REPLACE FUNCTION public.get_finance_summary(p_gym_id UUID, p_target_date DATE)
RETURNS TABLE (
    total_revenue NUMERIC,
    total_expense NUMERIC,
    net_profit NUMERIC,
    monthly_revenue_data NUMERIC[]
) AS $$
DECLARE
    v_month_start DATE := date_trunc('month', p_target_date);
    v_month_end DATE := (date_trunc('month', p_target_date) + interval '1 month' - interval '1 day')::DATE;
    v_revenue_list NUMERIC[] := ARRAY[]::NUMERIC[];
    v_day INT;
    v_day_rev NUMERIC;
BEGIN
    -- Monthly Revenue (sum based on revenue_date, falling back to transaction_date)
    SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO total_revenue
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id
      AND type = 'Revenue'
      AND COALESCE(revenue_date, transaction_date::DATE) BETWEEN v_month_start AND v_month_end;

    -- Monthly Expense (sum based on expense_date, falling back to transaction_date)
    SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO total_expense
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id
      AND type = 'Expense'
      AND COALESCE(expense_date, transaction_date::DATE) BETWEEN v_month_start AND v_month_end;

    -- Net Profit
    net_profit := total_revenue - total_expense;

    -- Calculate 6 data points for the sparkline chart dynamically (5-day intervals)
    FOR v_day IN 0..5 LOOP
        SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO v_day_rev
        FROM public.finance_transactions
        WHERE gym_id = p_gym_id
          AND type = 'Revenue'
          AND COALESCE(revenue_date, transaction_date::DATE) >= (v_month_start + (v_day * 5) * interval '1 day')::DATE
          AND COALESCE(revenue_date, transaction_date::DATE) < (v_month_start + ((v_day + 1) * 5) * interval '1 day')::DATE;
        v_revenue_list := array_append(v_revenue_list, v_day_rev);
    END LOOP;

    monthly_revenue_data := v_revenue_list;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Sync existing historical transactions
DO $$
DECLARE
    r_tx RECORD;
    v_payment_method TEXT;
    v_category TEXT;
    v_expense_date DATE;
    v_revenue_date DATE;
    v_draft_month TEXT;
BEGIN
    FOR r_tx IN SELECT * FROM public.transactions
    LOOP
        -- Check if it already exists
        IF NOT EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = r_tx.id::TEXT) THEN
            
            -- Map category
            v_category := COALESCE(r_tx.category, 'Other');
            IF v_category IN ('Salaries', 'Salary', 'Salary Advance') THEN
                v_category := 'Salary';
            ELSIF v_category NOT IN ('Membership', 'Salary', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other') THEN
                v_category := 'Other';
            END IF;

            -- Map payment method
            BEGIN
                v_payment_method := COALESCE(r_tx.payment_mode::TEXT, 'Cash');
                IF v_payment_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
                    v_payment_method := 'Other';
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_payment_method := 'Cash';
            END;

            -- Calculate expense_date and revenue_date
            v_expense_date := r_tx.date;
            IF v_category = 'Salary' AND r_tx.reference_id IS NOT NULL THEN
                SELECT salary_month INTO v_draft_month
                FROM public.salary_drafts
                WHERE id = r_tx.reference_id;

                IF v_draft_month IS NOT NULL THEN
                    v_expense_date := to_date(v_draft_month, 'Month YYYY');
                ELSE
                    -- Check if it is an advance ledger record instead
                    SELECT given_date INTO v_expense_date
                    FROM public.salary_advance_ledger
                    WHERE id = r_tx.reference_id;
                    
                    IF v_expense_date IS NULL THEN
                        v_expense_date := r_tx.date;
                    END IF;
                END IF;
            END IF;

            IF r_tx.type = 'Revenue' THEN
                v_revenue_date := r_tx.date;
            ELSE
                v_revenue_date := NULL;
            END IF;

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
                r_tx.gym_id,
                r_tx.amount,
                r_tx.type,
                v_category,
                v_payment_method,
                r_tx.date::TIMESTAMPTZ,
                v_expense_date,
                v_revenue_date,
                r_tx.date,
                r_tx.id::TEXT,
                r_tx.user_id,
                r_tx.title
            );
        END IF;
    END LOOP;
END
$$;
