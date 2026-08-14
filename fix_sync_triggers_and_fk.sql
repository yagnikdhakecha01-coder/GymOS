-- =========================================================================
-- COMPLETE SAFE FIX FOR MEMBER_MEMBERSHIPS
-- Run this in Supabase SQL Editor.
-- =========================================================================

-- 1. Drop check constraint completely so payment_status never blocks transactions
ALTER TABLE public.member_memberships DROP CONSTRAINT IF EXISTS member_memberships_payment_status_check;
ALTER TABLE public.member_memberships DROP CONSTRAINT IF EXISTS chk_membership_payment_status;

-- 2. Normalize any null or blank existing rows
UPDATE public.member_memberships 
SET payment_status = 'Pending' 
WHERE payment_status IS NULL OR payment_status = '';

-- 3. Ensure updated_at column exists
ALTER TABLE public.member_memberships ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- 4. Ensure plan_id is nullable
ALTER TABLE public.member_memberships ALTER COLUMN plan_id DROP NOT NULL;

-- 5. Create or replace fn_on_finance_transaction_inserted trigger function
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_inserted()
RETURNS TRIGGER AS $$
DECLARE
    v_member_membership_id UUID;
    v_ref_uuid UUID;
    v_actual_total_amount NUMERIC(12,2);
    v_plan_price NUMERIC(12,2);
    v_discount NUMERIC(12,2);
    v_plan_id TEXT;
    v_duration_days INT;
BEGIN
    IF NEW.type = 'Revenue' AND NEW.category = 'Membership' AND NEW.reference_id IS NOT NULL THEN
        IF NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_ref_uuid := NEW.reference_id::UUID;
        ELSE
            RETURN NEW;
        END IF;

        SELECT id INTO v_member_membership_id 
        FROM public.member_memberships 
        WHERE member_id = v_ref_uuid
        ORDER BY created_at DESC 
        LIMIT 1;

        IF v_member_membership_id IS NULL THEN
            SELECT 
                m.membership_plan_id,
                COALESCE(m.discount_amount, 0.0),
                COALESCE(m.total_received_amount, 0.0) + COALESCE(m.pending_amount, 0.0)
            INTO v_plan_id, v_discount, v_actual_total_amount
            FROM public.members m
            WHERE m.id = v_ref_uuid;

            IF v_plan_id IS NOT NULL THEN
                SELECT COALESCE(p.price, 0.0), COALESCE(p.duration_days, COALESCE(p.duration_months, 1) * 30)
                INTO v_plan_price, v_duration_days
                FROM public.membership_plans p
                WHERE p.id = v_plan_id;
            END IF;

            IF v_actual_total_amount IS NULL OR v_actual_total_amount <= 0 THEN
                v_actual_total_amount := COALESCE(v_plan_price, NEW.amount) - COALESCE(v_discount, 0.0);
            END IF;

            IF v_actual_total_amount < NEW.amount THEN
                v_actual_total_amount := NEW.amount;
            END IF;

            INSERT INTO public.member_memberships (
                gym_id,
                member_id,
                plan_id,
                start_date,
                end_date,
                total_amount,
                paid_amount,
                payment_status
            ) VALUES (
                NEW.gym_id,
                v_ref_uuid,
                COALESCE(v_plan_id, 'Custom'),
                CURRENT_DATE,
                CURRENT_DATE + (COALESCE(v_duration_days, 30) || ' days')::INTERVAL,
                v_actual_total_amount,
                NEW.amount,
                CASE 
                    WHEN v_actual_total_amount <= NEW.amount THEN 'Paid' 
                    WHEN NEW.amount > 0 THEN 'Partial'
                    ELSE 'Pending' 
                END
            );
        ELSE
            UPDATE public.member_memberships
            SET paid_amount = COALESCE(paid_amount, 0) + NEW.amount,
                payment_status = CASE 
                    WHEN (COALESCE(paid_amount, 0) + NEW.amount) >= total_amount THEN 'Paid' 
                    WHEN (COALESCE(paid_amount, 0) + NEW.amount) > 0 THEN 'Partial'
                    ELSE 'Pending' 
                END,
                updated_at = NOW()
            WHERE id = v_member_membership_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
