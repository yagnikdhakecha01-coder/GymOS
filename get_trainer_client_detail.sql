-- =========================================================================
-- RPC: get_trainer_client_detail
-- Staff client detail page ke liye — membership dates, measurements, commission
-- Supabase SQL Editor mein RUN karo
-- =========================================================================

CREATE OR REPLACE FUNCTION public.get_trainer_client_detail(
    p_staff_id UUID,
    p_member_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
    v_comm_rate NUMERIC(5,2) := 0;
    v_comm_earned NUMERIC(12,2) := 0;
    v_comm_pending NUMERIC(12,2) := 0;
    v_member_received NUMERIC(12,2) := 0;
BEGIN
    -- Verify this member belongs to this trainer
    IF NOT EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.id = p_member_id
          AND (
              m.pt_trainer = p_staff_id
              OR EXISTS (
                  SELECT 1 FROM public.pt_assignments pa
                  WHERE pa.member_id = p_member_id
                    AND pa.staff_id = p_staff_id
                    AND pa.assignment_status = 'Active'
              )
          )
    ) THEN
        RETURN NULL;
    END IF;

    -- Commission rate from active PT assignment or staff default
    SELECT COALESCE(pa.commission_percentage, s.commission_percentage, 0)
    INTO v_comm_rate
    FROM public.members m
    JOIN public.staff s ON s.id = p_staff_id
    LEFT JOIN public.pt_assignments pa
        ON pa.member_id = m.id AND pa.staff_id = p_staff_id AND pa.assignment_status = 'Active'
    WHERE m.id = p_member_id
    LIMIT 1;

    -- Member payments received (commission calculation base — NOT plan price)
    SELECT COALESCE(m.total_received_amount, 0)
    INTO v_member_received
    FROM public.members m
    WHERE m.id = p_member_id;

    -- Commission earned from ledger for this member + staff
    SELECT
        COALESCE(SUM(CASE WHEN cl.status IN ('Paid', 'Pending') THEN cl.amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN cl.status = 'Pending' THEN cl.amount ELSE 0 END), 0)
    INTO v_comm_earned, v_comm_pending
    FROM public.commission_ledger cl
    WHERE cl.staff_id = p_staff_id
      AND cl.member_id = p_member_id;

    -- Fallback: calculate from received * rate if no ledger entries yet
    IF v_comm_earned = 0 AND v_member_received > 0 AND v_comm_rate > 0 THEN
        v_comm_earned := ROUND(v_member_received * v_comm_rate / 100.0, 2);
        v_comm_pending := v_comm_earned;
    END IF;

    SELECT jsonb_build_object(
        'member_id', m.id,
        'member_name', m.name,
        'member_email', COALESCE(m.email, ''),
        'member_phone', COALESCE(m.phone, ''),
        'member_avatar', COALESCE(m.avatar, ''),
        'member_status', m.status,
        'join_date', COALESCE(m.join_date, ''),
        'expiry_date', COALESCE(m.extra_fields->>'expiryDate', ''),
        'membership_plan_id', m.membership_plan_id,
        'membership_plan_name', COALESCE(mp.title, 'Membership Plan'),
        'medical_details', COALESCE(m.medical_details, ''),
        'notes', COALESCE(m.notes, ''),
        'extra_fields', COALESCE(m.extra_fields, '{}'::jsonb),
        'payment_status', COALESCE(m.payment_status, 'Pending'),
        'member_payments_received', v_member_received,
        'commission_rate', v_comm_rate,
        'commission_earned', v_comm_earned,
        'commission_pending', v_comm_pending,
        'assignment_status', COALESCE(pa.assignment_status, 'Active'),
        'pt_start_date', COALESCE(pa.pt_start_date::text, m.join_date, '')
    )
    INTO v_result
    FROM public.members m
    LEFT JOIN public.membership_plans mp ON mp.id = m.membership_plan_id
    LEFT JOIN public.pt_assignments pa
        ON pa.member_id = m.id AND pa.staff_id = p_staff_id AND pa.assignment_status = 'Active'
    WHERE m.id = p_member_id;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_trainer_client_detail(UUID, UUID)
    TO anon, authenticated, service_role;

-- Staff body measurements update RPC
CREATE OR REPLACE FUNCTION public.update_member_measurements(
    p_staff_id UUID,
    p_member_id UUID,
    p_measurements JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_extra JSONB;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.id = p_member_id AND m.pt_trainer = p_staff_id
    ) AND NOT EXISTS (
        SELECT 1 FROM public.pt_assignments pa
        WHERE pa.member_id = p_member_id AND pa.staff_id = p_staff_id AND pa.assignment_status = 'Active'
    ) THEN
        RAISE EXCEPTION 'Not authorized to update this member';
    END IF;

    SELECT COALESCE(extra_fields, '{}'::jsonb) INTO v_extra
    FROM public.members WHERE id = p_member_id;

    v_extra := v_extra || jsonb_build_object('measurements', p_measurements);

    IF p_measurements ? 'weight' THEN
        v_extra := v_extra || jsonb_build_object('weight', p_measurements->'weight');
    END IF;
    IF p_measurements ? 'height' THEN
        v_extra := v_extra || jsonb_build_object('height', p_measurements->'height');
    END IF;

    UPDATE public.members
    SET extra_fields = v_extra
    WHERE id = p_member_id;

    RETURN v_extra;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_member_measurements(UUID, UUID, JSONB)
    TO anon, authenticated, service_role;
