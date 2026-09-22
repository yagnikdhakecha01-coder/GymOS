-- =============================================================================
-- GYMOS COMPREHENSIVE SECURITY PATCH V2 (ZERO DATA LOSS)
-- =============================================================================
-- PURPOSE:
--   1. Close all remaining multi-tenant data leaks in leave_requests,
--      salary_advance_ledger, payments, invoices, and subscriptions.
--   2. Enforce strict caller authorization inside get_trainer_clients,
--      update_member_measurements, and get_member_payment_transactions.
--   3. Revoke all unauthorized permissions from 'anon' role.
--   4. 100% Zero Data Loss, Zero Table Drops.
-- =============================================================================

BEGIN;

-- =============================================================================
-- PART 1: SECURE LEAVE REQUESTS & SALARY ADVANCES
-- =============================================================================

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leave_requests FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS leave_requests_permissive ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_owner_policy ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_staff_self ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_secure_policy ON public.leave_requests;

REVOKE ALL ON TABLE public.leave_requests FROM anon;

-- Secure combined policy: Admins/Owners of gym OR Staff member themselves
CREATE POLICY leave_requests_secure_policy ON public.leave_requests
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() 
          AND LOWER(role) IN ('owner', 'admin', 'gym_owner', 'super_admin')
    ) OR
    staff_id IN (
        SELECT id FROM public.staff WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() 
          AND LOWER(role) IN ('owner', 'admin', 'gym_owner', 'super_admin')
    ) OR
    staff_id IN (
        SELECT id FROM public.staff WHERE user_id = auth.uid()
    )
);


-- Secure salary_advance_ledger
ALTER TABLE public.salary_advance_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_advance_ledger FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS salary_advance_ledger_permissive ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_owner_policy ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_staff_self ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_secure_policy ON public.salary_advance_ledger;

REVOKE ALL ON TABLE public.salary_advance_ledger FROM anon;

CREATE POLICY salary_advance_ledger_secure_policy ON public.salary_advance_ledger
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() 
          AND LOWER(role) IN ('owner', 'admin', 'gym_owner', 'super_admin')
    ) OR
    staff_id IN (
        SELECT id FROM public.staff WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() 
          AND LOWER(role) IN ('owner', 'admin', 'gym_owner', 'super_admin')
    ) OR
    staff_id IN (
        SELECT id FROM public.staff WHERE user_id = auth.uid()
    )
);


-- =============================================================================
-- PART 2: SECURE PAYMENTS, INVOICES, SUBSCRIPTIONS & SUBSCRIPTION HISTORY
-- =============================================================================

-- 1. Payments Table
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payments_permissive ON public.payments;
DROP POLICY IF EXISTS payments_secure_policy ON public.payments;
REVOKE ALL ON TABLE public.payments FROM anon;

CREATE POLICY payments_secure_policy ON public.payments
FOR SELECT TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
);

-- Only Super Admins / Webhooks / System can insert or update payments
CREATE POLICY payments_modify_policy ON public.payments
FOR INSERT TO authenticated
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() 
          AND LOWER(role) IN ('owner', 'admin', 'gym_owner')
    )
);

-- 2. Invoices Table
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS invoices_permissive ON public.invoices;
DROP POLICY IF EXISTS invoices_secure_policy ON public.invoices;
REVOKE ALL ON TABLE public.invoices FROM anon;

CREATE POLICY invoices_secure_policy ON public.invoices
FOR SELECT TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
);

-- 3. Subscriptions Table
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS subscriptions_permissive ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_secure_policy ON public.subscriptions;
REVOKE ALL ON TABLE public.subscriptions FROM anon;

CREATE POLICY subscriptions_secure_policy ON public.subscriptions
FOR SELECT TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
);

-- Protect subscriptions from being altered by non-admin authenticated users
CREATE POLICY subscriptions_admin_modify ON public.subscriptions
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid())
)
WITH CHECK (
    public.is_admin(auth.uid())
);

-- 4. Subscription History Table
ALTER TABLE public.subscription_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_history FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS subscription_history_permissive ON public.subscription_history;
DROP POLICY IF EXISTS subscription_history_secure_policy ON public.subscription_history;
REVOKE ALL ON TABLE public.subscription_history FROM anon;

CREATE POLICY subscription_history_secure_policy ON public.subscription_history
FOR SELECT TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
);


-- =============================================================================
-- PART 3: HARDEN get_trainer_clients RPC (PREVENT PII EXFILTRATION)
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.get_trainer_clients(UUID) FROM anon, public;

