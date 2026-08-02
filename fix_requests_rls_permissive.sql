-- ====================================================================
-- GYMOS: PERMISSIVE RLS POLICIES FOR LEAVE REQUESTS & SALARY ADVANCES
-- ====================================================================

-- 1. Drop all previous restrictive policies
DROP POLICY IF EXISTS leave_requests_isolation ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_owner_policy ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_staff_self ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_permissive ON public.leave_requests;

DROP POLICY IF EXISTS salary_advance_ledger_isolation ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_owner_policy ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_staff_self ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_permissive ON public.salary_advance_ledger;

-- 2. Create fully permissive policies for authenticated users
CREATE POLICY leave_requests_permissive ON public.leave_requests
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY salary_advance_ledger_permissive ON public.salary_advance_ledger
    FOR ALL TO authenticated
    USING (true)
    WITH CHECK (true);
