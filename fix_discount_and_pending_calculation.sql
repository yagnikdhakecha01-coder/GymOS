-- =========================================================================
-- FIX: Discount Amount and Pending Amount Calculation
--
-- PROBLEM:
-- When a member was assigned a plan with a discount (e.g. ₹12000 plan with ₹1000 discount,
-- paying ₹2500 today), the database trigger `fn_on_member_plan_changed` inserted a row in 
-- `member_memberships` using the raw plan price (`12000.00`) instead of deducting the 
-- discount (`11000.00`).
-- Because `member_memberships.pending_amount` is generated as `(total_amount - paid_amount)`,
-- it became 12000 - 2500 = 9500 instead of 8500.
-- This in turn triggered `update_member_pending_amount` and `fn_sync_member_payment_status`
-- which overwrote `members.pending_amount` with 9500, wiping out the 1000 discount on UI.
--
-- SOLUTION:
-- 1. Updated `fn_on_member_plan_changed` to subtract `NEW.discount_amount` when inserting
--    or updating `member_memberships.total_amount`.
-- 2. Updated `fn_force_member_payment_recalc` to keep initial values when member_memberships
--    does not exist yet.
-- 3. Updated `sync_member_payment_amounts` RPC to sync net `total_amount = received + pending`.
-- 4. Corrected all existing database records where discount_amount > 0.
-- =========================================================================

-- 1. Function: fn_on_member_plan_changed
CREATE OR REPLACE FUNCTION public.fn_on_member_plan_changed()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_price NUMERIC(12,2);
    v_duration_days INT;
    v_net_total NUMERIC(12,2);
    v_latest_mm_id UUID;
BEGIN
    IF NEW.membership_plan_id IS NOT NULL THEN
        SELECT 
            COALESCE(price, 0.0),
            COALESCE(duration_days, COALESCE(duration_months, 1) * 30, 30)::INTEGER
        INTO v_plan_price, v_duration_days
        FROM public.membership_plans 
        WHERE id = NEW.membership_plan_id 
        LIMIT 1;

        -- True net total is plan price minus discount
        v_net_total := GREATEST(0.0, COALESCE(v_plan_price, 0.0) - COALESCE(NEW.discount_amount, 0.0));

        -- Case 1: Plan changed or new plan assigned
        IF (OLD IS NULL OR NEW.membership_plan_id IS DISTINCT FROM OLD.membership_plan_id) THEN
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
                NEW.id,
                NEW.membership_plan_id,
                CURRENT_DATE,
                CURRENT_DATE + v_duration_days,
                v_net_total,
                COALESCE(NEW.total_received_amount, 0.0),
                CASE 
                    WHEN COALESCE(NEW.total_received_amount, 0.0) >= v_net_total THEN 'Fully Paid'
                    WHEN COALESCE(NEW.total_received_amount, 0.0) > 0 THEN 'Partial'
                    ELSE 'Unpaid'
                END
            );
        -- Case 2: Discount amount was updated for current plan
        ELSIF (OLD IS NOT NULL AND NEW.discount_amount IS DISTINCT FROM OLD.discount_amount) THEN
            SELECT id INTO v_latest_mm_id
            FROM public.member_memberships
            WHERE member_id = NEW.id
            ORDER BY created_at DESC
            LIMIT 1;

            IF v_latest_mm_id IS NOT NULL THEN
                UPDATE public.member_memberships
                SET total_amount = v_net_total,
                    updated_at = NOW()
                WHERE id = v_latest_mm_id;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Function: fn_force_member_payment_recalc
CREATE OR REPLACE FUNCTION public.fn_force_member_payment_recalc()
RETURNS TRIGGER AS $$
DECLARE
    v_mm_count INT;
BEGIN
    SELECT COUNT(*) INTO v_mm_count
    FROM public.member_memberships
    WHERE member_id = NEW.id;

    IF v_mm_count > 0 THEN
        -- Recalculate total remaining dues for this member from member_memberships
        SELECT COALESCE(SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0))), 0.0)
        INTO NEW.pending_amount
        FROM public.member_memberships
        WHERE member_id = NEW.id;

        -- Recalculate total received amount for this member from member_memberships
        SELECT COALESCE(SUM(COALESCE(paid_amount, 0.0)), 0.0)
        INTO NEW.total_received_amount
        FROM public.member_memberships
        WHERE member_id = NEW.id;

        NEW.payment_status := CASE WHEN NEW.pending_amount <= 0 THEN 'Paid' ELSE 'Pending' END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. RPC: sync_member_payment_amounts
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
BEGIN
    SELECT id INTO v_mm_id
    FROM public.member_memberships
    WHERE member_id = p_member_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_mm_id IS NOT NULL THEN
        UPDATE public.member_memberships
        SET total_amount = (p_new_total_received + p_new_pending_amount),
            paid_amount = p_new_total_received,
            payment_status = CASE 
                WHEN p_new_pending_amount <= 0 THEN 'Fully Paid'
                ELSE 'Partially Paid'
            END,
            updated_at = NOW()
        WHERE id = v_mm_id;
    END IF;

    UPDATE public.members
    SET total_received_amount = p_new_total_received,
        pending_amount = p_new_pending_amount,
        payment_status = CASE WHEN p_new_pending_amount <= 0 THEN 'Paid' ELSE 'Pending' END
    WHERE id = p_member_id;
END;
$$ LANGUAGE plpgsql;

-- 4. Correct all existing records
UPDATE public.member_memberships mm
SET total_amount = COALESCE(p.price, mm.total_amount) - m.discount_amount,
    updated_at = NOW()
FROM public.members m
LEFT JOIN public.membership_plans p ON m.membership_plan_id = p.id
WHERE mm.member_id = m.id
  AND m.discount_amount > 0
  AND mm.payment_status != 'Fully Paid'
  AND mm.total_amount = COALESCE(p.price, mm.total_amount);
