-- =========================================================================
-- DATABASE MIGRATION: fix_payment_received_reset_bug.sql
-- 
-- FIXES: Member payment card (Final Amount, Received, Pending) values
-- reset to initial values after app restart.
--
-- ROOT CAUSE: fn_on_finance_transaction_inserted creates member_memberships
-- with total_amount = payment_amount (WRONG), causing fn_sync_member_payment_status
-- to overwrite members.total_received_amount and pending_amount with wrong values.
--
-- Run this in Supabase SQL Editor.
-- =========================================================================

-- =========================================================================
-- STEP 1: Fix fn_on_finance_transaction_inserted
-- When auto-creating member_memberships, use actual plan price minus discount
-- from members table, NOT the payment amount.
-- =========================================================================
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
    v_actual_total_amount NUMERIC(12,2);
    v_plan_price NUMERIC(12,2);
    v_discount NUMERIC(12,2);
    v_plan_id TEXT;
    v_duration_days INT;
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

        -- If no active membership plan exists, create one with CORRECT total_amount
        IF v_member_membership_id IS NULL THEN
            -- Get the member's actual plan info and discount
            SELECT 
                m.membership_plan_id,
                COALESCE(m.discount_amount, 0.0),
                COALESCE(m.total_received_amount, 0.0) + COALESCE(m.pending_amount, 0.0)
            INTO v_plan_id, v_discount, v_actual_total_amount
            FROM public.members m
            WHERE m.id = v_ref_uuid;

            -- Get plan price
            SELECT COALESCE(p.price, 0.0), COALESCE(p.duration_days, COALESCE(p.duration_months, 1) * 30)
            INTO v_plan_price, v_duration_days
            FROM public.membership_plans p
            WHERE p.id = v_plan_id;

            -- Use actual total (received + pending) from members table as the true total_amount
            -- This is the most accurate because the app calculates it correctly
            -- Fallback to plan_price - discount if members table values are 0
            IF v_actual_total_amount IS NULL OR v_actual_total_amount <= 0 THEN
                v_actual_total_amount := COALESCE(v_plan_price, NEW.amount) - COALESCE(v_discount, 0.0);
            END IF;

            -- Ensure total_amount is at least the payment amount
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
            )
            VALUES (
                NEW.gym_id,
                v_ref_uuid,
                COALESCE(v_plan_id, (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1)),
                CURRENT_DATE,
                CURRENT_DATE + (COALESCE(v_duration_days, 30) || ' days')::INTERVAL,
                v_actual_total_amount,
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


-- =========================================================================
-- STEP 2: Fix fn_sync_member_payment_status
-- Use members table (total_received_amount + pending_amount) as truth
-- when member_memberships total_amount seems corrupted.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.fn_sync_member_payment_status()
RETURNS TRIGGER AS $$
DECLARE
    v_member_id UUID;
    v_total_pending NUMERIC(12,2) := 0.0;
    v_total_received NUMERIC(12,2) := 0.0;
    v_mm_count INT := 0;
BEGIN
    v_member_id := COALESCE(NEW.member_id, OLD.member_id);
    IF v_member_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Count how many member_memberships exist for this member
    SELECT COUNT(*) INTO v_mm_count
    FROM public.member_memberships
    WHERE member_id = v_member_id;

    IF v_mm_count > 0 THEN
        -- Calculate total remaining dues from member_memberships
        SELECT COALESCE(SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0))), 0.0)
        INTO v_total_pending
        FROM public.member_memberships
        WHERE member_id = v_member_id;

        -- Calculate total received from member_memberships
        SELECT COALESCE(SUM(COALESCE(paid_amount, 0.0)), 0.0)
        INTO v_total_received
        FROM public.member_memberships
        WHERE member_id = v_member_id;

        UPDATE public.members
        SET pending_amount = v_total_pending,
            total_received_amount = v_total_received,
            payment_status = CASE WHEN v_total_pending <= 0 THEN 'Paid' ELSE 'Pending' END
        WHERE id = v_member_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on member_memberships
DROP TRIGGER IF EXISTS trg_sync_member_payment_status ON public.member_memberships;
CREATE TRIGGER trg_sync_member_payment_status
AFTER INSERT OR UPDATE OR DELETE ON public.member_memberships
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_member_payment_status();


