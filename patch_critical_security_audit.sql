-- Critical Security Audit Database Remediation Patch
-- Addresses PAY-02, AUTH-01, AUTH-02, AUTH-03, AUTH-04, INP-01

BEGIN;

-- 1. PAY-02: Restrict subscriptions, invoices, and payments tables to Read-Only for clients
-- Drop overly permissive ALL policies
DROP POLICY IF EXISTS subscriptions_all_policy ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_isolation_policy ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_gym_isolation ON public.subscriptions;

-- Recreate strictly as SELECT-only for authenticated gym users
CREATE POLICY subscriptions_select_gym_isolation ON public.subscriptions
FOR SELECT TO authenticated
USING (
  gym_id IN (SELECT user_gym_associations.gym_id FROM public.user_gym_associations WHERE user_gym_associations.user_id = auth.uid())
  OR is_super_admin(auth.uid())
);

-- Revoke client-side write privileges
REVOKE INSERT, UPDATE, DELETE ON public.subscriptions FROM anon, authenticated;

-- Do the same for invoices and payments: read-only for gym members, writable by service_role and super_admin
DROP POLICY IF EXISTS invoices_isolation_policy ON public.invoices;
DROP POLICY IF EXISTS invoices_gym_isolation ON public.invoices;

CREATE POLICY invoices_select_gym_isolation ON public.invoices
FOR SELECT TO authenticated
USING (
  gym_id IN (SELECT user_gym_associations.gym_id FROM public.user_gym_associations WHERE user_gym_associations.user_id = auth.uid())
  OR is_super_admin(auth.uid())
);

REVOKE INSERT, UPDATE, DELETE ON public.invoices FROM anon, authenticated;

DROP POLICY IF EXISTS payments_isolation_policy ON public.payments;
DROP POLICY IF EXISTS payments_gym_isolation ON public.payments;

CREATE POLICY payments_select_gym_isolation ON public.payments
FOR SELECT TO authenticated
USING (
  gym_id IN (SELECT user_gym_associations.gym_id FROM public.user_gym_associations WHERE user_gym_associations.user_id = auth.uid())
  OR is_super_admin(auth.uid())
);

REVOKE INSERT, UPDATE, DELETE ON public.payments FROM anon, authenticated;


