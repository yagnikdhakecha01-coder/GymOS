-- ====================================================================
-- GYMOS - DATABASE FUNCTION: get_paid_salary_draft_details
-- Run this in your Supabase SQL Editor to retrieve detailed
-- breakdown of commissions, advances and adjustments for a paid salary.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.get_paid_salary_draft_details(
    p_draft_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_draft RECORD;
    v_commissions JSONB;
    v_advances JSONB;
    v_adjustments JSONB;
BEGIN
    -- 1. Fetch draft info
    SELECT id, gym_id, staff_id, salary_month, base_salary, commission_amount, advance_deduction, other_additions, other_deductions, net_salary, status, created_at
    INTO v_draft
    FROM public.salary_drafts
    WHERE id = p_draft_id;

    IF v_draft.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'Salary draft not found'
        );
    END IF;

    -- 2. Fetch commissions linked to this salary payment
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'created_at', to_char(created_at AT TIME ZONE 'Asia/Kolkata', 'dd-MM-yyyy'),
        'payment_id', payment_id,
        'payment_received', payment_received,
        'commission_rate', commission_rate,
        'amount', amount
    ) ORDER BY created_at ASC), '[]'::JSONB)
    INTO v_commissions
    FROM public.commission_ledger
    WHERE salary_payment_id = p_draft_id;

    -- 3. Fetch advances recovered in this salary payment
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'given_date', to_char(given_date, 'dd-MM-yyyy'),
        'reason', reason,
        'advance_amount', advance_amount,
        'recovered_amount', recovered_amount,
        'remaining_amount', remaining_amount,
        'status', status
    ) ORDER BY given_date ASC), '[]'::JSONB)
    INTO v_advances
    FROM public.salary_advance_ledger
    WHERE salary_payment_id = p_draft_id;

    -- 4. Fetch manual adjustments linked to this salary draft
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'reason', reason,
        'amount', amount,
        'type', type
    ) ORDER BY created_at ASC), '[]'::JSONB)
    INTO v_adjustments
    FROM public.salary_adjustments
    WHERE salary_draft_id = p_draft_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'draft_id', v_draft.id,
        'gym_id', v_draft.gym_id,
        'staff_id', v_draft.staff_id,
        'salary_month', v_draft.salary_month,
        'base_salary', v_draft.base_salary,
        'commission_amount', v_draft.commission_amount,
        'advance_deduction', v_draft.advance_deduction,
        'other_additions', v_draft.other_additions,
        'other_deductions', v_draft.other_deductions,
        'net_salary', v_draft.net_salary,
        'paid_on', to_char(v_draft.created_at AT TIME ZONE 'Asia/Kolkata', 'dd MMM yyyy'),
        'commissions', v_commissions,
        'advances', v_advances,
        'adjustments', v_adjustments
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_paid_salary_draft_details(UUID) TO anon, authenticated, service_role;