CREATE OR REPLACE FUNCTION public.get_trainer_clients(p_staff_id UUID)
RETURNS TABLE (
    member_id UUID,
    member_name TEXT,
    member_email TEXT,
    member_phone TEXT,
    member_avatar TEXT,
    member_status TEXT,
    program TEXT,
    assignment_status TEXT,
    pt_start_date TEXT,
    membership_plan_id UUID,
    medical_details TEXT,
    notes TEXT,
    total_received_amount NUMERIC,
    pending_amount NUMERIC,
    discount_amount NUMERIC,
    payment_status TEXT,
    extra_fields JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_gym_id UUID;
    v_is_authorized BOOLEAN := false;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SECURITY ERROR: Authentication required (Code: 40121)';
    END IF;

    -- Fetch gym of this staff member
    SELECT gym_id INTO v_gym_id FROM public.staff WHERE id = p_staff_id;

    IF v_gym_id IS NULL THEN
        RETURN;
    END IF;

    -- Check if caller is the staff member themselves OR admin/owner of this gym
    SELECT (
        public.is_admin(v_caller_id) OR
        EXISTS (
            SELECT 1 FROM public.staff 
            WHERE id = p_staff_id AND user_id = v_caller_id
        ) OR
        EXISTS (
            SELECT 1 FROM public.user_gym_associations 
            WHERE user_id = v_caller_id 
              AND gym_id = v_gym_id 
              AND LOWER(role) IN ('owner', 'admin', 'gym_owner', 'super_admin')
        )
    ) INTO v_is_authorized;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'SECURITY ERROR: Unauthorized. You do not have permission to view clients of this staff member (Code: 40321)';
    END IF;

    RETURN QUERY
    SELECT DISTINCT ON (m.id)
        m.id AS member_id,
        m.name::text AS member_name,
        COALESCE(m.email, '')::text AS member_email,
        COALESCE(m.phone, '')::text AS member_phone,
        COALESCE(m.avatar, '')::text AS member_avatar,
        m.status::text AS member_status,
        ('PT - ' || COALESCE(pa.commission_percentage, s.commission_percentage, 0)::text || '% Comm.')::text AS program,
        COALESCE(pa.assignment_status, 'Active')::text AS assignment_status,
        COALESCE(pa.pt_start_date::text, m.join_date::text, '')::text AS pt_start_date,
        (CASE
            WHEN m.membership_plan_id IS NOT NULL
                 AND m.membership_plan_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            THEN m.membership_plan_id::uuid
            ELSE NULL
         END) AS membership_plan_id,
        COALESCE(m.medical_details, '')::text AS medical_details,
        COALESCE(m.notes, '')::text AS notes,
        COALESCE(m.total_received_amount, 0)::numeric AS total_received_amount,
        COALESCE(m.pending_amount, 0)::numeric AS pending_amount,
        COALESCE(m.discount_amount, 0)::numeric AS discount_amount,
        COALESCE(m.payment_status, 'Pending')::text AS payment_status,
        COALESCE(m.extra_fields, '{}'::jsonb) AS extra_fields
    FROM public.staff s
    INNER JOIN public.members m ON m.gym_id = s.gym_id
    LEFT JOIN public.pt_assignments pa
        ON pa.member_id = m.id
       AND pa.staff_id = p_staff_id
       AND pa.assignment_status = 'Active'
    WHERE s.id = p_staff_id
      AND (
          m.pt_trainer = p_staff_id
          OR pa.id IS NOT NULL
      )
    ORDER BY m.id, pa.created_at DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_trainer_clients(UUID) TO authenticated, service_role;


-- =============================================================================
-- PART 4: HARDEN update_member_measurements RPC
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.update_member_measurements(UUID, UUID, JSONB) FROM anon, public;

CREATE OR REPLACE FUNCTION public.update_member_measurements(
    p_staff_id UUID,
    p_member_id UUID,
    p_measurements JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_gym_id UUID;
    v_extra JSONB;
    v_is_authorized BOOLEAN := false;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SECURITY ERROR: Authentication required (Code: 40122)';
    END IF;

    SELECT gym_id INTO v_gym_id FROM public.members WHERE id = p_member_id;

    IF v_gym_id IS NULL THEN
        RAISE EXCEPTION 'Member not found';
    END IF;

    -- Verify caller is the staff member or admin/owner
    SELECT (
        public.is_admin(v_caller_id) OR
        EXISTS (
            SELECT 1 FROM public.staff 
            WHERE id = p_staff_id AND user_id = v_caller_id
        ) OR
        EXISTS (
            SELECT 1 FROM public.user_gym_associations 
            WHERE user_id = v_caller_id 
              AND gym_id = v_gym_id 
              AND LOWER(role) IN ('owner', 'admin', 'gym_owner')
        )
    ) INTO v_is_authorized;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'SECURITY ERROR: Unauthorized to update this member measurements (Code: 40322)';
    END IF;

    SELECT COALESCE(extra_fields, '{}'::jsonb)
    INTO v_extra
    FROM public.members
    WHERE id = p_member_id;

    IF p_measurements->'weight' IS NOT NULL THEN
        v_extra := v_extra || jsonb_build_object('weight', p_measurements->'weight');
    END IF;
    IF p_measurements->'chest' IS NOT NULL THEN
        v_extra := v_extra || jsonb_build_object('chest', p_measurements->'chest');
    END IF;
    IF p_measurements->'waist' IS NOT NULL THEN
        v_extra := v_extra || jsonb_build_object('waist', p_measurements->'waist');
    END IF;
    IF p_measurements->'biceps' IS NOT NULL THEN
        v_extra := v_extra || jsonb_build_object('biceps', p_measurements->'biceps');
    END IF;
    IF p_measurements->'hips' IS NOT NULL THEN
        v_extra := v_extra || jsonb_build_object('hips', p_measurements->'hips');
    END IF;
    IF p_measurements->'height' IS NOT NULL THEN
        v_extra := v_extra || jsonb_build_object('height', p_measurements->'height');
    END IF;

    UPDATE public.members
    SET extra_fields = v_extra
    WHERE id = p_member_id;

    RETURN v_extra;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_member_measurements(UUID, UUID, JSONB) TO authenticated, service_role;


-- =============================================================================
-- PART 5: HARDEN get_member_payment_transactions RPC
-- =============================================================================

REVOKE EXECUTE ON FUNCTION public.get_member_payment_transactions(UUID) FROM anon, public;

CREATE OR REPLACE FUNCTION public.get_member_payment_transactions(p_member_id UUID)
RETURNS TABLE (
    id UUID,
    gym_id UUID,
    title TEXT,
    amount NUMERIC,
    type TEXT,
    category TEXT,
    payment_method TEXT,
    date TEXT,
    transaction_date TIMESTAMPTZ,
    reference_id TEXT,
    created_by UUID,
    notes TEXT,
    expense_date DATE,
    revenue_date DATE,
    entry_date DATE,
    created_by_info TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_gym_id UUID;
    v_member_name TEXT;
    v_name_pattern TEXT;
    v_is_authorized BOOLEAN := false;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SECURITY ERROR: Authentication required (Code: 40123)';
    END IF;

    -- Fetch gym and name of member
    SELECT gym_id, trim(name) INTO v_gym_id, v_member_name
    FROM public.members
    WHERE id = p_member_id;

    IF v_gym_id IS NULL THEN
        RETURN;
    END IF;

    -- Verify caller has access to this gym or is the member themselves
    SELECT (
        public.is_admin(v_caller_id) OR
        EXISTS (
            SELECT 1 FROM public.members 
            WHERE id = p_member_id AND user_id = v_caller_id
        ) OR
        EXISTS (
            SELECT 1 FROM public.user_gym_associations 
            WHERE user_id = v_caller_id AND gym_id = v_gym_id
        ) OR
        EXISTS (
            SELECT 1 FROM public.staff 
            WHERE user_id = v_caller_id AND gym_id = v_gym_id
        )
    ) INTO v_is_authorized;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'SECURITY ERROR: Unauthorized to view member payments (Code: 40323)';
    END IF;

    v_name_pattern := '\y' || COALESCE(v_member_name, '') || '\y';

    RETURN QUERY
    SELECT 
        ft.id,
        ft.gym_id,
        COALESCE(ft.notes, ft.category, 'Payment') AS title,
        ft.amount,
        ft.type,
        ft.category,
        ft.payment_method,
        to_char(ft.transaction_date, 'DD Mon YYYY') AS date,
        ft.transaction_date,
        ft.reference_id,
        ft.created_by,
        COALESCE(ft.notes, '') AS notes,
        ft.expense_date,
        ft.revenue_date,
        ft.entry_date,
        ''::TEXT AS created_by_info
    FROM public.finance_transactions ft
    WHERE ft.gym_id = v_gym_id
      AND ft.type = 'Revenue'
      AND (
          ft.reference_id = p_member_id::TEXT
          OR ft.created_by = p_member_id
          OR (
              v_member_name IS NOT NULL 
              AND length(v_member_name) >= 2
              AND (
                  ft.notes ~* v_name_pattern
                  OR ft.category ~* v_name_pattern
              )
          )
      )
    ORDER BY ft.transaction_date DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_member_payment_transactions(UUID) TO authenticated, service_role;

COMMIT;
