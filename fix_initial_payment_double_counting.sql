-- =========================================================================
-- DATABASE MIGRATION: fix_initial_payment_double_counting.sql
--
-- FIX: Prevents double-counting member initial payment when adding a member.
--
-- ROOT CAUSE:
-- When a member is created:
-- 1. `members` row is inserted with `total_received_amount = paidToday`.
-- 2. Trigger `trg_on_member_plan_changed` creates a row in `member_memberships`
--    with `paid_amount = NEW.total_received_amount`.
-- 3. The client app inserts an initial payment transaction into `finance_transactions`
--    with notes = 'Automatic Membership Initial Payment'.
-- 4. Trigger `trg_on_finance_transaction_inserted` was adding `NEW.amount` again
--    to `member_memberships.paid_amount`, causing the initial payment to double
--    (e.g., ₹1000 became ₹2000, and pending dues dropped from ₹11000 to ₹10000).
-- 5. Trigger `trg_sync_member_payment_status` then synced the doubled ₹2000 back
--    into `members.total_received_amount`.
--
-- SOLUTION:
-- In `fn_on_finance_transaction_inserted()`, if the transaction is an initial
-- registration payment ('Automatic Membership Initial Payment', '%Initial Payment%',
-- or '%Old Member Import%'), do not add `NEW.amount` again since it was already
-- initialized by `fn_on_member_plan_changed`. Subsequent dues payments continue
-- to add correctly.
-- =========================================================================

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
            -- Check if this transaction is an initial registration payment
            IF (NEW.notes = 'Automatic Membership Initial Payment' 
                OR NEW.notes LIKE '%Initial Payment%' 
                OR NEW.notes LIKE '%Old Member Import%') THEN
                -- Initial payment was already set when member_memberships was created.
                -- Do NOT double-add; ensure paid_amount is at least NEW.amount.
                UPDATE public.member_memberships
                SET paid_amount = GREATEST(COALESCE(paid_amount, 0), NEW.amount),
                    payment_status = CASE 
                        WHEN GREATEST(COALESCE(paid_amount, 0), NEW.amount) >= total_amount THEN 'Paid' 
                        WHEN GREATEST(COALESCE(paid_amount, 0), NEW.amount) > 0 THEN 'Partial'
                        ELSE 'Pending' 
                    END,
                    updated_at = NOW()
                WHERE id = v_member_membership_id;
            ELSE
                -- Subsequent payment (e.g. paying dues via Receive Payment)
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
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on finance_transactions
DROP TRIGGER IF EXISTS trg_on_finance_transaction_inserted ON public.finance_transactions;
CREATE TRIGGER trg_on_finance_transaction_inserted
AFTER INSERT ON public.finance_transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_on_finance_transaction_inserted();

-- Fix Nihar Ramani record
UPDATE public.member_memberships
SET paid_amount = 1000.00,
    total_amount = 12000.00,
    payment_status = 'Partial',
    updated_at = NOW()
WHERE member_id = 'c690adc7-704e-49a0-9760-7c3438ddd37d';

UPDATE public.members
SET total_received_amount = 1000.00,
    pending_amount = 11000.00,
    payment_status = 'Pending'
WHERE id = 'c690adc7-704e-49a0-9760-7c3438ddd37d';
