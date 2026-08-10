-- ====================================================================
-- GYMOS: AUTOMATIC MEMBER PAYMENT STATUS & PENDING DUES SYNC
-- ====================================================================

-- 1. TRIGGER FUNCTION: Synchronize pending_amount and payment_status on members table
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

DROP TRIGGER IF EXISTS trg_sync_member_payment_status ON public.member_memberships;
CREATE TRIGGER trg_sync_member_payment_status
AFTER INSERT OR UPDATE OR DELETE ON public.member_memberships
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_member_payment_status();


-- 2. RPC FUNCTION: Get Member Cards with Payment Status & Fees Due
DROP FUNCTION IF EXISTS public.get_owner_member_cards_v1(UUID);

CREATE OR REPLACE FUNCTION public.get_owner_member_cards_v1(p_gym_id UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    phone TEXT,
    avatar TEXT,
    status TEXT,
    join_date TEXT,
    next_due_date TEXT,
    pending_amount NUMERIC,
    payment_status TEXT,
    is_paid BOOLEAN
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.id,
        m.name,
        COALESCE(m.phone, '') AS phone,
        COALESCE(m.avatar, '') AS avatar,
        COALESCE(m.status, 'Active') AS status,
        COALESCE(to_char(m.created_at, 'DD Mon YYYY'), '') AS join_date,
        COALESCE(
            (
                SELECT to_char(mm.end_date, 'DD Mon YYYY')
                FROM public.member_memberships mm
                WHERE mm.member_id = m.id AND mm.status = 'Active'
                ORDER BY mm.end_date DESC
                LIMIT 1
            ), 
            'N/A'
        ) AS next_due_date,
        COALESCE(m.pending_amount, 0.0)::NUMERIC AS pending_amount,
        CASE WHEN COALESCE(m.pending_amount, 0.0) <= 0 THEN 'Paid' ELSE 'Pending' END AS payment_status,
        (COALESCE(m.pending_amount, 0.0) <= 0) AS is_paid
    FROM public.members m
    WHERE m.gym_id = p_gym_id
    ORDER BY m.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_owner_member_cards_v1(UUID) TO anon, authenticated, service_role;
