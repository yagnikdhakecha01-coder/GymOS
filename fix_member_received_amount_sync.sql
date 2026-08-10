-- =========================================================================
-- DATABASE MIGRATION: fix_member_received_amount_sync.sql
-- Run this script in your Supabase SQL Editor to sync received/pending amounts
-- and deploy the automatic sync trigger.
-- =========================================================================

-- 1. Redeploy the automatic sync trigger function to include total_received_amount
CREATE OR REPLACE FUNCTION public.fn_sync_member_payment_status()
RETURNS TRIGGER AS $$
DECLARE
    v_member_id UUID;
    v_total_pending NUMERIC(12,2) := 0.0;
    v_total_received NUMERIC(12,2) := 0.0;
BEGIN
    v_member_id := COALESCE(NEW.member_id, OLD.member_id);
    IF v_member_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Calculate total remaining dues for this member from member_memberships
    SELECT COALESCE(SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0))), 0.0)
    INTO v_total_pending
    FROM public.member_memberships
    WHERE member_id = v_member_id;

    -- Calculate total received amount for this member from member_memberships
    SELECT COALESCE(SUM(COALESCE(paid_amount, 0.0)), 0.0)
    INTO v_total_received
    FROM public.member_memberships
    WHERE member_id = v_member_id;

    UPDATE public.members
    SET pending_amount = v_total_pending,
        total_received_amount = v_total_received,
        payment_status = CASE WHEN v_total_pending <= 0 THEN 'Paid' ELSE 'Pending' END
    WHERE id = v_member_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on member_memberships
DROP TRIGGER IF EXISTS trg_sync_member_payment_status ON public.member_memberships;
CREATE TRIGGER trg_sync_member_payment_status
AFTER INSERT OR UPDATE OR DELETE ON public.member_memberships
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_member_payment_status();

-- 2. One-time update to synchronize existing members' received and pending balances
UPDATE public.members m
SET total_received_amount = COALESCE((
        SELECT SUM(COALESCE(paid_amount, 0.0))
        FROM public.member_memberships mm
        WHERE mm.member_id = m.id
    ), 0.0),
    pending_amount = COALESCE((
        SELECT SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0)))
        FROM public.member_memberships mm
        WHERE mm.member_id = m.id
    ), 0.0);