-- =========================================================================
-- STEP 3: Fix existing corrupted member_memberships data
-- Correct total_amount using plan price - discount for all existing records
-- =========================================================================
UPDATE public.member_memberships mm
SET total_amount = GREATEST(
    COALESCE(
        -- Use members table total (received + pending) as source of truth
        (SELECT COALESCE(m.total_received_amount, 0.0) + COALESCE(m.pending_amount, 0.0)
         FROM public.members m
         WHERE m.id = mm.member_id),
        -- Fallback: plan price - discount
        (SELECT COALESCE(p.price, 0.0) - COALESCE(
            (SELECT COALESCE(m2.discount_amount, 0.0) FROM public.members m2 WHERE m2.id = mm.member_id),
            0.0
        )
         FROM public.membership_plans p
         WHERE p.id = mm.plan_id),
        mm.total_amount
    ),
    mm.paid_amount  -- total_amount must be >= paid_amount
)
WHERE mm.total_amount < (
    SELECT COALESCE(p.price, 0.0) - COALESCE(
        (SELECT COALESCE(m3.discount_amount, 0.0) FROM public.members m3 WHERE m3.id = mm.member_id),
        0.0
    )
    FROM public.membership_plans p
    WHERE p.id = mm.plan_id
);


-- =========================================================================
-- STEP 4: Re-sync all member payment statuses from corrected data
-- =========================================================================
UPDATE public.members m
SET total_received_amount = COALESCE((
        SELECT SUM(COALESCE(paid_amount, 0.0))
        FROM public.member_memberships mm
        WHERE mm.member_id = m.id
    ), m.total_received_amount),
    pending_amount = COALESCE((
        SELECT SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0)))
        FROM public.member_memberships mm
        WHERE mm.member_id = m.id
    ), m.pending_amount),
    payment_status = CASE 
        WHEN COALESCE((
            SELECT SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0)))
            FROM public.member_memberships mm
            WHERE mm.member_id = m.id
        ), m.pending_amount) <= 0 THEN 'Paid'
        ELSE 'Pending'
    END
WHERE EXISTS (
    SELECT 1 FROM public.member_memberships mm WHERE mm.member_id = m.id
);

-- =========================================================================
-- STEP 5: Create RPC function for app-side payment sync
-- Called by the app after recording a payment to directly update
-- member_memberships.paid_amount, ensuring consistency.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.sync_member_payment_amounts(
    p_member_id UUID,
    p_gym_id UUID,
    p_payment_amount NUMERIC,
    p_new_total_received NUMERIC,
    p_new_pending_amount NUMERIC
)
RETURNS VOID AS $$
DECLARE
    v_mm_id UUID;
    v_current_paid NUMERIC(12,2);
    v_total_amount NUMERIC(12,2);
BEGIN
    -- Find the most recent member_memberships record
    SELECT id, COALESCE(paid_amount, 0.0), COALESCE(total_amount, 0.0)
    INTO v_mm_id, v_current_paid, v_total_amount
    FROM public.member_memberships
    WHERE member_id = p_member_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_mm_id IS NOT NULL THEN
        -- Fix total_amount if it's less than what it should be
        IF v_total_amount < (p_new_total_received + p_new_pending_amount) THEN
            UPDATE public.member_memberships
            SET total_amount = (p_new_total_received + p_new_pending_amount)
            WHERE id = v_mm_id;
        END IF;

        -- Update paid_amount to match app's calculated total received
        -- Use app's total received as source of truth
        UPDATE public.member_memberships
        SET paid_amount = p_new_total_received,
            payment_status = CASE 
                WHEN p_new_pending_amount <= 0 THEN 'Fully Paid'
                ELSE 'Partially Paid'
            END
        WHERE id = v_mm_id;
    END IF;

    -- Directly update the members table to ensure consistency
    -- This runs AFTER the member_memberships trigger would fire
    UPDATE public.members
    SET total_received_amount = p_new_total_received,
        pending_amount = p_new_pending_amount,
        payment_status = CASE WHEN p_new_pending_amount <= 0 THEN 'Paid' ELSE 'Pending' END
    WHERE id = p_member_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.sync_member_payment_amounts(UUID, UUID, NUMERIC, NUMERIC, NUMERIC) TO anon, authenticated, service_role;


-- =========================================================================
-- DONE! All triggers fixed, existing data corrected, RPC function deployed.
-- =========================================================================
