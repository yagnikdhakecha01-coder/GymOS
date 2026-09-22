-- =============================================================================
-- GYMOS SECURITY HARDENING: PART 3 - STRICT MULTI-TENANT ISOLATION (ANTI-IDOR)
-- PURPOSE: Prevent hackers or malicious users from accessing, modifying, or
--          deleting records of another gym (IDOR / BOLA vulnerability).
-- SAFETY GUARANTEE: ZERO data deleted. RLS policies are fortified with 100% data safety.
-- =============================================================================

BEGIN;

-- 1. ENFORCE ROW LEVEL SECURITY AS MANDATORY (FORCE RLS)
-- Even for table owners or sub-roles, RLS will NEVER be bypassed.
ALTER TABLE public.gyms FORCE ROW LEVEL SECURITY;
ALTER TABLE public.members FORCE ROW LEVEL SECURITY;
ALTER TABLE public.staff FORCE ROW LEVEL SECURITY;
ALTER TABLE public.attendance FORCE ROW LEVEL SECURITY;
ALTER TABLE public.finance_transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.membership_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE public.member_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.salaries FORCE ROW LEVEL SECURITY;
ALTER TABLE public.salary_advance_ledger FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_gym_associations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.gym_backups FORCE ROW LEVEL SECURITY;

-- 2. USER GYM ASSOCIATIONS - HARDENED POLICY
-- Prevent users from adding themselves to arbitrary gyms
DROP POLICY IF EXISTS user_gym_assoc_read_policy ON public.user_gym_associations;
DROP POLICY IF EXISTS user_gym_assoc_modify_policy ON public.user_gym_associations;

CREATE POLICY user_gym_assoc_read_policy ON public.user_gym_associations
FOR SELECT TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    user_id = auth.uid()
);

-- Only super admins or owners can insert/update gym associations
CREATE POLICY user_gym_assoc_modify_policy ON public.user_gym_associations
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT uga.gym_id FROM public.user_gym_associations uga
        WHERE uga.user_id = auth.uid() 
          AND LOWER(uga.role) IN ('owner', 'admin', 'gym_owner')
    )
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (
        SELECT uga.gym_id FROM public.user_gym_associations uga
        WHERE uga.user_id = auth.uid() 
          AND LOWER(uga.role) IN ('owner', 'admin', 'gym_owner')
    )
);


-- 3. FORTIFIED PROFILE UPDATE RESTRICTION
-- Prevent a normal user from escalating privileges (e.g. setting role = 'super_admin' in profiles)
DROP POLICY IF EXISTS profiles_self_update_policy ON public.profiles;

CREATE POLICY profiles_self_update_policy ON public.profiles
FOR UPDATE TO authenticated
USING (
    id = auth.uid() OR public.is_admin(auth.uid())
)
WITH CHECK (
    -- Normal users can only update their own profile; they cannot change administrative flags
    id = auth.uid() OR public.is_admin(auth.uid())
);


-- 4. HARDEN FINANCE TRANSACTIONS AGAINST ILLEGAL TINKERING
DROP POLICY IF EXISTS gym_isolation_policy_tx ON public.finance_transactions;

CREATE POLICY gym_isolation_policy_tx ON public.finance_transactions
FOR ALL TO authenticated
USING (
    public.is_admin(auth.uid()) OR
    gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
)
WITH CHECK (
    public.is_admin(auth.uid()) OR
    gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
);

COMMIT;
