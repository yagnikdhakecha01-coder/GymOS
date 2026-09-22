-- Migration: 20260922_sync_finance_and_member_transactions.sql
-- Description: Automatically synchronizes member balances and staff salary dues
-- when finance transactions are inserted, updated, or deleted.

CREATE OR REPLACE FUNCTION public.sync_member_balances_from_transactions(p_member_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_paid NUMERIC(12,2) := 0.0;
    v_mm_id UUID;
    v_total_amount NUMERIC(12,2) := 0.0;
    v_pending NUMERIC(12,2) := 0.0;
    v_status TEXT := 'Pending';
BEGIN
    IF p_member_id IS NULL THEN
        RETURN;
    END IF;

    -- 1. Calculate the exact sum of all membership revenue transactions for this member
    SELECT COALESCE(SUM(amount), 0.0)
    INTO v_total_paid
    FROM public.finance_transactions
    WHERE type = 'Revenue'
      AND category = 'Membership'
      AND reference_id = p_member_id::TEXT;

    -- 2. Fetch the most recent member_memberships record
    SELECT id, COALESCE(total_amount, 0.0)
    INTO v_mm_id, v_total_amount
    FROM public.member_memberships
    WHERE member_id = p_member_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- If no membership record exists, get total_amount from member's received + pending
    IF v_mm_id IS NULL THEN
        SELECT COALESCE(total_received_amount, 0.0) + COALESCE(pending_amount, 0.0)
        INTO v_total_amount
        FROM public.members
        WHERE id = p_member_id;
    END IF;

    -- Ensure total_amount is at least total_paid
    IF v_total_amount IS NULL OR v_total_amount < v_total_paid THEN
        v_total_amount := v_total_paid;
    END IF;

    v_pending := GREATEST(0.0, v_total_amount - v_total_paid);
    v_status := CASE 
        WHEN v_pending <= 0.0 THEN 'Paid'
        WHEN v_total_paid > 0.0 THEN 'Partial'
        ELSE 'Pending'
    END;

    -- 3. Update member_memberships if exists (Note: pending_amount is a generated column ALWAYS AS (total_amount - paid_amount))
    IF v_mm_id IS NOT NULL THEN
        UPDATE public.member_memberships
        SET total_amount = v_total_amount,
            paid_amount = v_total_paid,
            payment_status = CASE WHEN (v_total_amount - v_total_paid) <= 0.0 THEN 'Fully Paid' ELSE 'Partially Paid' END,
            updated_at = NOW()
        WHERE id = v_mm_id;
    END IF;

    -- 4. Update members table
    UPDATE public.members
    SET total_received_amount = v_total_paid,
        pending_amount = v_pending,
        payment_status = v_status
    WHERE id = p_member_id;
END;
$$;

-- Trigger function for UPDATE and DELETE on finance_transactions
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_updated_or_deleted()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_old_ref_uuid UUID;
    v_new_ref_uuid UUID;
    v_delta NUMERIC(12,2);
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- Check if amount, category, type, or reference_id changed
        IF (OLD.amount IS DISTINCT FROM NEW.amount)
           OR (OLD.category IS DISTINCT FROM NEW.category)
           OR (OLD.type IS DISTINCT FROM NEW.type)
           OR (OLD.reference_id IS DISTINCT FROM NEW.reference_id) THEN
           
            -- Handle Membership Revenue Synchronization
            IF (OLD.type = 'Revenue' AND OLD.category = 'Membership') 
               OR (NEW.type = 'Revenue' AND NEW.category = 'Membership') THEN
               
                IF OLD.reference_id IS NOT NULL AND OLD.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_old_ref_uuid := OLD.reference_id::UUID;
                    PERFORM public.sync_member_balances_from_transactions(v_old_ref_uuid);
                END IF;

                IF NEW.reference_id IS NOT NULL AND NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_new_ref_uuid := NEW.reference_id::UUID;
                    IF v_new_ref_uuid IS DISTINCT FROM v_old_ref_uuid THEN
                        PERFORM public.sync_member_balances_from_transactions(v_new_ref_uuid);
                    END IF;
                END IF;
            END IF;

            -- Handle Staff Salary Expense Synchronization
            IF (OLD.type = 'Expense' AND OLD.category = 'Salary') 
               OR (NEW.type = 'Expense' AND NEW.category = 'Salary') THEN
               
                IF OLD.reference_id IS NOT NULL AND OLD.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_old_ref_uuid := OLD.reference_id::UUID;
                END IF;
                IF NEW.reference_id IS NOT NULL AND NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                    v_new_ref_uuid := NEW.reference_id::UUID;
                END IF;

                IF v_old_ref_uuid IS NOT NULL AND v_old_ref_uuid = v_new_ref_uuid THEN
                    v_delta := COALESCE(NEW.amount, 0.0) - COALESCE(OLD.amount, 0.0);
                    UPDATE public.staff
                    SET salary_due = GREATEST(0.0, COALESCE(salary_due, 0.0) - v_delta)
                    WHERE id = v_old_ref_uuid;
                ELSE
                    IF v_old_ref_uuid IS NOT NULL THEN
                        UPDATE public.staff
                        SET salary_due = COALESCE(salary_due, 0.0) + COALESCE(OLD.amount, 0.0)
                        WHERE id = v_old_ref_uuid;
                    END IF;
                    IF v_new_ref_uuid IS NOT NULL THEN
                        UPDATE public.staff
                        SET salary_due = GREATEST(0.0, COALESCE(salary_due, 0.0) - COALESCE(NEW.amount, 0.0))
                        WHERE id = v_new_ref_uuid;
                    END IF;
                END IF;
            END IF;
        END IF;

        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        -- Handle Membership Revenue Deletion
        IF OLD.type = 'Revenue' AND OLD.category = 'Membership' THEN
            IF OLD.reference_id IS NOT NULL AND OLD.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                v_old_ref_uuid := OLD.reference_id::UUID;
                PERFORM public.sync_member_balances_from_transactions(v_old_ref_uuid);
            END IF;
        END IF;

        -- Handle Staff Salary Deletion
        IF OLD.type = 'Expense' AND OLD.category = 'Salary' THEN
            IF OLD.reference_id IS NOT NULL AND OLD.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
                v_old_ref_uuid := OLD.reference_id::UUID;
                UPDATE public.staff
                SET salary_due = COALESCE(salary_due, 0.0) + COALESCE(OLD.amount, 0.0)
                WHERE id = v_old_ref_uuid;
            END IF;
        END IF;

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

-- Create Trigger for UPDATE and DELETE
DROP TRIGGER IF EXISTS trg_on_finance_transaction_updated_or_deleted ON public.finance_transactions;
CREATE TRIGGER trg_on_finance_transaction_updated_or_deleted
AFTER UPDATE OR DELETE ON public.finance_transactions
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_finance_transaction_updated_or_deleted();
