-- =========================================================================
-- HIGH-PERFORMANCE BACKEND RPC FUNCTION & TRIGGER FIX
-- RUN THIS IN SUPABASE SQL EDITOR
-- =========================================================================

-- 1. Create or replace the backend RPC function for instant member payment history
CREATE OR REPLACE FUNCTION public.get_member_payment_transactions(p_member_id UUID)
RETURNS TABLE (
    id UUID,
    gym_id UUID,
    title TEXT,
    amount NUMERIC,
    type TEXT,
    category TEXT,
    payment_method TEXT,
    date TEXT,
    transaction_date TIMESTAMPTZ,
    reference_id TEXT,
    created_by UUID,
    notes TEXT,
    expense_date DATE,
    revenue_date DATE,
    entry_date DATE,
    created_by_info TEXT
) AS $$
DECLARE
    v_member_name TEXT;
    v_name_pattern TEXT;
BEGIN
    -- Fetch exact member name for strict word-boundary matching
    SELECT trim(name) INTO v_member_name
    FROM public.members
    WHERE id = p_member_id;

    v_name_pattern := '\y' || COALESCE(v_member_name, '') || '\y';

    RETURN QUERY
    SELECT 
        ft.id,
        ft.gym_id,
        COALESCE(ft.notes, ft.category, 'Payment') AS title,
        ft.amount,
        ft.type,
        ft.category,
        ft.payment_method,
        to_char(ft.transaction_date, 'DD Mon YYYY') AS date,
        ft.transaction_date,
        ft.reference_id,
        ft.created_by,
        COALESCE(ft.notes, '') AS notes,
        ft.expense_date,
        ft.revenue_date,
        ft.entry_date,
        ''::TEXT AS created_by_info
    FROM public.finance_transactions ft
    WHERE ft.type = 'Revenue' -- STRICT: Only revenue/member payments (NO Salary, NO Other Expenses)
      AND (
          ft.reference_id = p_member_id::TEXT
          OR ft.created_by = p_member_id
          OR (
              v_member_name IS NOT NULL 
              AND length(v_member_name) >= 2
              AND (
                  ft.notes ~* v_name_pattern
                  OR ft.category ~* v_name_pattern
              )
          )
      )
    ORDER BY ft.transaction_date DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_member_payment_transactions(UUID) TO anon, authenticated, service_role;

-- 2. Update DB Trigger so sync always preserves member_id in reference_id
CREATE OR REPLACE FUNCTION public.fn_sync_transactions_to_finance()
RETURNS TRIGGER AS $$
DECLARE
    v_payment_method TEXT := 'Cash';
    v_category TEXT := 'Other';
    v_expense_date DATE;
    v_revenue_date DATE;
    v_notes TEXT;
    v_ref_id TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = NEW.id::TEXT) THEN
        RETURN NEW;
    END IF;

    v_category := COALESCE(NEW.category, 'Other');
    IF v_category IN ('Salaries', 'Salary', 'Salary Advance') THEN
        v_category := 'Salary';
    ELSIF v_category NOT IN ('Membership', 'Salary', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other') THEN
        v_category := 'Other';
    END IF;

    BEGIN
        v_payment_method := COALESCE(NEW.payment_mode::TEXT, 'Cash');
        IF v_payment_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
            v_payment_method := 'Other';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_payment_method := 'Cash';
    END;

    v_expense_date := NEW.date;
    IF NEW.type = 'Revenue' THEN
        v_revenue_date := NEW.date;
    ELSE
        v_revenue_date := NULL;
    END IF;

    v_notes := COALESCE(NEW.title, '');
    v_ref_id := COALESCE(NEW.reference_id, NEW.user_id::TEXT, NEW.id::TEXT);

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
        v_ref_id,
        NEW.user_id,
        v_notes
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
