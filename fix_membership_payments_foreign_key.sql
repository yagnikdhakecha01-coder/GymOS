-- =========================================================================
-- DATABASE MIGRATION: fix_membership_payments_foreign_key.sql
-- Run this script in your Supabase SQL Editor to fix the foreign key constraint
-- error on membership payments when using the offline-first sync engine.
-- =========================================================================

-- 1. Drop the foreign key constraint that references the old transactions table
-- (Since membership payments now reference finance_transactions during sync, 
-- this constraint is relaxed to allow storing finance_transactions UUIDs safely).
ALTER TABLE public.membership_payments 
DROP CONSTRAINT IF EXISTS membership_payments_transaction_id_fkey;

-- 2. Update the trigger function on membership_payments to bypass duplicate
-- transaction creation if transaction_id is already assigned by the sync engine.
CREATE OR REPLACE FUNCTION public.fn_generate_membership_transaction()
RETURNS TRIGGER AS $$
DECLARE
    m_name TEXT;
    p_title TEXT;
    t_id UUID;
BEGIN
    -- If transaction_id is already set (e.g. set to the finance_transactions ID from the sync engine),
    -- update the paid_amount / status of member_memberships and return immediately.
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

    -- Insert Transaction record into old transactions table
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
