-- ====================================================================
-- GYMOS: FIX RLS POLICIES FOR LEAVE REQUESTS & SALARY ADVANCES
-- ====================================================================

-- 1. Drop existing policies to avoid any conflicts
DROP POLICY IF EXISTS leave_requests_isolation ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_owner_policy ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_staff_self ON public.leave_requests;

DROP POLICY IF EXISTS salary_advance_ledger_isolation ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_owner_policy ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_staff_self ON public.salary_advance_ledger;

-- 2. Enable RLS on both tables (just in case)
ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_advance_ledger ENABLE ROW LEVEL SECURITY;

-- 3. Create RLS Policies for public.leave_requests
-- Rule A: Gym Owners can view and manage all leave requests for their gyms
CREATE POLICY leave_requests_owner_policy ON public.leave_requests
    FOR ALL TO authenticated
    USING (gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    ))
    WITH CHECK (gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    ));

-- Rule B: Staff members can view, insert, and manage their own leave requests
CREATE POLICY leave_requests_staff_self ON public.leave_requests
    FOR ALL TO authenticated
    USING (staff_id IN (
        SELECT id FROM public.staff 
        WHERE user_id = auth.uid()
    ))
    WITH CHECK (staff_id IN (
        SELECT id FROM public.staff 
        WHERE user_id = auth.uid()
    ));

-- 4. Create RLS Policies for public.salary_advance_ledger
-- Rule A: Gym Owners can view and manage all salary advances for their gyms
CREATE POLICY salary_advance_ledger_owner_policy ON public.salary_advance_ledger
    FOR ALL TO authenticated
    USING (gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    ))
    WITH CHECK (gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    ));

-- Rule B: Staff members can view, insert, and manage their own salary advance requests
CREATE POLICY salary_advance_ledger_staff_self ON public.salary_advance_ledger
    FOR ALL TO authenticated
    USING (staff_id IN (
        SELECT id FROM public.staff 
        WHERE user_id = auth.uid()
    ))
    WITH CHECK (staff_id IN (
        SELECT id FROM public.staff 
        WHERE user_id = auth.uid()
    ));
