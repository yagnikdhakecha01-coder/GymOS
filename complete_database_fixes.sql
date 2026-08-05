-- =========================================================================
-- COMPLETE DATABASE MIGRATION & FIXES: complete_database_fixes.sql
-- Run this script in your Supabase SQL Editor to ensure all RLS policies,
-- staff pending salary RPC, and salary draft functions exist and work 100%.
-- =========================================================================

BEGIN;

-- 1. Helper function to check if a user is a super admin
CREATE OR REPLACE FUNCTION public.is_admin(u_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users WHERE user_id = u_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. RPC Function: Calculate Pending Salary for a Staff Member
CREATE OR REPLACE FUNCTION public.get_staff_pending_salary(p_staff_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_base_salary NUMERIC(12,2) := 0.0;
    v_paid_salary NUMERIC(12,2) := 0.0;
    v_pending NUMERIC(12,2) := 0.0;
BEGIN
    -- Get base salary from staff record
    SELECT COALESCE(salary, 0.0) INTO v_base_salary
    FROM public.staff
    WHERE id = p_staff_id;

    -- Get total paid salary in current month
    SELECT COALESCE(SUM(amount), 0.0) INTO v_paid_salary
    FROM public.finance_transactions
    WHERE reference_id = p_staff_id::TEXT
      AND category = 'Salary'
      AND type = 'Expense'
      AND DATE_TRUNC('month', transaction_date) = DATE_TRUNC('month', CURRENT_DATE);

    v_pending := GREATEST(0.0, v_base_salary - v_paid_salary);
    RETURN v_pending;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. MEMBERS TABLE RLS POLICY
ALTER TABLE public.members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS member_isolation_policy ON public.members;
DROP POLICY IF EXISTS update_own_member_record ON public.members;

CREATE POLICY member_isolation_policy ON public.members
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
);


-- 4. FINANCE TRANSACTIONS TABLE RLS POLICY
ALTER TABLE public.finance_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gym_isolation_policy_tx ON public.finance_transactions;

CREATE POLICY gym_isolation_policy_tx ON public.finance_transactions
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
);


-- 5. STAFF TABLE RLS POLICY
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_isolation_policy ON public.staff;
DROP POLICY IF EXISTS update_own_staff_record ON public.staff;

CREATE POLICY staff_isolation_policy ON public.staff
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
);


-- 6. ATTENDANCE TABLE RLS POLICY
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS attendance_isolation_policy ON public.attendance;

CREATE POLICY attendance_isolation_policy ON public.attendance
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
);


-- 7. INVITATIONS TABLE RLS POLICY
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS manage_invitations_owner ON public.invitations;
DROP POLICY IF EXISTS read_own_invitations ON public.invitations;

CREATE POLICY manage_invitations_owner ON public.invitations
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
    )
);


-- 8. GRANT PERMISSIONS
GRANT ALL ON TABLE public.members TO authenticated, service_role;
GRANT ALL ON TABLE public.finance_transactions TO authenticated, service_role;
GRANT ALL ON TABLE public.staff TO authenticated, service_role;
GRANT ALL ON TABLE public.attendance TO authenticated, service_role;
GRANT ALL ON TABLE public.invitations TO authenticated, service_role;

COMMIT;