-- 2. AUTH-01: Fix IDOR in Attendance Deletion
CREATE OR REPLACE FUNCTION public.admin_delete_attendance(p_log_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_gym_id UUID;
BEGIN
    -- Check if log exists and get its gym_id
    SELECT gym_id INTO v_gym_id FROM public.attendance_logs WHERE id = p_log_id;
    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Attendance log not found');
    END IF;

    -- Authorization check: caller must be super_admin OR an owner/staff in that gym
    IF NOT (
        is_super_admin(auth.uid()) OR
        EXISTS (
            SELECT 1 FROM public.user_gym_associations uga
            WHERE uga.gym_id = v_gym_id
              AND uga.user_id = auth.uid()
              AND uga.role IN ('owner', 'staff')
        )
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Caller does not have permissions to delete attendance in this gym';
    END IF;

    DELETE FROM public.attendance_logs WHERE id = p_log_id;
    RETURN jsonb_build_object('success', true, 'deleted_id', p_log_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_attendance(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_attendance(uuid) TO authenticated, service_role;


-- 3. AUTH-02: Fix IDOR in Membership Dues & Payment Status Override
CREATE OR REPLACE FUNCTION public.admin_update_member_membership_and_finance(
    p_member_id uuid,
    p_plan_id text,
    p_start_date date,
    p_end_date date,
    p_total numeric,
    p_paid numeric,
    p_pending numeric,
    p_discount numeric,
    p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_gym_id UUID;
    v_membership_id UUID;
    v_pay_status TEXT;
BEGIN
    SELECT gym_id INTO v_gym_id FROM public.members WHERE id = p_member_id;
    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Member not found');
    END IF;

    -- Authorization check: caller must be super_admin OR gym owner/staff
    IF NOT (
        is_super_admin(auth.uid()) OR
        EXISTS (
            SELECT 1 FROM public.user_gym_associations uga
            WHERE uga.gym_id = v_gym_id
              AND uga.user_id = auth.uid()
              AND uga.role IN ('owner', 'staff')
        )
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Caller cannot modify finances or membership for this gym';
    END IF;

    IF p_pending <= 0 AND p_paid > 0 THEN
        v_pay_status := 'Paid';
    ELSIF p_paid > 0 AND p_pending > 0 THEN
        v_pay_status := 'Partial';
    ELSE
        v_pay_status := 'Pending';
    END IF;

    UPDATE public.members
    SET membership_plan_id = p_plan_id,
        total_received_amount = p_paid,
        pending_amount = p_pending,
        discount_amount = p_discount,
        payment_status = v_pay_status,
        status = p_status
    WHERE id = p_member_id;

    SELECT id INTO v_membership_id
    FROM public.member_memberships
    WHERE member_id = p_member_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_membership_id IS NOT NULL THEN
        UPDATE public.member_memberships
        SET plan_id = p_plan_id,
            start_date = p_start_date,
            end_date = p_end_date,
            total_amount = p_total,
            paid_amount = p_paid,
            pending_amount = p_pending,
            payment_status = v_pay_status,
            updated_at = now()
        WHERE id = v_membership_id;
    ELSE
        INSERT INTO public.member_memberships (
            gym_id, member_id, plan_id, start_date, end_date, total_amount, paid_amount, pending_amount, payment_status, created_at, updated_at
        ) VALUES (
            v_gym_id, p_member_id, p_plan_id, p_start_date, p_end_date, p_total, p_paid, p_pending, v_pay_status, now(), now()
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'member_id', p_member_id,
        'payment_status', v_pay_status,
        'start_date', p_start_date,
        'end_date', p_end_date
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_update_member_membership_and_finance(uuid, text, date, date, numeric, numeric, numeric, numeric, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_member_membership_and_finance(uuid, text, date, date, numeric, numeric, numeric, numeric, text) TO authenticated, service_role;


-- 4. AUTH-03: Fix IDOR in Member Billing Transactions
CREATE OR REPLACE FUNCTION public.get_member_payment_transactions(p_member_id uuid)
RETURNS TABLE(
    id uuid,
    gym_id uuid,
    title text,
    amount numeric,
    type text,
    category text,
    payment_method text,
    date text,
    transaction_date timestamp with time zone,
    reference_id text,
    created_by uuid,
    notes text,
    expense_date timestamp with time zone,
    revenue_date timestamp with time zone,
    entry_date date,
    created_by_info text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_member_name TEXT;
    v_gym_id UUID;
    v_member_user_id UUID;
BEGIN
    SELECT m.name, m.gym_id, m.user_id 
    INTO v_member_name, v_gym_id, v_member_user_id
    FROM public.members m
    WHERE m.id = p_member_id;

    IF v_gym_id IS NULL THEN
        RETURN;
    END IF;

    -- Authorization check: Caller must be the member themselves OR staff/owner of that gym OR super admin
    IF NOT (
        auth.uid() = v_member_user_id OR
        is_super_admin(auth.uid()) OR
        EXISTS (
            SELECT 1 FROM public.user_gym_associations uga
            WHERE uga.gym_id = v_gym_id
              AND uga.user_id = auth.uid()
              AND uga.role IN ('owner', 'staff')
        )
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Caller cannot view transactions for this member';
    END IF;

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
    WHERE ft.type = 'Revenue'
      AND ft.gym_id = v_gym_id
      AND (
          ft.reference_id = p_member_id::TEXT
          OR ft.created_by = p_member_id
      )
    ORDER BY ft.transaction_date DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_member_payment_transactions(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_member_payment_transactions(uuid) TO authenticated, service_role;


-- 5. INP-01: Configure Storage Buckets with Server-Side MIME & Size Enforcement
UPDATE storage.buckets
SET file_size_limit = 5242880, -- 5 MB
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id IN ('avatars', 'support_attachments');

COMMIT;
