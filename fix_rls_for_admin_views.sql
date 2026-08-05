-- =========================================================================
-- DATABASE MIGRATION: fix_rls_for_admin_views.sql
-- Run this script in your Supabase SQL Editor to allow Super Admin access
-- to members, staff, and transactions across all gyms while protecting owner privacy.
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

-- 2. Modify members RLS policy to allow Admin bypass & User association lookup
DROP POLICY IF EXISTS member_isolation_policy ON public.members;
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

-- 3. Modify staff RLS policy to allow Admin bypass & User association lookup
DROP POLICY IF EXISTS staff_isolation_policy ON public.staff;
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

-- 4. Modify finance_transactions RLS policy to allow Admin bypass & User association lookup
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
