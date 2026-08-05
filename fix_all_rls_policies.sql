-- =========================================================================
-- MASTER RLS POLICIES FIX: fix_all_rls_policies.sql
-- Run this script in your Supabase SQL Editor to resolve all 42501 Forbidden errors
-- for Members, Finance Ledger, Staff, Attendance, and Salaries.
-- =========================================================================

-- 1. Helper function to check if a user is a super admin
CREATE OR REPLACE FUNCTION public.is_admin(u_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users WHERE user_id = u_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. MEMBERS TABLE RLS POLICY
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


-- 3. FINANCE TRANSACTIONS TABLE RLS POLICY
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


-- 4. STAFF TABLE RLS POLICY
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


-- 5. ATTENDANCE TABLE RLS POLICY
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


-- 6. SALARY PAYMENTS TABLE RLS POLICY
ALTER TABLE public.salary_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gym_isolation_policy_salaries ON public.salary_payments;

CREATE POLICY gym_isolation_policy_salaries ON public.salary_payments
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


-- 7. Grant access to authenticated users & service role
GRANT ALL ON TABLE public.members TO authenticated, service_role;
GRANT ALL ON TABLE public.finance_transactions TO authenticated, service_role;
GRANT ALL ON TABLE public.staff TO authenticated, service_role;
GRANT ALL ON TABLE public.attendance TO authenticated, service_role;
GRANT ALL ON TABLE public.salary_payments TO authenticated, service_role;
