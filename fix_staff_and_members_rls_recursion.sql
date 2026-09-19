-- ==============================================================================
-- Migration: Fix RLS Infinite Recursion (42P17) on Staff and Member Policies
-- Resolves foreign key violations (23503) during mobile offline sync
-- PRESERVES 100% OF EXISTING DATA — ZERO DATA MODIFICATION OR DELETION
-- ==============================================================================

-- 1. Create a SECURITY DEFINER helper function to resolve accessible gyms
-- By using SECURITY DEFINER, this function executes with superuser rights and 
-- bypasses table RLS, completely breaking the infinite recursive loop on 'staff'.
CREATE OR REPLACE FUNCTION public.fn_user_accessible_gym_ids(p_user_id UUID)
RETURNS SETOF UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    -- Gyms associated via user_gym_associations (owners, staff, members)
    SELECT gym_id FROM public.user_gym_associations WHERE user_id = p_user_id
    UNION
    -- Gyms where the user is recorded in the staff table
    SELECT gym_id FROM public.staff WHERE user_id = p_user_id;
$$;

-- Grant execution to all authenticated roles
GRANT EXECUTE ON FUNCTION public.fn_user_accessible_gym_ids(UUID) TO authenticated, anon, service_role;

-- 2. Cleanly replace staff_isolation_policy on table 'staff'
-- Eliminates the self-referencing subquery (FROM staff staff_alias) which triggered 42P17.
DROP POLICY IF EXISTS staff_isolation_policy ON public.staff;
CREATE POLICY staff_isolation_policy ON public.staff
FOR ALL TO authenticated
USING (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR user_id = auth.uid()
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
)
WITH CHECK (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR user_id = auth.uid()
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
);

-- 3. Cleanly replace member_isolation_policy on table 'members'
-- Uses fn_user_accessible_gym_ids to prevent cascading recursion into 'staff'.
DROP POLICY IF EXISTS member_isolation_policy ON public.members;
CREATE POLICY member_isolation_policy ON public.members
FOR ALL TO authenticated
USING (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR user_id = auth.uid()
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
)
WITH CHECK (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR user_id = auth.uid()
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
);

-- 4. Cleanly replace secondary policies that directly queried 'staff' to avoid cross-table recursion
DROP POLICY IF EXISTS exercises_select ON public.exercises;
CREATE POLICY exercises_select ON public.exercises
FOR SELECT TO authenticated
USING (
    gym_id IS NULL
    OR is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
);

DROP POLICY IF EXISTS body_logs_member_rw ON public.member_body_logs;
CREATE POLICY body_logs_member_rw ON public.member_body_logs
FOR ALL TO authenticated
USING (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
    OR member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
)
WITH CHECK (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
    OR member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS fitness_goals_rw ON public.member_fitness_goals;
CREATE POLICY fitness_goals_rw ON public.member_fitness_goals
FOR ALL TO authenticated
USING (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
    OR member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
)
WITH CHECK (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
    OR member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS weekly_schedule_rw ON public.member_weekly_schedule;
CREATE POLICY weekly_schedule_rw ON public.member_weekly_schedule
FOR ALL TO authenticated
USING (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
    OR member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
)
WITH CHECK (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
    OR member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS workout_sets_member_rw ON public.member_workout_sets;
CREATE POLICY workout_sets_member_rw ON public.member_workout_sets
FOR ALL TO authenticated
USING (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
    OR member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS prs_member_rw ON public.member_personal_records;
CREATE POLICY prs_member_rw ON public.member_personal_records
FOR ALL TO authenticated
USING (
    is_admin(auth.uid())
    OR is_super_admin(auth.uid())
    OR gym_id IN (SELECT public.fn_user_accessible_gym_ids(auth.uid()))
    OR member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
);
