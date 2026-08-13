-- =============================================================================
-- GYMOS MASTER SQL FIXES - ALL DATABASE FIXES COMBINED
-- Generated: 2026-08-13 11:32
--
-- HOW TO RUN IN SUPABASE SQL EDITOR:
--   Option A: Run this ENTIRE file (may take 1-2 min)
--   Option B: Run PART by PART (search for "-- PART X --" below)
--
-- WARNING:
--   - fix_orphaned_auth_data deletes orphan auth records (PART 1)
--   - Backup your database before running if production data exists
--   - If any section fails, note the error and continue from next PART
-- =============================================================================


-- =============================================================================
-- PART 1 : fix_orphaned_auth_data.sql
-- =============================================================================

-- =========================================================================
-- REPAIR AUTH SCHEMA: fix_orphaned_auth_data.sql
-- Run this script in your Supabase SQL Editor to clear orphaned Google identities
-- caused by manual auth.users deletion.
-- =========================================================================

BEGIN;

-- Temporarily disable replication constraints
SET session_replication_role = 'replica';

-- 1. Delete orphaned Google identities whose user_id no longer exists in auth.users
DELETE FROM auth.identities 
WHERE user_id NOT IN (SELECT id FROM auth.users);

-- 2. Delete orphaned sessions and refresh tokens
DELETE FROM auth.sessions 
WHERE user_id NOT IN (SELECT id FROM auth.users);

-- 3. Re-enable replication constraints
SET session_replication_role = 'origin';

COMMIT;

-- 4. Bulletproof profile creation trigger
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE 
    SET 
        email = EXCLUDED.email,
        full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
        avatar_url = COALESCE(public.profiles.avatar_url, EXCLUDED.avatar_url);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();




-- =============================================================================
-- PART 2 : fix_category_check_constraint.sql
-- =============================================================================

-- ====================================================
-- GYMOS - FIX CHECK CONSTRAINT & OLD TRIGGERS ON SUPABASE
-- ====================================================
-- Run this ONCE in Supabase SQL Editor to completely solve
-- "violates check constraint finance_transactions_category_check"

-- 1. Drop old triggers that were inserting 'Salaries'
DROP TRIGGER IF EXISTS trg_on_advance_salary_created ON public.salary_advances;
DROP FUNCTION IF EXISTS public.fn_on_advance_salary_created() CASCADE;

-- 2. Drop old restrict constraint on finance_transactions if present
ALTER TABLE public.finance_transactions 
  DROP CONSTRAINT IF EXISTS finance_transactions_category_check;

-- 3. Add flexible category check constraint (allows 'Salary', 'Salaries', 'Membership', etc.)
ALTER TABLE public.finance_transactions 
  ADD CONSTRAINT finance_transactions_category_check 
  CHECK (category IN ('Membership', 'Salary', 'Salaries', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other'));

-- 4. Create clean Database Trigger using 'Salary'
CREATE OR REPLACE FUNCTION public.fn_on_advance_salary_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status) THEN
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        INSERT INTO public.finance_transactions (
            gym_id,
            type,
            category,
            amount,
            payment_method,
            reference_id,
            notes
        )
        VALUES (
            NEW.gym_id,
            'Expense',
            'Salary',
            NEW.amount,
            'Cash',
            NEW.staff_id::TEXT,
            'Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || NEW.reason || ')', '')
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_advance_salary_created
AFTER INSERT OR UPDATE ON public.salary_advances
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_salary_created();




-- =============================================================================
-- PART 3 : fix_advance_status_enum.sql
-- =============================================================================

-- ====================================================
-- GYMOS - FIX ENUM ADVANCE STATUS & BACKEND TRIGGERS
-- ====================================================
-- Run this in your Supabase SQL Editor to allow 'Given' status 
-- and fix the Postgres error: "invalid input value for enum advance_status: Given"

-- 1. Add 'Given' value to existing advance_status ENUM safely
ALTER TYPE public.advance_status ADD VALUE IF NOT EXISTS 'Given';

-- 2. Trigger Function to insert Finance Expense when Advance Salary is Approved/Given
CREATE OR REPLACE FUNCTION public.fn_on_advance_salary_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status) THEN
        -- Fetch Staff Name
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Insert Expense record in Finance Transactions automatically
        INSERT INTO public.transactions (
            gym_id, 
            type, 
            title, 
            amount, 
            category, 
            date, 
            payment_mode, 
            reference_id, 
            notes
        )
        VALUES (
            NEW.gym_id,
            'Expense',
            'Salary Advance - ' || COALESCE(s_name, 'Staff'),
            NEW.amount,
            'Salaries',
            NEW.requested_date::TEXT,
            'Cash',
            NEW.staff_id::TEXT,
            NEW.reason
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to salary_advances table
DROP TRIGGER IF EXISTS trg_on_advance_salary_created ON public.salary_advances;
CREATE TRIGGER trg_on_advance_salary_created
AFTER INSERT OR UPDATE ON public.salary_advances
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_salary_created();


-- 3. Update Salary Draft Live Calculations Trigger
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- 1. Calculate pending commission amount for staff
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    -- 2. Accumulate ALL advances given to staff (e.g. 2000 + 3000 = 5000)
    SELECT COALESCE(SUM(amount), 0.0) INTO adv_total 
    FROM public.salary_advances 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- 3. Calculate manual additions (Adjustments section)
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;

    -- 4. Calculate manual deductions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    -- 5. Set Draft values automatically in Backend
    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    -- Net Pending Payable Salary = (Base + Commission + Additions - Deductions) - Total Accumulative Advance
    NEW.net_salary := ((NEW.base_salary + comm_total + adj_add) - adj_ded) - adv_total;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach Trigger to salary_drafts table
DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;

CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();




-- =============================================================================
-- PART 4 : fix_subscription_history_action_check.sql
-- =============================================================================

-- =========================================================================
-- FIX SUBSCRIPTION HISTORY CHECK CONSTRAINT ERROR: fix_subscription_history_action_check.sql
-- Copy and paste this script in your Supabase SQL Editor and click RUN.
-- =========================================================================

-- 1. Drop existing restrictive CHECK constraint on subscription_history.action
ALTER TABLE public.subscription_history DROP CONSTRAINT IF EXISTS subscription_history_action_check;

-- 2. Add flexible CHECK constraint allowing 'create', 'Trial Activated', etc.
ALTER TABLE public.subscription_history 
ADD CONSTRAINT subscription_history_action_check 
CHECK (action IN (
    'create', 
    'Trial Activated', 
    'Plan Purchased', 
    'Plan Renewed', 
    'Plan Upgraded', 
    'Plan Downgraded', 
    'Payment Failed', 
    'Subscription Cancelled',
    'trial_extended',
    'expiry_updated'
));

-- 3. Update handle_new_gym_subscription function to be safe and use 'Trial Activated'
CREATE OR REPLACE FUNCTION public.handle_new_gym_subscription()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role = 'owner' THEN
        INSERT INTO public.subscriptions (gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date)
        VALUES (
            NEW.gym_id,
            NEW.user_id,
            'free_trial',
            'trial',
            now(),
            now() + interval '3 months',
            now(),
            now() + interval '3 months'
        )
        ON CONFLICT (gym_id) DO NOTHING;
        
        -- Log history using allowed action value
        INSERT INTO public.subscription_history (gym_id, old_plan_id, new_plan_id, action, changed_by, notes)
        VALUES (
            NEW.gym_id,
            NULL,
            'free_trial',
            'Trial Activated',
            NEW.user_id,
            'Auto 3-month trial started on registration'
        )
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;




-- =============================================================================
-- PART 5 : fix_membership_payments_foreign_key.sql
-- =============================================================================

-- =========================================================================
-- DATABASE MIGRATION: fix_membership_payments_foreign_key.sql
-- Run this script in your Supabase SQL Editor to fix the foreign key constraint
-- error on membership payments when using the offline-first sync engine.
-- =========================================================================

-- 1. Drop the foreign key constraint that references the old transactions table
-- (Since membership payments now reference finance_transactions during sync, 
-- this constraint is relaxed to allow storing finance_transactions UUIDs safely).
ALTER TABLE public.membership_payments 
DROP CONSTRAINT IF EXISTS membership_payments_transaction_id_fkey;

-- 2. Update the trigger function on membership_payments to bypass duplicate
-- transaction creation if transaction_id is already assigned by the sync engine.
CREATE OR REPLACE FUNCTION public.fn_generate_membership_transaction()
RETURNS TRIGGER AS $$
DECLARE
    m_name TEXT;
    p_title TEXT;
    t_id UUID;
BEGIN
    -- If transaction_id is already set (e.g. set to the finance_transactions ID from the sync engine),
    -- update the paid_amount / status of member_memberships and return immediately.
    IF NEW.transaction_id IS NOT NULL THEN
        UPDATE public.member_memberships 
        SET paid_amount = paid_amount + NEW.amount,
            payment_status = CASE 
                WHEN paid_amount + NEW.amount >= total_amount THEN 'Fully Paid'
                ELSE 'Partially Paid'
            END
        WHERE id = NEW.member_membership_id;
        RETURN NEW;
    END IF;

    -- Fetch Member name
    SELECT name INTO m_name FROM public.members WHERE id = (
        SELECT member_id FROM public.member_memberships WHERE id = NEW.member_membership_id
    );
    -- Fetch Plan title
    SELECT title INTO p_title FROM public.membership_plans WHERE id = (
        SELECT plan_id FROM public.member_memberships WHERE id = NEW.member_membership_id
    );

    -- Insert Transaction record into old transactions table
    INSERT INTO public.transactions (gym_id, type, title, amount, category, date, payment_mode, reference_id)
    VALUES (
        NEW.gym_id,
        'Revenue',
        'Membership Payment - ' || coalesce(m_name, 'Member') || ' (' || coalesce(p_title, 'Plan') || ')',
        NEW.amount,
        'Membership',
        NEW.payment_date,
        NEW.payment_mode,
        NEW.id
    ) RETURNING id INTO t_id;

    -- Update Transaction ID link
    UPDATE public.membership_payments SET transaction_id = t_id WHERE id = NEW.id;

    -- Update member's paid amount and payment status
    UPDATE public.member_memberships 
    SET paid_amount = paid_amount + NEW.amount,
        payment_status = CASE 
            WHEN paid_amount + NEW.amount >= total_amount THEN 'Fully Paid'
            ELSE 'Partially Paid'
        END
    WHERE id = NEW.member_membership_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;




-- =============================================================================
-- PART 6 : fix_gyms_subscription_fk_trigger.sql
-- =============================================================================

-- =========================================================================
-- FIX GYM SUBSCRIPTION FOREIGN KEY TRIGGER ERROR: fix_gyms_subscription_fk_trigger.sql
-- Copy and paste this script in your Supabase SQL Editor and click RUN.
-- =========================================================================

-- 1. Drop old conflicting triggers
DROP TRIGGER IF EXISTS trg_sync_gym_dates ON public.gyms;
DROP TRIGGER IF EXISTS trg_sync_gym_dates_before ON public.gyms;
DROP TRIGGER IF EXISTS trg_sync_gym_dates_after ON public.gyms;
DROP TRIGGER IF EXISTS on_gym_sync ON public.gyms;

-- 2. BEFORE TRIGGER: Pre-calculate default dates on NEW gym BEFORE insert (FK safe)
CREATE OR REPLACE FUNCTION public.handle_gym_dates_before()
RETURNS TRIGGER AS $$
BEGIN
    -- Determine effective target expiry date (Default 3 months)
    IF NEW.expiry_date IS NULL AND NEW.trial_end_date IS NULL THEN
        NEW.trial_end_date := NOW() + INTERVAL '3 months';
        NEW.expiry_date := NOW() + INTERVAL '3 months';
    ELSIF NEW.expiry_date IS NULL THEN
        NEW.expiry_date := NEW.trial_end_date;
    ELSIF NEW.trial_end_date IS NULL THEN
        NEW.trial_end_date := NEW.expiry_date;
    END IF;

    -- Default status and plan if missing
    IF NEW.status IS NULL THEN
        NEW.status := 'trial';
    END IF;
    IF NEW.plan IS NULL THEN
        NEW.plan := 'free_trial';
    END IF;

    -- Auto check expiration status
    IF NEW.expiry_date <= NOW() THEN
        NEW.status := 'expired';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_sync_gym_dates_before
BEFORE INSERT OR UPDATE ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.handle_gym_dates_before();


-- 3. AFTER TRIGGER: Safely sync subscriptions table AFTER gym row exists in database
CREATE OR REPLACE FUNCTION public.handle_gym_subscriptions_after()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_id UUID;
    v_target_date TIMESTAMPTZ;
BEGIN
    -- Avoid infinite recursion
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    v_target_date := COALESCE(NEW.expiry_date, NEW.trial_end_date, NOW() + INTERVAL '3 months');

    -- Safely get owner_id if association exists
    SELECT user_id INTO v_owner_id
    FROM public.user_gym_associations
    WHERE gym_id = NEW.id AND role = 'owner'
    LIMIT 1;

    -- Insert or update subscriptions record AFTER gym is in table
    INSERT INTO public.subscriptions (
        gym_id, owner_id, plan_id, status, trial_start, trial_end, start_date, end_date, updated_at
    )
    VALUES (
        NEW.id,
        v_owner_id,
        COALESCE(NEW.plan, 'free_trial'),
        COALESCE(NEW.status, 'trial'),
        COALESCE(NEW.created_at, NOW()),
        v_target_date,
        COALESCE(NEW.created_at, NOW()),
        v_target_date,
        NOW()
    )
    ON CONFLICT (gym_id) DO UPDATE SET 
        owner_id = EXCLUDED.owner_id,
        plan_id = EXCLUDED.plan_id,
        status = EXCLUDED.status,
        trial_end = EXCLUDED.trial_end,
        end_date = EXCLUDED.end_date,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_sync_gym_dates_after
AFTER INSERT OR UPDATE ON public.gyms
FOR EACH ROW EXECUTE FUNCTION public.handle_gym_subscriptions_after();




-- =============================================================================
-- PART 7 : fix_google_auth_and_triggers.sql
-- =============================================================================

-- =========================================================================
-- FIX GOOGLE AUTH & DATABASE SIGNUP TRIGGERS: fix_google_auth_and_triggers.sql
-- Run this script in your Supabase SQL Editor to resolve Auth 400 Gotrue errors.
-- =========================================================================

-- 1. Drop dangerous triggers on auth.users that interfere with Google OAuth
DROP TRIGGER IF EXISTS trg_auto_confirm_email ON auth.users;
DROP FUNCTION IF EXISTS auth.auto_confirm_user_email();

-- 2. Create a bulletproof profile generation trigger with Exception handling
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE 
    SET 
        email = EXCLUDED.email,
        full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
        avatar_url = COALESCE(public.profiles.avatar_url, EXCLUDED.avatar_url);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Guarantee that auth.users creation NEVER fails or returns 400 error
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach profile creation trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

-- 3. Ensure public.profiles RLS allows authenticated users to insert/update their own profile
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_self_access" ON public.profiles;
CREATE POLICY "profiles_self_access" ON public.profiles
FOR ALL TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "profiles_admin_access" ON public.profiles;
CREATE POLICY "profiles_admin_access" ON public.profiles
FOR ALL TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid())
);




-- =============================================================================
-- PART 8 : fix_all_rls_policies.sql
-- =============================================================================

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




-- =============================================================================
-- PART 9 : fix_unlink_rls_policy.sql
-- =============================================================================

-- =========================================================================
-- FIX UNLINK RLS POLICY: fix_unlink_rls_policy.sql
-- Run this script in your Supabase SQL Editor to allow gym owners
-- to successfully unlink staff and members by deleting user associations.
-- =========================================================================

-- Enable delete policy on user_gym_associations table
DROP POLICY IF EXISTS delete_associations ON public.user_gym_associations;

CREATE POLICY delete_associations ON public.user_gym_associations
    FOR DELETE TO authenticated
    USING (
        user_id = auth.uid()
        OR
        gym_id IN (
            SELECT gym_id 
            FROM public.user_gym_associations 
            WHERE user_id = auth.uid() AND role = 'owner'
        )
    );




-- =============================================================================
-- PART 10 : fix_requests_rls_policies.sql
-- =============================================================================

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




-- =============================================================================
-- PART 11 : fix_requests_rls_permissive.sql
-- =============================================================================

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




-- =============================================================================
-- PART 12 : fix_requests_approval_triggers_and_rls.sql
-- =============================================================================

-- ====================================================================
-- GYMOS: FIXED RLS POLICIES & AUTOMATIC TRIGGERS FOR REQUEST APPROVALS
-- ====================================================================

-- 1. Permissive RLS Policies for leave_requests and salary_advance_ledger
DROP POLICY IF EXISTS leave_requests_isolation ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_owner_policy ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_staff_self ON public.leave_requests;
DROP POLICY IF EXISTS leave_requests_permissive ON public.leave_requests;

DROP POLICY IF EXISTS salary_advance_ledger_isolation ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_owner_policy ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_staff_self ON public.salary_advance_ledger;
DROP POLICY IF EXISTS salary_advance_ledger_permissive ON public.salary_advance_ledger;

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salary_advance_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY leave_requests_permissive ON public.leave_requests
    FOR ALL TO public
    USING (true)
    WITH CHECK (true);

CREATE POLICY salary_advance_ledger_permissive ON public.salary_advance_ledger
    FOR ALL TO public
    USING (true)
    WITH CHECK (true);


-- 2. AUTOMATIC ATTENDANCE UPDATE ON APPROVED LEAVE
CREATE OR REPLACE FUNCTION public.fn_process_approved_leave()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_curr_date DATE;
    v_date_str TEXT;
    v_check_in TIMESTAMPTZ;
    v_check_out TIMESTAMPTZ;
BEGIN
    IF NEW.status = 'Approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'Approved') THEN
        SELECT user_id INTO v_user_id
        FROM public.staff
        WHERE id = NEW.staff_id;

        v_curr_date := NEW.start_date;
        WHILE v_curr_date <= NEW.end_date LOOP
            v_date_str := to_char(v_curr_date, 'dd-MM-yyyy');
            v_check_in := (v_curr_date::TEXT || ' 09:00:00')::TIMESTAMPTZ;
            v_check_out := (v_curr_date::TEXT || ' 18:00:00')::TIMESTAMPTZ;

            IF EXISTS (
                SELECT 1 FROM public.attendance_logs 
                WHERE (staff_id = NEW.staff_id OR user_id = v_user_id)
                  AND (date = v_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_curr_date)
            ) THEN
                UPDATE public.attendance_logs
                SET status = 'Leave',
                    shift_status = 'Completed',
                    updated_at = now()
                WHERE (staff_id = NEW.staff_id OR user_id = v_user_id)
                  AND (date = v_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_curr_date);
            ELSE
                INSERT INTO public.attendance_logs (
                    gym_id,
                    user_id,
                    role,
                    user_type,
                    staff_id,
                    date,
                    check_in,
                    check_out,
                    status,
                    shift_status,
                    method
                ) VALUES (
                    NEW.gym_id,
                    v_user_id,
                    'Staff',
                    'Staff',
                    NEW.staff_id,
                    v_date_str,
                    v_check_in,
                    v_check_out,
                    'Leave',
                    'Completed',
                    'Leave Approved'
                );
            END IF;

            v_curr_date := v_curr_date + INTERVAL '1 day';
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_process_approved_leave ON public.leave_requests;
CREATE TRIGGER trg_process_approved_leave
AFTER INSERT OR UPDATE ON public.leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.fn_process_approved_leave();


-- 3. AUTOMATIC EXPENSE & TRANSACTIONS RECORDING ON APPROVED SALARY ADVANCE
CREATE OR REPLACE FUNCTION public.fn_on_advance_ledger_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
    v_title TEXT;
BEGIN
    IF (NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status)) AND 
       (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('Approved'::public.advance_status, 'Given'::public.advance_status))) THEN
       
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;
        v_title := COALESCE('Salary Advance - ' || s_name, 'Salary Advance');

        -- 1. Record Expense entry in public.expenses table
        IF NOT EXISTS (
            SELECT 1 FROM public.expenses 
            WHERE gym_id = NEW.gym_id 
              AND category = 'Salary Advance' 
              AND amount = NEW.advance_amount 
              AND date = NEW.given_date
        ) THEN
            INSERT INTO public.expenses (
                gym_id,
                title,
                category,
                amount,
                date,
                notes
            ) VALUES (
                NEW.gym_id,
                v_title,
                'Salary Advance',
                NEW.advance_amount,
                NEW.given_date,
                COALESCE('Salary advance to ' || s_name || ' (' || NEW.reason || ')', 'Salary advance')
            );
        END IF;

        -- 2. Record Transaction entry in public.transactions table
        IF NOT EXISTS (
            SELECT 1 FROM public.transactions 
            WHERE gym_id = NEW.gym_id 
              AND type = 'Expense' 
              AND category = 'Salary Advance' 
              AND amount = NEW.advance_amount 
              AND date = NEW.given_date
        ) THEN
            INSERT INTO public.transactions (
                gym_id,
                type,
                title,
                category,
                amount,
                date
            ) VALUES (
                NEW.gym_id,
                'Expense',
                v_title,
                'Salary Advance',
                NEW.advance_amount,
                NEW.given_date
            );
        END IF;

    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_on_advance_ledger_created ON public.salary_advance_ledger;
CREATE TRIGGER trg_on_advance_ledger_created
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW
EXECUTE FUNCTION public.fn_on_advance_ledger_created();




-- =============================================================================
-- PART 13 : fix_subscription_rls_policies.sql
-- =============================================================================

-- ====================================================================
-- GYMOS - FIX SUBSCRIPTION, INVOICES, PAYMENTS & HISTORY RLS POLICIES
-- Run this script in your Supabase SQL Editor to resolve RLS 403 Errors
-- ====================================================================

-- 1. Enable RLS on all subscription-related tables
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing restrictive policies if any
DROP POLICY IF EXISTS subscriptions_isolation_policy ON public.subscriptions;
DROP POLICY IF EXISTS invoices_isolation_policy ON public.invoices;
DROP POLICY IF EXISTS payments_isolation_policy ON public.payments;
DROP POLICY IF EXISTS history_isolation_policy ON public.subscription_history;
DROP POLICY IF EXISTS plans_read_policy ON public.subscription_plans;

-- 3. Create permissive policies for authenticated users tied to their gym
CREATE POLICY subscriptions_isolation_policy ON public.subscriptions
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
    WITH CHECK (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY invoices_isolation_policy ON public.invoices
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
    WITH CHECK (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY payments_isolation_policy ON public.payments
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
    WITH CHECK (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY history_isolation_policy ON public.subscription_history
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
    WITH CHECK (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY plans_read_policy ON public.subscription_plans
    FOR SELECT TO authenticated
    USING (true);

-- 4. Grant explicit table privileges to authenticated and service_role
GRANT ALL ON TABLE public.subscriptions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.invoices TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.payments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_history TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_plans TO anon, authenticated, service_role;




-- =============================================================================
-- PART 14 : fix_admin_subscriptions_rls.sql
-- =============================================================================

-- ====================================================================
-- GYMOS ADMIN - SUBSCRIPTIONS & PLANS SUPER ADMIN RLS FIX
-- Run this script in your Supabase SQL Editor
-- ====================================================================

-- 1. Enable RLS on all related tables
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_history ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing restrictive policies if any
DROP POLICY IF EXISTS super_admin_all_subscriptions ON public.subscriptions;
DROP POLICY IF EXISTS super_admin_all_subscription_plans ON public.subscription_plans;
DROP POLICY IF EXISTS super_admin_all_invoices ON public.invoices;
DROP POLICY IF EXISTS super_admin_all_payments ON public.payments;
DROP POLICY IF EXISTS super_admin_all_subscription_history ON public.subscription_history;

-- 3. Create full permission policies for super admins and authenticated users
CREATE POLICY super_admin_all_subscriptions ON public.subscriptions
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY super_admin_all_subscription_plans ON public.subscription_plans
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY super_admin_all_invoices ON public.invoices
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY super_admin_all_payments ON public.payments
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY super_admin_all_subscription_history ON public.subscription_history
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 4. Grant explicit table permissions
GRANT ALL ON TABLE public.subscriptions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_plans TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.invoices TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.payments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_history TO anon, authenticated, service_role;




-- =============================================================================
-- PART 15 : fix_rls_for_admin_views.sql
-- =============================================================================

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




-- =============================================================================
-- PART 16 : fix_static_qr_rls.sql
-- =============================================================================

-- ====================================================
-- GYMOS - FIX STATIC QR RLS BYPASS
-- ====================================================

CREATE OR REPLACE FUNCTION public.get_display_static_qr(
    p_display_public_id TEXT,
    p_secret TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
    v_token TEXT;
BEGIN
    -- Verify display device is active, verified, and matches the secret
    SELECT * INTO v_display 
    FROM public.attendance_displays 
    WHERE display_public_id = p_display_public_id;
    
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display not found.');
    END IF;
    
    IF NOT v_display.is_verified OR NOT v_display.is_enabled THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display is not verified or is disabled.');
    END IF;
    
    IF v_display.device_secret <> p_secret THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid device credentials.');
    END IF;
    
    -- Retrieve static token
    SELECT static_qr_token INTO v_token
    FROM public.attendance_settings
    WHERE gym_id = v_display.gym_id;
    
    RETURN jsonb_build_object(
        'success', TRUE,
        'static_qr_token', v_token
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_display_static_qr TO anon, authenticated, service_role;




-- =============================================================================
-- PART 17 : fix_salary_advances_permissions.sql
-- =============================================================================

-- Run this query in your Supabase SQL Editor to grant required table privileges for salary_advances and all other tables to authenticated users.

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;




-- =============================================================================
-- PART 18 : complete_database_fixes.sql
-- =============================================================================

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




-- =============================================================================
-- PART 19 : staff_commission_redesign_migration.sql
-- =============================================================================

-- ====================================================================
-- GYMOS: STAFF COMMISSION ARCHITECTURE REDESIGN MIGRATION
-- ====================================================================

-- 1. Create Enums safely
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'commission_status') THEN
        CREATE TYPE public.commission_status AS ENUM ('Pending', 'Paid', 'Cancelled', 'Reversed', 'Void');
    ELSE
        -- Add any missing enum values if exists
        ALTER TYPE public.commission_status ADD VALUE IF NOT EXISTS 'Reversed';
        ALTER TYPE public.commission_status ADD VALUE IF NOT EXISTS 'Void';
    END IF;
END
$$;

-- 2. Create Personal Trainer Assignment Table
CREATE TABLE IF NOT EXISTS public.pt_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    commission_percentage NUMERIC(5, 2) NOT NULL DEFAULT 0.0 CHECK (commission_percentage >= 0),
    assignment_status TEXT NOT NULL DEFAULT 'Active' CHECK (assignment_status IN ('Active', 'Inactive')),
    pt_start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    deleted_at TIMESTAMPTZ
);

-- Indexing for assignments
CREATE INDEX IF NOT EXISTS idx_pt_assignments_lookup ON public.pt_assignments (member_id, staff_id, assignment_status);
CREATE INDEX IF NOT EXISTS idx_pt_assignments_gym ON public.pt_assignments (gym_id);

-- Enable RLS for assignments
ALTER TABLE public.pt_assignments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'pt_assignments' AND policyname = 'pt_assignments_isolation'
    ) THEN
        CREATE POLICY pt_assignments_isolation ON public.pt_assignments 
            FOR ALL TO authenticated
            USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));
    END IF;
END
$$;

-- 3. Junction table mapping salary payment to multiple commission ledger entries
CREATE TABLE IF NOT EXISTS public.salary_payment_commissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    salary_payment_id UUID NOT NULL REFERENCES public.salary_drafts(id) ON DELETE CASCADE,
    commission_ledger_id UUID NOT NULL, -- References commission_ledger(id) but decoupled for constraint flexibility if dropped
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing junction table
CREATE INDEX IF NOT EXISTS idx_sal_pay_comm_payment ON public.salary_payment_commissions (salary_payment_id);
CREATE INDEX IF NOT EXISTS idx_sal_pay_comm_ledger ON public.salary_payment_commissions (commission_ledger_id);

-- Enable RLS
ALTER TABLE public.salary_payment_commissions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'salary_payment_commissions' AND policyname = 'salary_payment_commissions_isolation'
    ) THEN
        CREATE POLICY salary_payment_commissions_isolation ON public.salary_payment_commissions 
            FOR ALL TO authenticated
            USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));
    END IF;
END
$$;

-- 4. Recreate/Enhance Commission Ledger to match details
-- Check if table needs modification
DO $$
BEGIN
    -- Add rule_version
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='rule_version') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN rule_version TEXT DEFAULT 'v1';
    END IF;

    -- Add calculation_base
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='calculation_base') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN calculation_base TEXT DEFAULT 'Received Payment';
    END IF;

    -- Add source_type
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='source_type') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN source_type TEXT DEFAULT 'Membership';
    END IF;

    -- Add source_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='source_id') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN source_id UUID;
    END IF;

    -- Add member_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='member_id') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN member_id UUID REFERENCES public.members(id) ON DELETE CASCADE;
    END IF;

    -- Add salary_month
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='salary_month') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN salary_month TEXT;
    END IF;

    -- Add included_in_salary
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='included_in_salary') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN included_in_salary BOOLEAN DEFAULT FALSE NOT NULL;
    END IF;

    -- Add salary_payment_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='salary_payment_id') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN salary_payment_id UUID REFERENCES public.salary_drafts(id) ON DELETE SET NULL;
    END IF;

    -- Add settlement_batch_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='settlement_batch_id') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN settlement_batch_id UUID;
    END IF;

    -- Add updated_at
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='commission_ledger' AND column_name='updated_at') THEN
        ALTER TABLE public.commission_ledger ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();
    END IF;
END
$$;

-- 5. Trigger to Automatically Generate Commission on Payment Received
CREATE OR REPLACE FUNCTION public.fn_generate_commission_entry()
RETURNS TRIGGER AS $$
DECLARE
    v_staff_id UUID;
    v_comm_rate NUMERIC(5,2);
    v_salary_type TEXT;
    v_member_id UUID;
    v_payment_month TEXT;
BEGIN
    -- Get member_id from member_memberships
    SELECT member_id INTO v_member_id 
    FROM public.member_memberships 
    WHERE id = NEW.member_membership_id;

    -- Find the active PT assignment for this member to retrieve snapshotted commission rate and staff_id
    SELECT staff_id, commission_percentage 
    INTO v_staff_id, v_comm_rate
    FROM public.pt_assignments
    WHERE member_id = v_member_id AND assignment_status = 'Active'
    LIMIT 1;

    -- If no PT Assignment is found, check member table pt_trainer (fallback/compatibility)
    IF v_staff_id IS NULL THEN
        SELECT pt_trainer INTO v_staff_id FROM public.members WHERE id = v_member_id;
        IF v_staff_id IS NOT NULL THEN
            SELECT commission_percentage INTO v_comm_rate FROM public.staff WHERE id = v_staff_id;
        END IF;
    END IF;

    -- Process only if assigned staff has valid salary type that supports commission
    IF v_staff_id IS NOT NULL AND v_comm_rate IS NOT NULL AND v_comm_rate > 0 THEN
        SELECT salary_type INTO v_salary_type FROM public.staff WHERE id = v_staff_id;

        IF v_salary_type IN ('Commission Based', 'Fixed + Commission', 'Percentage', 'Both') THEN
            v_payment_month := to_char(NEW.payment_date, 'Month YYYY');

            INSERT INTO public.commission_ledger (
                gym_id,
                staff_id,
                member_id,
                payment_id,
                payment_received,
                commission_rate,
                amount,
                status,
                source_type,
                source_id,
                rule_version,
                calculation_base,
                salary_month,
                included_in_salary,
                created_at,
                updated_at
            )
            VALUES (
                NEW.gym_id,
                v_staff_id,
                v_member_id,
                NEW.id,
                NEW.amount,
                v_comm_rate,
                (NEW.amount * v_comm_rate / 100.0),
                'Pending'::public.commission_status,
                'Membership',
                NEW.id,
                'v1',
                'Received Payment',
                v_payment_month,
                FALSE,
                now(),
                now()
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.1 Transaction generator on Membership Payment insertion or Finance Transaction insertion
-- We will modify the triggers to automatically generate membership payments and link them to commission calculations when transactions are inserted in finance_transactions.
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_inserted()
RETURNS TRIGGER AS $$
DECLARE
    v_member_membership_id UUID;
    v_payment_id UUID;
    v_salary_type TEXT;
    v_staff_id UUID;
    v_comm_rate NUMERIC(5,2);
    v_payment_month TEXT;
    v_ref_uuid UUID;
BEGIN
    -- Check if this transaction is revenue for membership and has a valid member reference_id
    IF NEW.type = 'Revenue' AND NEW.category = 'Membership' AND NEW.reference_id IS NOT NULL THEN
        -- Safely cast reference_id to UUID if it matches UUID format
        IF NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_ref_uuid := NEW.reference_id::UUID;
        ELSE
            RETURN NEW;
        END IF;

        -- Find the active member membership plan
        SELECT id INTO v_member_membership_id 
        FROM public.member_memberships 
        WHERE member_id = v_ref_uuid
        ORDER BY created_at DESC 
        LIMIT 1;

        -- If no active membership plan exists, create a default dummy membership linking record
        IF v_member_membership_id IS NULL THEN
            INSERT INTO public.member_memberships (
                gym_id,
                member_id,
                plan_id,
                start_date,
                end_date,
                total_amount,
                paid_amount,
                payment_status
            )
            VALUES (
                NEW.gym_id,
                v_ref_uuid,
                (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1),
                CURRENT_DATE,
                CURRENT_DATE + (
                    COALESCE(
                        (SELECT duration_days FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        (SELECT COALESCE(duration_months, 1) * 30 FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        30
                    ) || ' days'
                )::INTERVAL,
                NEW.amount,
                0.0,
                'Unpaid'
            ) RETURNING id INTO v_member_membership_id;
        END IF;

        -- Insert record into membership_payments to register actual received payment details
        INSERT INTO public.membership_payments (
            gym_id,
            member_membership_id,
            amount,
            payment_mode,
            transaction_id,
            payment_date
        )
        VALUES (
            NEW.gym_id,
            v_member_membership_id,
            NEW.amount,
            COALESCE(NEW.payment_method::public.payment_mode, 'Cash'::public.payment_mode),
            NEW.id,
            CURRENT_DATE
        ) RETURNING id INTO v_payment_id;

        -- Directly process commission ledger insertion in trigger logic for safety
        SELECT staff_id, commission_percentage 
        INTO v_staff_id, v_comm_rate
        FROM public.pt_assignments
        WHERE member_id = v_ref_uuid AND assignment_status = 'Active'
        LIMIT 1;

        -- Fallback check
        IF v_staff_id IS NULL THEN
            SELECT pt_trainer INTO v_staff_id FROM public.members WHERE id = v_ref_uuid;
            IF v_staff_id IS NOT NULL THEN
                SELECT commission_percentage INTO v_comm_rate FROM public.staff WHERE id = v_staff_id;
            END IF;
        END IF;

        -- Generate ledger entry if conditions match
        IF v_staff_id IS NOT NULL AND v_comm_rate IS NOT NULL AND v_comm_rate > 0 THEN
            SELECT salary_type INTO v_salary_type FROM public.staff WHERE id = v_staff_id;

            IF v_salary_type IN ('Commission Based', 'Fixed + Commission', 'Percentage', 'Both') THEN
                v_payment_month := to_char(CURRENT_DATE, 'Month YYYY');

                INSERT INTO public.commission_ledger (
                    gym_id,
                    staff_id,
                    member_id,
                    payment_id,
                    payment_received,
                    commission_rate,
                    amount,
                    status,
                    source_type,
                    source_id,
                    rule_version,
                    calculation_base,
                    salary_month,
                    included_in_salary,
                    created_at,
                    updated_at
                )
                VALUES (
                    NEW.gym_id,
                    v_staff_id,
                    v_ref_uuid,
                    v_payment_id,
                    NEW.amount,
                    v_comm_rate,
                    (NEW.amount * v_comm_rate / 100.0),
                    'Pending'::public.commission_status,
                    'Membership',
                    NEW.id,
                    'v1',
                    'Received Payment',
                    v_payment_month,
                    FALSE,
                    now(),
                    now()
                );
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger
DROP TRIGGER IF EXISTS trg_on_finance_transaction_inserted ON public.finance_transactions;
CREATE TRIGGER trg_on_finance_transaction_inserted
AFTER INSERT ON public.finance_transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_on_finance_transaction_inserted();


-- 6. Trigger to reverse commission on refund / payment deletion
CREATE OR REPLACE FUNCTION public.fn_reverse_commission_on_payment_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.commission_ledger
    SET status = 'Cancelled'::public.commission_status,
        updated_at = now()
    WHERE payment_id = OLD.id AND status = 'Pending'::public.commission_status;
    
    -- For already paid ones, mark as Reversed
    UPDATE public.commission_ledger
    SET status = 'Reversed'::public.commission_status,
        updated_at = now()
    WHERE payment_id = OLD.id AND status = 'Paid'::public.commission_status;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_reverse_commission_on_payment_delete ON public.membership_payments;
CREATE TRIGGER trg_reverse_commission_on_payment_delete
AFTER DELETE ON public.membership_payments
FOR EACH ROW EXECUTE FUNCTION public.fn_reverse_commission_on_payment_delete();

-- 7. Update Live Calculations Inside public.salary_drafts
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- Sum of pending commission entries for this staff that are not paid yet
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status = 'Pending'::public.commission_status
      AND included_in_salary = FALSE;

    -- Sum of pending advances
    SELECT COALESCE(SUM(remaining_amount), 0.0) INTO adv_total 
    FROM public.salary_advance_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- Manual adjustments
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    NEW.net_salary := ((NEW.base_salary + comm_total + adj_add) - adj_ded) - adv_total;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;
CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();

-- 8. Transaction-Safe Stored Procedure (RPC) to Pay Salary and Map Ledgers
CREATE OR REPLACE FUNCTION public.pay_salary_draft_v2(
    p_draft_id UUID,
    p_payment_mode TEXT,
    p_notes TEXT
)
RETURNS VOID AS $$
DECLARE
    v_gym_id UUID;
    v_staff_id UUID;
    v_net_salary NUMERIC(12,2);
    v_advance_deduction NUMERIC(12,2);
    v_salary_month TEXT;
    v_tx_id UUID;
    s_name TEXT;
    r_advance RECORD;
    r_commission RECORD;
    v_to_recover NUMERIC(12,2) := 0.0;
    v_recovered_temp NUMERIC(12,2) := 0.0;
    v_settlement_batch_id UUID;
BEGIN
    -- Fetch draft details
    SELECT gym_id, staff_id, net_salary, advance_deduction, salary_month
    INTO v_gym_id, v_staff_id, v_net_salary, v_advance_deduction, v_salary_month
    FROM public.salary_drafts
    WHERE id = p_draft_id AND status <> 'Paid';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Salary Draft not found or already paid.';
    END IF;

    SELECT name INTO s_name FROM public.staff WHERE id = v_staff_id;
    v_settlement_batch_id := gen_random_uuid();

    -- 1. Create Transaction record in public.transactions (Create Salary Expense)
    INSERT INTO public.transactions (
        gym_id,
        type,
        title,
        amount,
        category,
        date,
        payment_mode,
        reference_id
    )
    VALUES (
        v_gym_id,
        'Expense',
        'Salary Payment - ' || COALESCE(s_name, 'Staff'),
        v_net_salary,
        'Salaries',
        CURRENT_DATE,
        COALESCE(p_payment_mode::public.payment_mode, 'Cash'::public.payment_mode),
        p_draft_id
    ) RETURNING id INTO v_tx_id;

    -- 2. Junction map and update commission ledger entries to Paid
    FOR r_commission IN 
        SELECT id 
        FROM public.commission_ledger 
        WHERE staff_id = v_staff_id 
          AND status = 'Pending'::public.commission_status
          AND included_in_salary = FALSE
    LOOP
        -- Insert junction record
        INSERT INTO public.salary_payment_commissions (
            gym_id,
            salary_payment_id,
            commission_ledger_id
        )
        VALUES (
            v_gym_id,
            p_draft_id,
            r_commission.id
        );

        -- Update Ledger entry status
        UPDATE public.commission_ledger
        SET status = 'Paid'::public.commission_status,
            included_in_salary = TRUE,
            salary_payment_id = p_draft_id,
            settlement_batch_id = v_settlement_batch_id,
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = r_commission.id;
    END LOOP;

    -- 3. Recover advances dynamically
    v_to_recover := v_advance_deduction;
    IF v_to_recover > 0 THEN
        FOR r_advance IN 
            SELECT id, remaining_amount, recovered_amount, advance_amount
            FROM public.salary_advance_ledger
            WHERE staff_id = v_staff_id 
              AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
            ORDER BY given_date ASC
        LOOP
            IF v_to_recover <= 0 THEN
                EXIT;
            END IF;

            IF r_advance.remaining_amount <= v_to_recover THEN
                v_recovered_temp := r_advance.remaining_amount;
                
                UPDATE public.salary_advance_ledger
                SET recovered_amount = r_advance.advance_amount,
                    remaining_amount = 0.0,
                    status = 'Recovered'::public.advance_status,
                    salary_payment_id = p_draft_id,
                    updated_at = NOW()
                WHERE id = r_advance.id;
                
                v_to_recover := v_to_recover - v_recovered_temp;
            ELSE
                UPDATE public.salary_advance_ledger
                SET recovered_amount = r_advance.recovered_amount + v_to_recover,
                    remaining_amount = r_advance.remaining_amount - v_to_recover,
                    salary_payment_id = p_draft_id,
                    updated_at = NOW()
                WHERE id = r_advance.id;
                
                v_to_recover := 0.0;
            END IF;
        END LOOP;
    END IF;

    -- 4. Mark draft as Paid
    UPDATE public.salary_drafts
    SET status = 'Paid'::public.draft_status,
        paid_transaction_id = v_tx_id,
        created_at = NOW()
    WHERE id = p_draft_id;

    -- 5. Create Audit Log Entry
    INSERT INTO public.audit_logs (
        gym_id,
        action,
        table_name,
        reference_id,
        payload
    )
    VALUES (
        v_gym_id,
        'PAID SALARY V2',
        'salary_drafts',
        p_draft_id,
        jsonb_build_object(
            'staff_id', v_staff_id,
            'net_salary', v_net_salary,
            'settlement_batch_id', v_settlement_batch_id,
            'paid_transaction_id', v_tx_id
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Grant privileges for newly created tables
GRANT ALL ON TABLE public.pt_assignments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.salary_payment_commissions TO anon, authenticated, service_role;





-- =============================================================================
-- PART 20 : salary_advance_ledger.sql
-- =============================================================================

-- ====================================================================
-- GYMOS: ADVANCE SALARY LEDGER & MIGRATION SCHEMA (BACKEND REDESIGN)
-- ====================================================================

-- 1. Create enum states and table constraints safely
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'advance_status') THEN
        CREATE TYPE public.advance_status AS ENUM ('Pending', 'Approved', 'Rejected', 'Given', 'Recovered');
    END IF;
END
$$;

-- Rename old table if exists or drop to avoid conflicts
DROP TABLE IF EXISTS public.salary_advances CASCADE;

-- 2. Create Salary Advance Ledger Table
CREATE TABLE public.salary_advance_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    salary_payment_id UUID, -- Links to draft (salary_drafts) when recovered
    advance_amount NUMERIC(12,2) NOT NULL CHECK (advance_amount > 0),
    recovered_amount NUMERIC(12,2) DEFAULT 0.0 NOT NULL CHECK (recovered_amount >= 0),
    remaining_amount NUMERIC(12,2) DEFAULT 0.0 NOT NULL CHECK (remaining_amount >= 0),
    status public.advance_status DEFAULT 'Pending'::public.advance_status NOT NULL,
    given_date DATE NOT NULL,
    salary_month TEXT NOT NULL, -- 'MMMM YYYY' (e.g. 'July 2026')
    payment_method TEXT DEFAULT 'Cash',
    reference_number TEXT,
    notes TEXT,
    reason TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing for fast search queries
CREATE INDEX IF NOT EXISTS idx_sal_adv_ledger_staff ON public.salary_advance_ledger(staff_id, status);

-- Enable RLS
ALTER TABLE public.salary_advance_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY salary_advance_ledger_isolation ON public.salary_advance_ledger 
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- Set remaining_amount equal to advance_amount on creation
CREATE OR REPLACE FUNCTION public.fn_set_remaining_advance_amount()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.remaining_amount := NEW.advance_amount;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_remaining_advance_amount
BEFORE INSERT ON public.salary_advance_ledger
FOR EACH ROW EXECUTE FUNCTION public.fn_set_remaining_advance_amount();


-- 3. Automatic Expense Logger on Advance Salary Handout
CREATE OR REPLACE FUNCTION public.fn_on_advance_ledger_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF (NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status)) AND 
       (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('Approved'::public.advance_status, 'Given'::public.advance_status))) THEN
       
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Record Expense dynamically
        INSERT INTO public.transactions (
            gym_id,
            type,
            title,
            amount,
            category,
            date,
            payment_mode,
            reference_id
        )
        VALUES (
            NEW.gym_id,
            'Expense',
            'Salary Advance - ' || COALESCE(s_name, 'Staff'),
            NEW.advance_amount,
            'Salary Advance',
            NEW.given_date,
            COALESCE(NEW.payment_method::public.payment_mode, 'Cash'::public.payment_mode),
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_advance_ledger_created
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_ledger_created();


-- 4. Update view to calculate Pending Salary accurately
CREATE OR REPLACE VIEW public.vw_pending_salary_list AS
SELECT 
    s.id AS staff_id,
    s.gym_id,
    s.name,
    s.role,
    s.avatar,
    s.salary AS base_salary,
    COALESCE((
        SELECT SUM(cl.amount) 
        FROM public.commission_ledger cl 
        WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
    ), 0.0) AS pending_commission,
    COALESCE((
        SELECT SUM(sa.remaining_amount) 
        FROM public.salary_advance_ledger sa 
        WHERE sa.staff_id = s.id 
          AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
    ), 0.0) AS total_advance,
    GREATEST(
        (s.salary + COALESCE((
            SELECT SUM(cl.amount) 
            FROM public.commission_ledger cl 
            WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
        ), 0.0)) - COALESCE((
            SELECT SUM(sa.remaining_amount) 
            FROM public.salary_advance_ledger sa 
            WHERE sa.staff_id = s.id 
              AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
        ), 0.0), 
        0.0
    ) AS net_pending_salary
FROM public.staff s
WHERE NOT EXISTS (
    SELECT 1 FROM public.salary_drafts sd 
    WHERE sd.staff_id = s.id 
      AND sd.salary_month = to_char(now(), 'Month YYYY')
      AND sd.status = 'Paid'::public.draft_status
);


-- 5. Updated live calculations inside public.salary_drafts
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    SELECT COALESCE(SUM(remaining_amount), 0.0) INTO adv_total 
    FROM public.salary_advance_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded FROM public.salary_adjustments WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    -- Formula: Fixed Salary + Commission + Additions - Deductions - Advance Deduction
    NEW.net_salary := ((NEW.base_salary + comm_total + adj_add) - adj_ded) - adv_total;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;
CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();


-- 6. Stored Procedure (RPC) Transaction to pay salary & recover advances
CREATE OR REPLACE FUNCTION public.pay_salary_draft(
    p_draft_id UUID,
    p_payment_mode TEXT,
    p_notes TEXT
)
RETURNS VOID AS $$
DECLARE
    v_gym_id UUID;
    v_staff_id UUID;
    v_net_salary NUMERIC(12,2);
    v_advance_deduction NUMERIC(12,2);
    v_salary_month TEXT;
    v_tx_id UUID;
    s_name TEXT;
    r_advance RECORD;
    v_to_recover NUMERIC(12,2) := 0.0;
    v_recovered_temp NUMERIC(12,2) := 0.0;
BEGIN
    -- Fetch draft details
    SELECT gym_id, staff_id, net_salary, advance_deduction, salary_month
    INTO v_gym_id, v_staff_id, v_net_salary, v_advance_deduction, v_salary_month
    FROM public.salary_drafts
    WHERE id = p_draft_id AND status <> 'Paid';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Salary Draft not found or already paid.';
    END IF;

    SELECT name INTO s_name FROM public.staff WHERE id = v_staff_id;

    -- 1. Create Transaction record in public.transactions
    INSERT INTO public.transactions (
        gym_id,
        type,
        title,
        amount,
        category,
        date,
        payment_mode,
        reference_id
    )
    VALUES (
        v_gym_id,
        'Expense',
        'Salary Payment - ' || COALESCE(s_name, 'Staff'),
        v_net_salary,
        'Salaries',
        CURRENT_DATE,
        COALESCE(p_payment_mode::public.payment_mode, 'Cash'::public.payment_mode),
        p_draft_id
    ) RETURNING id INTO v_tx_id;

    -- 2. Mark Commissions included as Paid
    UPDATE public.commission_ledger
    SET status = 'Paid'::public.commission_status,
        paid_at = NOW()
    WHERE staff_id = v_staff_id AND status = 'Pending'::public.commission_status;

    -- 3. Recover advances dynamically
    v_to_recover := v_advance_deduction;
    IF v_to_recover > 0 THEN
        FOR r_advance IN 
            SELECT id, remaining_amount, recovered_amount, advance_amount
            FROM public.salary_advance_ledger
            WHERE staff_id = v_staff_id 
              AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
            ORDER BY given_date ASC
        LOOP
            IF v_to_recover <= 0 THEN
                EXIT;
            END IF;

            IF r_advance.remaining_amount <= v_to_recover THEN
                -- Full recovery for this record
                v_recovered_temp := r_advance.remaining_amount;
                
                UPDATE public.salary_advance_ledger
                SET recovered_amount = r_advance.advance_amount,
                    remaining_amount = 0.0,
                    status = 'Recovered'::public.advance_status,
                    salary_payment_id = p_draft_id,
                    updated_at = NOW()
                WHERE id = r_advance.id;
                
                v_to_recover := v_to_recover - v_recovered_temp;
            ELSE
                -- Partial recovery for this record
                UPDATE public.salary_advance_ledger
                SET recovered_amount = r_advance.recovered_amount + v_to_recover,
                    remaining_amount = r_advance.remaining_amount - v_to_recover,
                    salary_payment_id = p_draft_id,
                    updated_at = NOW()
                WHERE id = r_advance.id;
                
                v_to_recover := 0.0;
            END IF;
        END LOOP;
    END IF;

    -- 4. Mark draft as Paid
    UPDATE public.salary_drafts
    SET status = 'Paid'::public.draft_status,
        paid_transaction_id = v_tx_id,
        created_at = NOW()
    WHERE id = p_draft_id;

    -- 5. Create Audit Log Entry
    INSERT INTO public.audit_logs (
        gym_id,
        action,
        table_name,
        reference_id,
        payload
    )
    VALUES (
        v_gym_id,
        'Pay Salary Draft',
        'salary_drafts',
        p_draft_id,
        jsonb_build_object(
            'staff_id', v_staff_id,
            'net_salary', v_net_salary,
            'advance_deduction', v_advance_deduction,
            'transaction_id', v_tx_id
        )
    );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;




-- =============================================================================
-- PART 21 : change_member_pt.sql
-- =============================================================================

-- MIGRATION: CHANGE MEMBER PERSONAL TRAINER & SNAPSHOT COMMISSION PERCENTAGE
-- This script adds an RPC function to change a member's PT assignment.
-- It automatically deactivates any existing active assignment so that commission edits
-- apply only to future payments (not retroactively).

CREATE OR REPLACE FUNCTION public.change_member_pt(
    p_gym_id UUID,
    p_member_id UUID,
    p_pt_member BOOLEAN,
    p_staff_id UUID,
    p_commission_percentage NUMERIC
) RETURNS VOID AS $$
BEGIN
    -- 1. Inactivate any existing active PT assignments for this member
    UPDATE public.pt_assignments
    SET assignment_status = 'Inactive', updated_at = now()
    WHERE member_id = p_member_id AND assignment_status = 'Active';

    -- 2. If pt_member is true, insert the new active PT assignment
    IF p_pt_member = TRUE AND p_staff_id IS NOT NULL THEN
        INSERT INTO public.pt_assignments (
            gym_id,
            member_id,
            staff_id,
            commission_percentage,
            assignment_status,
            pt_start_date
        ) VALUES (
            p_gym_id,
            p_member_id,
            p_staff_id,
            p_commission_percentage,
            'Active',
            CURRENT_DATE
        );
    END IF;

    -- 3. Update the members table to keep it in sync
    UPDATE public.members
    SET 
        pt_member = p_pt_member,
        pt_trainer = CASE WHEN p_pt_member = TRUE THEN p_staff_id ELSE NULL END
    WHERE id = p_member_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions to standard roles
GRANT EXECUTE ON FUNCTION public.change_member_pt(UUID, UUID, BOOLEAN, UUID, NUMERIC) TO anon, authenticated, service_role;




-- =============================================================================
-- PART 22 : get_trainer_clients.sql
-- =============================================================================

-- =========================================================================
-- DATABASE FUNCTION: get_trainer_clients
-- Run this in your Supabase SQL Editor to retrieve a trainer's assigned
-- member details directly from the database.
-- =========================================================================

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
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
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
            WHEN m.membership_plan_id IS NOT NULL AND m.membership_plan_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' 
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
    FROM public.members m
    JOIN public.staff s ON s.id = p_staff_id
    LEFT JOIN public.pt_assignments pa ON pa.member_id = m.id AND pa.staff_id = p_staff_id AND pa.assignment_status = 'Active'
    WHERE (m.pt_trainer = p_staff_id AND m.pt_member = true)
       OR (pa.id IS NOT NULL);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_trainer_clients(UUID) TO anon, authenticated, service_role;




-- =============================================================================
-- PART 23 : fix_commission_duplicates.sql
-- =============================================================================

-- MIGRATION: FIX DUPLICATE COMMISSION LEDGER ENTRIES
-- 1. Deduplicate existing entries in public.commission_ledger
DELETE FROM public.commission_ledger a
USING public.commission_ledger b
WHERE a.id > b.id 
  AND a.payment_id = b.payment_id;

-- 2. Modify the finance transaction trigger to remove double commission generation.
-- The trigger fn_on_finance_transaction_inserted inserts into public.membership_payments,
-- which already has an AFTER INSERT trigger (fn_generate_commission_entry) that handles
-- inserting into public.commission_ledger. Thus, we remove the redundant direct insert from here.
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_inserted()
RETURNS TRIGGER AS $$
DECLARE
    v_member_membership_id UUID;
    v_payment_id UUID;
    v_ref_uuid UUID;
BEGIN
    -- Check if this transaction is revenue for membership and has a valid member reference_id
    IF NEW.type = 'Revenue' AND NEW.category = 'Membership' AND NEW.reference_id IS NOT NULL THEN
        -- Safely cast reference_id to UUID if it matches UUID format
        IF NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_ref_uuid := NEW.reference_id::UUID;
        ELSE
            RETURN NEW;
        END IF;

        -- Find the active member membership plan
        SELECT id INTO v_member_membership_id 
        FROM public.member_memberships 
        WHERE member_id = v_ref_uuid
        ORDER BY created_at DESC 
        LIMIT 1;

        -- If no active membership plan exists, create a default dummy membership linking record
        IF v_member_membership_id IS NULL THEN
            INSERT INTO public.member_memberships (
                gym_id,
                member_id,
                plan_id,
                start_date,
                end_date,
                total_amount,
                paid_amount,
                payment_status
            )
            VALUES (
                NEW.gym_id,
                v_ref_uuid,
                (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1),
                CURRENT_DATE,
                CURRENT_DATE + (
                    COALESCE(
                        (SELECT duration_days FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        (SELECT COALESCE(duration_months, 1) * 30 FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        30
                    ) || ' days'
                )::INTERVAL,
                NEW.amount,
                0.0,
                'Unpaid'
            ) RETURNING id INTO v_member_membership_id;
        END IF;

        -- Insert record into membership_payments to register actual received payment details
        -- This will automatically trigger fn_generate_commission_entry to create the commission_ledger record.
        INSERT INTO public.membership_payments (
            gym_id,
            member_membership_id,
            amount,
            payment_mode,
            transaction_id,
            payment_date
        )
        VALUES (
            NEW.gym_id,
            v_member_membership_id,
            NEW.amount,
            COALESCE(NEW.payment_method::public.payment_mode, 'Cash'::public.payment_mode),
            NEW.id,
            CURRENT_DATE
        ) RETURNING id INTO v_payment_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;




-- =============================================================================
-- PART 24 : fix_finance_transactions_trigger.sql
-- =============================================================================

-- ====================================================
-- GYMOS - FIX FINANCE TRANSACTIONS TRIGGER (TARGET RIGHT TABLE)
-- ====================================================
-- Run this in your Supabase SQL Editor to solve:
-- "column 'notes' of relation 'transactions' does not exist"

-- 1. Ensure `finance_transactions` table exists
CREATE TABLE IF NOT EXISTS public.finance_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    type TEXT NOT NULL CHECK (type IN ('Revenue', 'Expense')),
    category TEXT NOT NULL,
    payment_method TEXT DEFAULT 'Cash' NOT NULL,
    transaction_date TIMESTAMPTZ DEFAULT now() NOT NULL,
    reference_id TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Grant privileges
GRANT ALL ON TABLE public.finance_transactions TO anon, authenticated, service_role;

-- 2. Trigger Function inserting into `finance_transactions` (Correct table with notes column)
CREATE OR REPLACE FUNCTION public.fn_on_advance_salary_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
BEGIN
    IF NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status) THEN
        -- Fetch Staff Name
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Insert Expense record into `finance_transactions`
        INSERT INTO public.finance_transactions (
            gym_id, 
            type, 
            category, 
            amount, 
            payment_method, 
            reference_id, 
            notes
        )
        VALUES (
            NEW.gym_id,
            'Expense',
            'Salary',
            NEW.amount,
            'Cash',
            NEW.staff_id::TEXT,
            'Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || NEW.reason || ')', '')
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach trigger to salary_advances table
DROP TRIGGER IF EXISTS trg_on_advance_salary_created ON public.salary_advances;
CREATE TRIGGER trg_on_advance_salary_created
AFTER INSERT OR UPDATE ON public.salary_advances
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_salary_created();


-- 3. Trigger Function on inserting into finance_transactions to compute commissions
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_inserted()
RETURNS TRIGGER AS $$
DECLARE
    v_member_membership_id UUID;
    v_payment_id UUID;
    v_salary_type TEXT;
    v_staff_id UUID;
    v_comm_rate NUMERIC(5,2);
    v_payment_month TEXT;
    v_ref_uuid UUID;
BEGIN
    -- Check if this transaction is revenue for membership and has a valid member reference_id
    IF NEW.type = 'Revenue' AND NEW.category = 'Membership' AND NEW.reference_id IS NOT NULL THEN
        -- Safely cast reference_id to UUID if it matches UUID format
        IF NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_ref_uuid := NEW.reference_id::UUID;
        ELSE
            RETURN NEW;
        END IF;

        -- Find the active member membership plan
        SELECT id INTO v_member_membership_id 
        FROM public.member_memberships 
        WHERE member_id = v_ref_uuid
        ORDER BY created_at DESC 
        LIMIT 1;

        -- If no active membership plan exists, create a default dummy membership linking record
        IF v_member_membership_id IS NULL THEN
            INSERT INTO public.member_memberships (
                gym_id,
                member_id,
                plan_id,
                start_date,
                end_date,
                total_amount,
                paid_amount,
                payment_status
            )
            VALUES (
                NEW.gym_id,
                v_ref_uuid,
                (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1),
                CURRENT_DATE,
                CURRENT_DATE + (
                    COALESCE(
                        (SELECT duration_days FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        (SELECT COALESCE(duration_months, 1) * 30 FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        30
                    ) || ' days'
                )::INTERVAL,
                NEW.amount,
                0.0,
                'Unpaid'
            ) RETURNING id INTO v_member_membership_id;
        END IF;

        -- Insert record into membership_payments to register actual received payment details
        INSERT INTO public.membership_payments (
            gym_id,
            member_membership_id,
            amount,
            payment_mode,
            transaction_id,
            payment_date
        )
        VALUES (
            NEW.gym_id,
            v_member_membership_id,
            NEW.amount,
            COALESCE(NEW.payment_method::public.payment_mode, 'Cash'::public.payment_mode),
            NEW.id,
            CURRENT_DATE
        ) RETURNING id INTO v_payment_id;

        -- Directly process commission ledger insertion in trigger logic for safety
        SELECT staff_id, commission_percentage 
        INTO v_staff_id, v_comm_rate
        FROM public.pt_assignments
        WHERE member_id = v_ref_uuid AND assignment_status = 'Active'
        LIMIT 1;

        -- Fallback check
        IF v_staff_id IS NULL THEN
            SELECT pt_trainer INTO v_staff_id FROM public.members WHERE id = v_ref_uuid;
            IF v_staff_id IS NOT NULL THEN
                SELECT commission_percentage INTO v_comm_rate FROM public.staff WHERE id = v_staff_id;
            END IF;
        END IF;

        -- Generate ledger entry if conditions match
        IF v_staff_id IS NOT NULL AND v_comm_rate IS NOT NULL AND v_comm_rate > 0 THEN
            SELECT salary_type INTO v_salary_type FROM public.staff WHERE id = v_staff_id;

            IF v_salary_type IN ('Commission Based', 'Fixed + Commission', 'Percentage', 'Both') THEN
                v_payment_month := to_char(CURRENT_DATE, 'Month YYYY');

                INSERT INTO public.commission_ledger (
                    gym_id,
                    staff_id,
                    member_id,
                    payment_id,
                    payment_received,
                    commission_rate,
                    amount,
                    status,
                    source_type,
                    source_id,
                    rule_version,
                    calculation_base,
                    salary_month,
                    included_in_salary,
                    created_at,
                    updated_at
                )
                VALUES (
                    NEW.gym_id,
                    v_staff_id,
                    v_ref_uuid,
                    v_payment_id,
                    NEW.amount,
                    v_comm_rate,
                    (NEW.amount * v_comm_rate / 100.0),
                    'Pending'::public.commission_status,
                    'Membership',
                    NEW.id,
                    'v1',
                    'Received Payment',
                    v_payment_month,
                    FALSE,
                    now(),
                    now()
                );
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on finance_transactions
DROP TRIGGER IF EXISTS trg_on_finance_transaction_inserted ON public.finance_transactions;
CREATE TRIGGER trg_on_finance_transaction_inserted
AFTER INSERT ON public.finance_transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_on_finance_transaction_inserted();




-- =============================================================================
-- PART 25 : fix_payment_received_reset_bug.sql
-- =============================================================================

-- =========================================================================
-- DATABASE MIGRATION: fix_payment_received_reset_bug.sql
-- 
-- FIXES: Member payment card (Final Amount, Received, Pending) values
-- reset to initial values after app restart.
--
-- ROOT CAUSE: fn_on_finance_transaction_inserted creates member_memberships
-- with total_amount = payment_amount (WRONG), causing fn_sync_member_payment_status
-- to overwrite members.total_received_amount and pending_amount with wrong values.
--
-- Run this in Supabase SQL Editor.
-- =========================================================================

-- =========================================================================
-- STEP 1: Fix fn_on_finance_transaction_inserted
-- When auto-creating member_memberships, use actual plan price minus discount
-- from members table, NOT the payment amount.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_inserted()
RETURNS TRIGGER AS $$
DECLARE
    v_member_membership_id UUID;
    v_payment_id UUID;
    v_salary_type TEXT;
    v_staff_id UUID;
    v_comm_rate NUMERIC(5,2);
    v_payment_month TEXT;
    v_ref_uuid UUID;
    v_actual_total_amount NUMERIC(12,2);
    v_plan_price NUMERIC(12,2);
    v_discount NUMERIC(12,2);
    v_plan_id TEXT;
    v_duration_days INT;
BEGIN
    -- Check if this transaction is revenue for membership and has a valid member reference_id
    IF NEW.type = 'Revenue' AND NEW.category = 'Membership' AND NEW.reference_id IS NOT NULL THEN
        -- Safely cast reference_id to UUID if it matches UUID format
        IF NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_ref_uuid := NEW.reference_id::UUID;
        ELSE
            RETURN NEW;
        END IF;

        -- Find the active member membership plan
        SELECT id INTO v_member_membership_id 
        FROM public.member_memberships 
        WHERE member_id = v_ref_uuid
        ORDER BY created_at DESC 
        LIMIT 1;

        -- If no active membership plan exists, create one with CORRECT total_amount
        IF v_member_membership_id IS NULL THEN
            -- Get the member's actual plan info and discount
            SELECT 
                m.membership_plan_id,
                COALESCE(m.discount_amount, 0.0),
                COALESCE(m.total_received_amount, 0.0) + COALESCE(m.pending_amount, 0.0)
            INTO v_plan_id, v_discount, v_actual_total_amount
            FROM public.members m
            WHERE m.id = v_ref_uuid;

            -- Get plan price
            SELECT COALESCE(p.price, 0.0), COALESCE(p.duration_days, COALESCE(p.duration_months, 1) * 30)
            INTO v_plan_price, v_duration_days
            FROM public.membership_plans p
            WHERE p.id = v_plan_id;

            -- Use actual total (received + pending) from members table as the true total_amount
            -- This is the most accurate because the app calculates it correctly
            -- Fallback to plan_price - discount if members table values are 0
            IF v_actual_total_amount IS NULL OR v_actual_total_amount <= 0 THEN
                v_actual_total_amount := COALESCE(v_plan_price, NEW.amount) - COALESCE(v_discount, 0.0);
            END IF;

            -- Ensure total_amount is at least the payment amount
            IF v_actual_total_amount < NEW.amount THEN
                v_actual_total_amount := NEW.amount;
            END IF;

            INSERT INTO public.member_memberships (
                gym_id,
                member_id,
                plan_id,
                start_date,
                end_date,
                total_amount,
                paid_amount,
                payment_status
            )
            VALUES (
                NEW.gym_id,
                v_ref_uuid,
                COALESCE(v_plan_id, (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1)),
                CURRENT_DATE,
                CURRENT_DATE + (COALESCE(v_duration_days, 30) || ' days')::INTERVAL,
                v_actual_total_amount,
                0.0,
                'Unpaid'
            ) RETURNING id INTO v_member_membership_id;
        END IF;

        -- Insert record into membership_payments to register actual received payment details
        INSERT INTO public.membership_payments (
            gym_id,
            member_membership_id,
            amount,
            payment_mode,
            transaction_id,
            payment_date
        )
        VALUES (
            NEW.gym_id,
            v_member_membership_id,
            NEW.amount,
            COALESCE(NEW.payment_method::public.payment_mode, 'Cash'::public.payment_mode),
            NEW.id,
            CURRENT_DATE
        ) RETURNING id INTO v_payment_id;

        -- Directly process commission ledger insertion in trigger logic for safety
        SELECT staff_id, commission_percentage 
        INTO v_staff_id, v_comm_rate
        FROM public.pt_assignments
        WHERE member_id = v_ref_uuid AND assignment_status = 'Active'
        LIMIT 1;

        -- Fallback check
        IF v_staff_id IS NULL THEN
            SELECT pt_trainer INTO v_staff_id FROM public.members WHERE id = v_ref_uuid;
            IF v_staff_id IS NOT NULL THEN
                SELECT commission_percentage INTO v_comm_rate FROM public.staff WHERE id = v_staff_id;
            END IF;
        END IF;

        -- Generate ledger entry if conditions match
        IF v_staff_id IS NOT NULL AND v_comm_rate IS NOT NULL AND v_comm_rate > 0 THEN
            SELECT salary_type INTO v_salary_type FROM public.staff WHERE id = v_staff_id;

            IF v_salary_type IN ('Commission Based', 'Fixed + Commission', 'Percentage', 'Both') THEN
                v_payment_month := to_char(CURRENT_DATE, 'Month YYYY');

                INSERT INTO public.commission_ledger (
                    gym_id,
                    staff_id,
                    member_id,
                    payment_id,
                    payment_received,
                    commission_rate,
                    amount,
                    status,
                    source_type,
                    source_id,
                    rule_version,
                    calculation_base,
                    salary_month,
                    included_in_salary,
                    created_at,
                    updated_at
                )
                VALUES (
                    NEW.gym_id,
                    v_staff_id,
                    v_ref_uuid,
                    v_payment_id,
                    NEW.amount,
                    v_comm_rate,
                    (NEW.amount * v_comm_rate / 100.0),
                    'Pending'::public.commission_status,
                    'Membership',
                    NEW.id,
                    'v1',
                    'Received Payment',
                    v_payment_month,
                    FALSE,
                    now(),
                    now()
                );
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on finance_transactions
DROP TRIGGER IF EXISTS trg_on_finance_transaction_inserted ON public.finance_transactions;
CREATE TRIGGER trg_on_finance_transaction_inserted
AFTER INSERT ON public.finance_transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_on_finance_transaction_inserted();


-- =========================================================================
-- STEP 2: Fix fn_sync_member_payment_status
-- Use members table (total_received_amount + pending_amount) as truth
-- when member_memberships total_amount seems corrupted.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.fn_sync_member_payment_status()
RETURNS TRIGGER AS $$
DECLARE
    v_member_id UUID;
    v_total_pending NUMERIC(12,2) := 0.0;
    v_total_received NUMERIC(12,2) := 0.0;
    v_mm_count INT := 0;
BEGIN
    v_member_id := COALESCE(NEW.member_id, OLD.member_id);
    IF v_member_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Count how many member_memberships exist for this member
    SELECT COUNT(*) INTO v_mm_count
    FROM public.member_memberships
    WHERE member_id = v_member_id;

    IF v_mm_count > 0 THEN
        -- Calculate total remaining dues from member_memberships
        SELECT COALESCE(SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0))), 0.0)
        INTO v_total_pending
        FROM public.member_memberships
        WHERE member_id = v_member_id;

        -- Calculate total received from member_memberships
        SELECT COALESCE(SUM(COALESCE(paid_amount, 0.0)), 0.0)
        INTO v_total_received
        FROM public.member_memberships
        WHERE member_id = v_member_id;

        UPDATE public.members
        SET pending_amount = v_total_pending,
            total_received_amount = v_total_received,
            payment_status = CASE WHEN v_total_pending <= 0 THEN 'Paid' ELSE 'Pending' END
        WHERE id = v_member_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on member_memberships
DROP TRIGGER IF EXISTS trg_sync_member_payment_status ON public.member_memberships;
CREATE TRIGGER trg_sync_member_payment_status
AFTER INSERT OR UPDATE OR DELETE ON public.member_memberships
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_member_payment_status();


-- =========================================================================
-- STEP 3: Fix existing corrupted member_memberships data
-- Correct total_amount using plan price - discount for all existing records
-- =========================================================================
UPDATE public.member_memberships mm
SET total_amount = GREATEST(
    COALESCE(
        -- Use members table total (received + pending) as source of truth
        (SELECT COALESCE(m.total_received_amount, 0.0) + COALESCE(m.pending_amount, 0.0)
         FROM public.members m
         WHERE m.id = mm.member_id),
        -- Fallback: plan price - discount
        (SELECT COALESCE(p.price, 0.0) - COALESCE(
            (SELECT COALESCE(m2.discount_amount, 0.0) FROM public.members m2 WHERE m2.id = mm.member_id),
            0.0
        )
         FROM public.membership_plans p
         WHERE p.id = mm.plan_id),
        mm.total_amount
    ),
    mm.paid_amount  -- total_amount must be >= paid_amount
)
WHERE mm.total_amount < (
    SELECT COALESCE(p.price, 0.0) - COALESCE(
        (SELECT COALESCE(m3.discount_amount, 0.0) FROM public.members m3 WHERE m3.id = mm.member_id),
        0.0
    )
    FROM public.membership_plans p
    WHERE p.id = mm.plan_id
);


-- =========================================================================
-- STEP 4: Re-sync all member payment statuses from corrected data
-- =========================================================================
UPDATE public.members m
SET total_received_amount = COALESCE((
        SELECT SUM(COALESCE(paid_amount, 0.0))
        FROM public.member_memberships mm
        WHERE mm.member_id = m.id
    ), m.total_received_amount),
    pending_amount = COALESCE((
        SELECT SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0)))
        FROM public.member_memberships mm
        WHERE mm.member_id = m.id
    ), m.pending_amount),
    payment_status = CASE 
        WHEN COALESCE((
            SELECT SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0)))
            FROM public.member_memberships mm
            WHERE mm.member_id = m.id
        ), m.pending_amount) <= 0 THEN 'Paid'
        ELSE 'Pending'
    END
WHERE EXISTS (
    SELECT 1 FROM public.member_memberships mm WHERE mm.member_id = m.id
);

-- =========================================================================
-- STEP 5: Create RPC function for app-side payment sync
-- Called by the app after recording a payment to directly update
-- member_memberships.paid_amount, ensuring consistency.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.sync_member_payment_amounts(
    p_member_id UUID,
    p_gym_id UUID,
    p_payment_amount NUMERIC,
    p_new_total_received NUMERIC,
    p_new_pending_amount NUMERIC
)
RETURNS VOID AS $$
DECLARE
    v_mm_id UUID;
    v_current_paid NUMERIC(12,2);
    v_total_amount NUMERIC(12,2);
BEGIN
    -- Find the most recent member_memberships record
    SELECT id, COALESCE(paid_amount, 0.0), COALESCE(total_amount, 0.0)
    INTO v_mm_id, v_current_paid, v_total_amount
    FROM public.member_memberships
    WHERE member_id = p_member_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_mm_id IS NOT NULL THEN
        -- Fix total_amount if it's less than what it should be
        IF v_total_amount < (p_new_total_received + p_new_pending_amount) THEN
            UPDATE public.member_memberships
            SET total_amount = (p_new_total_received + p_new_pending_amount)
            WHERE id = v_mm_id;
        END IF;

        -- Update paid_amount to match app's calculated total received
        -- Use app's total received as source of truth
        UPDATE public.member_memberships
        SET paid_amount = p_new_total_received,
            payment_status = CASE 
                WHEN p_new_pending_amount <= 0 THEN 'Fully Paid'
                ELSE 'Partially Paid'
            END
        WHERE id = v_mm_id;
    END IF;

    -- Directly update the members table to ensure consistency
    -- This runs AFTER the member_memberships trigger would fire
    UPDATE public.members
    SET total_received_amount = p_new_total_received,
        pending_amount = p_new_pending_amount,
        payment_status = CASE WHEN p_new_pending_amount <= 0 THEN 'Paid' ELSE 'Pending' END
    WHERE id = p_member_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.sync_member_payment_amounts(UUID, UUID, NUMERIC, NUMERIC, NUMERIC) TO anon, authenticated, service_role;


-- =========================================================================
-- DONE! All triggers fixed, existing data corrected, RPC function deployed.
-- =========================================================================




-- =============================================================================
-- PART 26 : fix_member_received_amount_sync.sql
-- =============================================================================

-- =========================================================================
-- DATABASE MIGRATION: fix_member_received_amount_sync.sql
-- Run this script in your Supabase SQL Editor to:
-- 1. Add missing created_by_info column to finance_transactions table
-- 2. Sync received/pending amounts
-- 3. Deploy automatic calculation and protection triggers.
-- =========================================================================

-- 1. Ensure created_by_info column exists on finance_transactions table
ALTER TABLE public.finance_transactions 
ADD COLUMN IF NOT EXISTS created_by_info TEXT;

-- 2. Redeploy the automatic sync trigger function to include total_received_amount
CREATE OR REPLACE FUNCTION public.fn_sync_member_payment_status()
RETURNS TRIGGER AS $$
DECLARE
    v_member_id UUID;
    v_total_pending NUMERIC(12,2) := 0.0;
    v_total_received NUMERIC(12,2) := 0.0;
BEGIN
    v_member_id := COALESCE(NEW.member_id, OLD.member_id);
    IF v_member_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Calculate total remaining dues for this member from member_memberships
    SELECT COALESCE(SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0))), 0.0)
    INTO v_total_pending
    FROM public.member_memberships
    WHERE member_id = v_member_id;

    -- Calculate total received amount for this member from member_memberships
    SELECT COALESCE(SUM(COALESCE(paid_amount, 0.0)), 0.0)
    INTO v_total_received
    FROM public.member_memberships
    WHERE member_id = v_member_id;

    UPDATE public.members
    SET pending_amount = v_total_pending,
        total_received_amount = v_total_received,
        payment_status = CASE WHEN v_total_pending <= 0 THEN 'Paid' ELSE 'Pending' END
    WHERE id = v_member_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on member_memberships
DROP TRIGGER IF EXISTS trg_sync_member_payment_status ON public.member_memberships;
CREATE TRIGGER trg_sync_member_payment_status
AFTER INSERT OR UPDATE OR DELETE ON public.member_memberships
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_member_payment_status();

-- 3. CREATE BEFORE TRIGGER ON members TABLE TO PREVENT CLIENT OVERWRITES
CREATE OR REPLACE FUNCTION public.fn_force_member_payment_recalc()
RETURNS TRIGGER AS $$
BEGIN
    -- Recalculate total remaining dues for this member from member_memberships
    SELECT COALESCE(SUM(GREATEST(0.0, COALESCE(total_amount, 0.0) - COALESCE(paid_amount, 0.0))), 0.0)
    INTO NEW.pending_amount
    FROM public.member_memberships
    WHERE member_id = NEW.id;

    -- Recalculate total received amount for this member from member_memberships
    SELECT COALESCE(SUM(COALESCE(paid_amount, 0.0)), 0.0)
    INTO NEW.total_received_amount
    FROM public.member_memberships
    WHERE member_id = NEW.id;

    NEW.payment_status := CASE WHEN NEW.pending_amount <= 0 THEN 'Paid' ELSE 'Pending' END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger BEFORE INSERT OR UPDATE on members table
DROP TRIGGER IF EXISTS trg_force_member_payment_recalc ON public.members;
CREATE TRIGGER trg_force_member_payment_recalc
BEFORE INSERT OR UPDATE ON public.members
FOR EACH ROW
EXECUTE FUNCTION public.fn_force_member_payment_recalc();

-- 4. One-time update to synchronize existing members' received and pending balances
-- (This will also fire the BEFORE UPDATE trigger, correcting all database records instantly)
UPDATE public.members m
SET name = name; 




-- =============================================================================
-- PART 27 : fix_advance_finance_and_pending_salary.sql
-- =============================================================================

-- =========================================================================
-- DATABASE PATCH: fix_advance_finance_and_pending_salary.sql
-- Run this script in your Supabase SQL Editor to sync salary advances
-- with finance_transactions and fix all pending salary calculations.
-- =========================================================================

-- 1. UPDATE FUNCTION: fn_on_advance_ledger_created
-- Direct integration to finance_transactions (category: 'Salary', type: 'Expense')
CREATE OR REPLACE FUNCTION public.fn_on_advance_ledger_created()
RETURNS TRIGGER AS $$
DECLARE
    s_name TEXT;
    v_pay_method TEXT := 'Cash';
BEGIN
    IF (NEW.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status)) AND 
       (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('Approved'::public.advance_status, 'Given'::public.advance_status))) THEN
       
        SELECT name INTO s_name FROM public.staff WHERE id = NEW.staff_id;

        -- Safe insert into public.expenses (legacy support)
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'expenses') THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.expenses 
                WHERE gym_id = NEW.gym_id 
                  AND category = 'Salary Advance' 
                  AND amount = NEW.advance_amount 
                  AND date = NEW.given_date 
                  AND title LIKE '%' || COALESCE(s_name, 'Staff') || '%'
            ) THEN
                INSERT INTO public.expenses (
                    gym_id,
                    title,
                    amount,
                    category,
                    date,
                    notes
                ) VALUES (
                    NEW.gym_id,
                    'Staff Salary Advance - ' || COALESCE(s_name, 'Staff'),
                    NEW.advance_amount,
                    'Salary Advance',
                    NEW.given_date,
                    COALESCE(NEW.reason, NEW.notes, 'Staff Advance Payment Approved')
                );
            END IF;
        END IF;

        -- Direct insert into public.finance_transactions (modern accounting ledger)
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'finance_transactions') THEN
            IF NOT EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = NEW.id::TEXT) THEN
                -- Match payment method enum check constraints
                v_pay_method := COALESCE(NEW.payment_method, 'Cash');
                IF v_pay_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
                    v_pay_method := 'Other';
                END IF;

                INSERT INTO public.finance_transactions (
                    gym_id,
                    amount,
                    type,
                    category,
                    payment_method,
                    transaction_date,
                    expense_date,
                    entry_date,
                    reference_id,
                    notes
                ) VALUES (
                    NEW.gym_id,
                    NEW.advance_amount,
                    'Expense',
                    'Salary', -- Check constraint: Salary
                    v_pay_method,
                    NEW.given_date::TIMESTAMPTZ, -- Logs on the exact date of advance
                    NEW.given_date,
                    NEW.given_date,
                    NEW.id::TEXT,
                    'Staff Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || NEW.reason || ')', '')
                );
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger on salary_advance_ledger
DROP TRIGGER IF EXISTS trg_on_advance_ledger_created ON public.salary_advance_ledger;
CREATE TRIGGER trg_on_advance_ledger_created
AFTER INSERT OR UPDATE ON public.salary_advance_ledger
FOR EACH ROW EXECUTE FUNCTION public.fn_on_advance_ledger_created();


-- 2. UPDATE FUNCTION: get_staff_pending_salary
-- Deducts active salary advances of the current month
CREATE OR REPLACE FUNCTION public.get_staff_pending_salary(p_staff_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_curr_month TEXT := to_char(CURRENT_DATE, 'FMMonth YYYY');
    v_base_salary NUMERIC(12,2) := 0.0;
    v_is_paid BOOLEAN := FALSE;
    v_advance_deduction NUMERIC(12,2) := 0.0;
    s_name TEXT;
    v_gym_id UUID;
BEGIN
    SELECT name, COALESCE(salary, 0.0), gym_id INTO s_name, v_base_salary, v_gym_id
    FROM public.staff
    WHERE id = p_staff_id;

    IF s_name IS NULL THEN
        RETURN 0.0;
    END IF;

    -- Check if paid in salary_drafts
    IF EXISTS (
        SELECT 1 FROM public.salary_drafts
        WHERE staff_id = p_staff_id
          AND trim(salary_month) = trim(v_curr_month)
          AND status = 'Paid'::public.draft_status
    ) OR EXISTS (
        SELECT 1 FROM public.expenses
        WHERE gym_id = v_gym_id
          AND category = 'Salaries'
          AND title LIKE '%' || s_name || '%'
          AND to_char(date, 'FMMonth YYYY') = trim(v_curr_month)
    ) OR EXISTS (
        SELECT 1 FROM public.transactions
        WHERE gym_id = v_gym_id
          AND category = 'Salaries'
          AND type = 'Expense'
          AND title LIKE '%' || s_name || '%'
          AND to_char(date, 'FMMonth YYYY') = trim(v_curr_month)
    ) OR EXISTS (
        SELECT 1 FROM public.finance_transactions
        WHERE gym_id = v_gym_id
          AND category = 'Salary'
          AND type = 'Expense'
          AND title LIKE '%' || s_name || '%'
          AND to_char(transaction_date, 'FMMonth YYYY') = trim(v_curr_month)
    ) THEN
        v_is_paid := TRUE;
    END IF;

    IF v_is_paid THEN
        RETURN 0.0;
    ELSE
        -- Sum remaining amount of active advances assigned to this month
        SELECT COALESCE(SUM(sa.remaining_amount), 0.0) INTO v_advance_deduction
        FROM public.salary_advance_ledger sa 
        WHERE sa.staff_id = p_staff_id 
          AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
          AND (
            trim(sa.salary_month) = trim(v_curr_month)
            OR (
              (sa.salary_month IS NULL OR sa.salary_month = '') 
              AND to_char(sa.given_date, 'FMMonth YYYY') = trim(v_curr_month)
            )
          );

        RETURN GREATEST(0.0, v_base_salary - v_advance_deduction);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_staff_pending_salary(UUID) TO anon, authenticated, service_role;


-- 3. UPDATE FUNCTION: get_total_salary_due
-- Deducts active salary advances of the current month from active unpaid staff total
CREATE OR REPLACE FUNCTION public.get_total_salary_due(p_gym_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_month_str TEXT := to_char(CURRENT_DATE, 'FMMonth YYYY');
    v_total_due NUMERIC(12,2) := 0.0;
    v_total_advances NUMERIC(12,2) := 0.0;
BEGIN
    -- Sum base salaries of unpaid active staff
    SELECT COALESCE(SUM(s.salary), 0.0) INTO v_total_due
    FROM public.staff s
    WHERE s.gym_id = p_gym_id
      AND s.status = 'Active'
      AND NOT EXISTS (
          SELECT 1 FROM public.salary_drafts sd
          WHERE sd.staff_id = s.id
            AND trim(sd.salary_month) = trim(v_month_str)
            AND sd.status = 'Paid'::public.draft_status
      )
      AND NOT EXISTS (
          SELECT 1 FROM public.expenses e
          WHERE e.gym_id = p_gym_id
            AND e.category = 'Salaries'
            AND e.title LIKE '%Salary Payment%'
            AND to_char(e.date, 'FMMonth YYYY') = trim(v_month_str)
      );

    -- Sum remaining amount of active advances of these unpaid staff
    SELECT COALESCE(SUM(sa.remaining_amount), 0.0) INTO v_total_advances
    FROM public.salary_advance_ledger sa
    JOIN public.staff s ON sa.staff_id = s.id
    WHERE s.gym_id = p_gym_id
      AND s.status = 'Active'
      AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
      AND (
        trim(sa.salary_month) = trim(v_month_str)
        OR (
          (sa.salary_month IS NULL OR sa.salary_month = '') 
          AND to_char(sa.given_date, 'FMMonth YYYY') = trim(v_month_str)
        )
      )
      AND NOT EXISTS (
          SELECT 1 FROM public.salary_drafts sd
          WHERE sd.staff_id = s.id
            AND trim(sd.salary_month) = trim(v_month_str)
            AND sd.status = 'Paid'::public.draft_status
      )
      AND NOT EXISTS (
          SELECT 1 FROM public.expenses e
          WHERE e.gym_id = p_gym_id
            AND e.category = 'Salaries'
            AND e.title LIKE '%Salary Payment%'
            AND to_char(e.date, 'FMMonth YYYY') = trim(v_month_str)
      );

    RETURN GREATEST(0.0, v_total_due - v_total_advances);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_total_salary_due(UUID) TO anon, authenticated, service_role;


-- 4. UPDATE FUNCTION: get_owner_staff_cards_v1
-- Deducts active salary advances from the salary_pending field
CREATE OR REPLACE FUNCTION public.get_owner_staff_cards_v1(
    p_gym_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    staff_id UUID,
    name TEXT,
    role TEXT,
    avatar TEXT,
    status TEXT,
    salary_pending NUMERIC,
    present_days INT,
    leave_days INT,
    early_exit_count INT,
    last_check_in TEXT,
    is_checked_in BOOLEAN,
    current_date_str TEXT,
    is_salary_paid BOOLEAN,
    paid_amount NUMERIC
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_of_month DATE := date_trunc('month', p_date)::DATE;
    v_month_str TEXT := to_char(p_date, 'FMMonth YYYY');
BEGIN
    RETURN QUERY
    WITH monthly_attendance AS (
        SELECT 
            s.id AS s_id,
            COUNT(DISTINCT al.check_in::DATE)::INT AS month_present,
            COUNT(DISTINCT CASE WHEN al.status IN ('Leave', 'Half Leave', 'On Leave') THEN al.check_in::DATE END)::INT AS month_leave,
            COUNT(CASE WHEN al.status = 'Early Exit' OR COALESCE(al.early_exit_minutes, 0) > 0 THEN 1 END)::INT AS month_early_exit
        FROM public.staff s
        LEFT JOIN public.attendance_logs al 
               ON (al.user_id = s.user_id OR al.user_id = s.id)
              AND al.gym_id = p_gym_id
              AND al.user_type = 'Staff'
              AND al.status IN ('Present', 'Late', 'Half Day', 'Overtime', 'Early Exit')
              AND al.check_in::DATE >= v_start_of_month
              AND al.check_in::DATE <= p_date
        WHERE s.gym_id = p_gym_id
        GROUP BY s.id
    ),
    today_attendance AS (
        SELECT DISTINCT ON (s.id)
            s.id AS s_id,
            al.check_in,
            al.check_out,
            (al.check_out IS NULL) AS checked_in
        FROM public.staff s
        JOIN public.attendance_logs al 
          ON (al.user_id = s.user_id OR al.user_id = s.id)
         AND al.gym_id = p_gym_id
         AND al.user_type = 'Staff'
         AND al.check_in::DATE = p_date
        WHERE s.gym_id = p_gym_id
        ORDER BY s.id, al.check_in DESC
    ),
    paid_drafts AS (
        SELECT 
            s.id AS s_id,
            TRUE AS is_paid,
            COALESCE(sd.net_salary, s.salary, 0.0) AS amount
        FROM public.staff s
        LEFT JOIN public.salary_drafts sd
               ON sd.staff_id = s.id
              AND trim(sd.salary_month) = trim(v_month_str)
              AND sd.status = 'Paid'::public.draft_status
        WHERE s.gym_id = p_gym_id
          AND (
            sd.id IS NOT NULL OR EXISTS (
                SELECT 1 FROM public.expenses e
                WHERE e.gym_id = p_gym_id
                  AND e.category = 'Salaries'
                  AND e.title LIKE '%' || s.name || '%'
                  AND to_char(e.date, 'FMMonth YYYY') = trim(v_month_str)
            )
          )
    )
    SELECT 
        s.id AS staff_id,
        s.name,
        s.role,
        COALESCE(s.avatar, '') AS avatar,
        s.status,
        CASE 
            WHEN COALESCE(pd.is_paid, FALSE) = TRUE THEN 0.0
            ELSE GREATEST(0.0, COALESCE(s.salary, 0.0) - COALESCE((
                SELECT SUM(sa.remaining_amount) 
                FROM public.salary_advance_ledger sa 
                WHERE sa.staff_id = s.id 
                  AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
                  AND (
                    trim(sa.salary_month) = trim(v_month_str)
                    OR (
                      (sa.salary_month IS NULL OR sa.salary_month = '') 
                      AND to_char(sa.given_date, 'FMMonth YYYY') = trim(v_month_str)
                    )
                  )
            ), 0.0))
        END::NUMERIC AS salary_pending,
        COALESCE(ma.month_present, 0)::INT AS present_days,
        COALESCE(ma.month_leave, 0)::INT AS leave_days,
        COALESCE(ma.month_early_exit, 0)::INT AS early_exit_count,
        CASE 
            WHEN ta.check_in IS NOT NULL THEN to_char(ta.check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')
            ELSE 'N/A'
        END AS last_check_in,
        COALESCE(ta.checked_in, FALSE) AS is_checked_in,
        to_char(p_date, 'DD Mon YYYY') AS current_date_str,
        COALESCE(pd.is_paid, FALSE) AS is_salary_paid,
        COALESCE(pd.amount, 0.0)::NUMERIC AS paid_amount
    FROM public.staff s
    LEFT JOIN monthly_attendance ma ON s.id = ma.s_id
    LEFT JOIN today_attendance ta ON s.id = ta.s_id
    LEFT JOIN paid_drafts pd ON s.id = pd.s_id
    WHERE s.gym_id = p_gym_id
    ORDER BY s.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_owner_staff_cards_v1(UUID, DATE) TO anon, authenticated, service_role;


-- 5. BACKFILL: Sync existing historical advances to finance_transactions (if not synced)
DO $$
DECLARE
    r_adv RECORD;
    s_name TEXT;
    v_pay_method TEXT;
BEGIN
    FOR r_adv IN 
        SELECT * FROM public.salary_advance_ledger 
        WHERE status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Recovered'::public.advance_status)
    LOOP
        -- If transaction doesn't exist for this advance, backfill it using the exact given_date
        IF NOT EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = r_adv.id::TEXT) THEN
            SELECT name INTO s_name FROM public.staff WHERE id = r_adv.staff_id;
            
            v_pay_method := COALESCE(r_adv.payment_method, 'Cash');
            IF v_pay_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
                v_pay_method := 'Other';
            END IF;

            INSERT INTO public.finance_transactions (
                gym_id,
                amount,
                type,
                category,
                payment_method,
                transaction_date,
                expense_date,
                entry_date,
                reference_id,
                notes
            ) VALUES (
                r_adv.gym_id,
                r_adv.advance_amount,
                'Expense',
                'Salary',
                v_pay_method,
                r_adv.given_date::TIMESTAMPTZ, -- Logs on the exact date of advance
                r_adv.given_date,
                r_adv.given_date,
                r_adv.id::TEXT,
                'Staff Salary Advance - ' || COALESCE(s_name, 'Staff') || COALESCE(' (' || r_adv.reason || ')', '')
            );
        END IF;
    END LOOP;
END
$$;




-- =============================================================================
-- PART 28 : fix_salary_advances_trigger.sql
-- =============================================================================

-- ====================================================================
-- GYMOS - DATABASE FIX: REBUILD SALARY DRAFT TRIGGER & REMOVE OBSOLETE TRIGGERS
-- Run this in your Supabase SQL Editor to fully clean up references
-- to the deleted "salary_advances" table and solve the payment error!
-- ====================================================================

-- 1. Drop the obsolete trigger and function that references public.salary_advances
DROP TRIGGER IF EXISTS trg_on_salary_draft_paid ON public.salary_drafts;
DROP FUNCTION IF EXISTS public.fn_on_salary_draft_paid();

-- 2. Drop the old trigger function for advance salary creation if it exists
DROP FUNCTION IF EXISTS public.fn_on_advance_salary_created();

-- 3. Rebuild the main totals calculation trigger function for salary_drafts
-- Added lock check: If the draft is already Paid or is transitioning to Paid, we do NOT recalculate totals to prevent them from resetting to zero.
CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- If draft is already Paid, or is being updated to Paid, LOCK the calculated totals and do not recalculate.
    IF NEW.status = 'Paid'::public.draft_status OR (TG_OP = 'UPDATE' AND OLD.status = 'Paid'::public.draft_status) THEN
        RETURN NEW;
    END IF;

    -- Calculate pending commission amount for staff
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    -- Calculate active advance salary amount (using remaining_amount from the new ledger table)
    SELECT COALESCE(SUM(remaining_amount), 0.0) INTO adv_total 
    FROM public.salary_advance_ledger 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- Calculate manual additions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;

    -- Calculate manual deductions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    -- Set Draft values automatically in Backend
    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    -- Net Salary = (Base Salary + Commission + Additions) - (Advance Deduction + Manual Deductions)
    NEW.net_salary := (NEW.base_salary + comm_total + adj_add) - (adv_total + adj_ded);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach Trigger to salary_drafts table
DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;

CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();


-- 4. Rebuild vw_pending_salary_list view using salary_advance_ledger
CREATE OR REPLACE VIEW public.vw_pending_salary_list AS
SELECT 
    s.id AS staff_id,
    s.gym_id,
    s.name,
    s.role,
    s.avatar,
    s.salary AS base_salary,
    COALESCE((
        SELECT SUM(cl.amount) 
        FROM public.commission_ledger cl 
        WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
    ), 0.0) AS pending_commission,
    COALESCE((
        SELECT SUM(sa.remaining_amount) 
        FROM public.salary_advance_ledger sa 
        WHERE sa.staff_id = s.id 
          AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
    ), 0.0) AS total_advance,
    -- Pending Net = (Salary + Commission) - Advances Taken
    GREATEST(
        (s.salary + COALESCE((
            SELECT SUM(cl.amount) 
            FROM public.commission_ledger cl 
            WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
        ), 0.0)) - COALESCE((
            SELECT SUM(sa.remaining_amount) 
            FROM public.salary_advance_ledger sa 
            WHERE sa.staff_id = s.id 
              AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
        ), 0.0), 
        0.0
    ) AS net_pending_salary
FROM public.staff s
WHERE NOT EXISTS (
    SELECT 1 FROM public.salary_drafts sd 
    WHERE sd.staff_id = s.id 
      AND sd.salary_month = to_char(now(), 'Month YYYY')
      AND sd.status = 'Paid'::public.draft_status
);


-- 5. OPTIONAL: Fix existing paid draft for July 2026 if it was set to base salary only
-- Run this if your existing history item shows incorrect values.
-- UPDATE public.salary_drafts
-- SET commission_amount = 3150.00,
--     advance_deduction = 550.00,
--     net_salary = 14600.00
-- WHERE salary_month = 'July 2026' AND status = 'Paid';




-- =============================================================================
-- PART 29 : update_backend_salary_trigger.sql
-- =============================================================================

-- ====================================================
-- GYMOS - BACKEND AUTOMATIC SALARY ADVANCE DEDUCTION TRIGGER
-- ====================================================
-- Run this in your Supabase SQL Editor to calculate and deduct
-- Advance Salary automatically inside the Database backend!

CREATE OR REPLACE FUNCTION public.fn_calculate_salary_draft_totals()
RETURNS TRIGGER AS $$
DECLARE
    comm_total NUMERIC(12,2) := 0.0;
    adv_total NUMERIC(12,2) := 0.0;
    adj_add NUMERIC(12,2) := 0.0;
    adj_ded NUMERIC(12,2) := 0.0;
BEGIN
    -- 1. Calculate pending commission amount for staff
    SELECT COALESCE(SUM(amount), 0.0) INTO comm_total 
    FROM public.commission_ledger 
    WHERE staff_id = NEW.staff_id AND status = 'Pending'::public.commission_status;

    -- 2. Calculate advance salary amount (Approved, Given, or Pending status)
    SELECT COALESCE(SUM(amount), 0.0) INTO adv_total 
    FROM public.salary_advances 
    WHERE staff_id = NEW.staff_id 
      AND status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status);

    -- 3. Calculate manual additions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_add 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Addition'::public.adjustment_type;

    -- 4. Calculate manual deductions
    SELECT COALESCE(SUM(amount), 0.0) INTO adj_ded 
    FROM public.salary_adjustments 
    WHERE salary_draft_id = NEW.id AND type = 'Deduction'::public.adjustment_type;

    -- 5. Set Draft values automatically in Backend
    NEW.commission_amount := comm_total;
    NEW.advance_deduction := adv_total;
    NEW.other_additions := adj_add;
    NEW.other_deductions := adj_ded;
    
    -- Net Salary = (Base Salary + Commission + Additions) - (Advance Deduction + Manual Deductions)
    NEW.net_salary := (NEW.base_salary + comm_total + adj_add) - (adv_total + adj_ded);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach Trigger to salary_drafts table
DROP TRIGGER IF EXISTS trg_calculate_salary_draft_totals ON public.salary_drafts;

CREATE TRIGGER trg_calculate_salary_draft_totals
BEFORE INSERT OR UPDATE ON public.salary_drafts
FOR EACH ROW EXECUTE FUNCTION public.fn_calculate_salary_draft_totals();




-- =============================================================================
-- PART 30 : fix_dashboard_stats_expiry.sql
-- =============================================================================

-- Update get_gym_dashboard_stats function to dynamically query expiryDate from extra_fields in public.members table
CREATE OR REPLACE FUNCTION public.get_gym_dashboard_stats(p_gym_id UUID, p_target_date DATE)
RETURNS TABLE (
    monthly_revenue NUMERIC,
    active_members INT,
    total_members INT,
    today_attendance INT,
    expiring_today INT,
    expiring_15_days INT,
    pending_leaves INT,
    pending_holidays INT
) AS $$
DECLARE
    v_month_start DATE := date_trunc('month', p_target_date);
    v_month_end DATE := (date_trunc('month', p_target_date) + interval '1 month' - interval '1 day')::DATE;
BEGIN
    RETURN QUERY
    SELECT
        -- Monthly revenue in target month
        COALESCE((
            SELECT SUM(amount)
            FROM public.finance_transactions
            WHERE gym_id = p_gym_id
              AND type = 'Revenue'
              AND transaction_date::DATE BETWEEN v_month_start AND v_month_end
        ), 0.0)::NUMERIC AS monthly_revenue,

        -- Active members as of target date (joined on/before target date & active status)
        (
            SELECT COUNT(*)::INT
            FROM public.members
            WHERE gym_id = p_gym_id
              AND status = 'Active'
              AND public.safe_parse_date(join_date) <= p_target_date
        ) AS active_members,

        -- Total members as of target date (joined on/before target date)
        (
            SELECT COUNT(*)::INT
            FROM public.members
            WHERE gym_id = p_gym_id
              AND public.safe_parse_date(join_date) <= p_target_date
        ) AS total_members,

        -- Today's attendance (on target date)
        (
            SELECT COUNT(DISTINCT user_id)::INT
            FROM public.attendance_logs
            WHERE gym_id = p_gym_id
              AND user_type = 'Member'
              AND status IN ('Present', 'Late', 'Early Exit', 'Overtime')
              AND (
                date = to_char(p_target_date, 'dd-MM-yyyy')
                OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_target_date
              )
        ) AS today_attendance,

        -- Expiring today (from public.members extra_fields)
        (
            SELECT COUNT(*)::INT
            FROM public.members
            WHERE gym_id = p_gym_id
              AND extra_fields->>'expiryDate' IS NOT NULL 
              AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE = p_target_date
        ),

        -- Expiring in next 1 to 15 days (from public.members extra_fields, excluding today)
        (
            SELECT COUNT(*)::INT
            FROM public.members
            WHERE gym_id = p_gym_id
              AND extra_fields->>'expiryDate' IS NOT NULL 
              AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE > p_target_date
              AND (substring(extra_fields->>'expiryDate' from '^\d{4}-\d{2}-\d{2}'))::DATE <= (p_target_date + interval '15 days')::DATE
        ),

        -- Pending leaves (leaves with leave_type != 'Other')
        (
            SELECT COUNT(*)::INT
            FROM public.leave_requests
            WHERE gym_id = p_gym_id
              AND status = 'Pending'::public.leave_status
              AND leave_type != 'Other'::public.leave_type
        ),

        -- Pending holidays (leaves with leave_type = 'Other')
        (
            SELECT COUNT(*)::INT
            FROM public.leave_requests
            WHERE gym_id = p_gym_id
              AND status = 'Pending'::public.leave_status
              AND leave_type = 'Other'::public.leave_type
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;




-- =============================================================================
-- PART 31 : fix_attendance_date_column_rpc.sql
-- =============================================================================

-- =========================================================================
-- MIGRATION: fix_attendance_date_column_rpc.sql
-- Description: Updated RPC for get_staff_today_attendance_details_v2 with exact status and timestamps
-- =========================================================================

-- 1. Drop old overloaded signatures to prevent ambiguities
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID);
DROP FUNCTION IF EXISTS public.get_staff_today_attendance_details_v2(UUID, UUID, DATE);

-- 2. Re-create the function cleanly
CREATE OR REPLACE FUNCTION public.get_staff_today_attendance_details_v2(
    p_user_id UUID,
    p_gym_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff_id UUID := NULL;
    v_profile_user_id UUID := NULL;
    v_assigned_shift TEXT := 'Single Shift';
    v_first_check_in TEXT := NULL;
    v_first_check_out TEXT := NULL;
    v_second_check_in TEXT := NULL;
    v_second_check_out TEXT := NULL;
    v_first_shift_status TEXT := 'Not Checked In';
    v_second_shift_status TEXT := 'Not Checked In';
    v_total_working_mins INT := 0;
    v_can_check_in BOOLEAN := TRUE;
    v_can_check_out BOOLEAN := FALSE;
    v_open_log_id UUID := NULL;
    v_hours INT := 0;
    v_mins INT := 0;
    v_working_hours_str TEXT := '0h 00m';
BEGIN
    SELECT s.id, s.user_id, COALESCE(NULLIF(ssa.assignment_type, ''), NULLIF(s.shift, ''), 'Single Shift')
    INTO v_staff_id, v_profile_user_id, v_assigned_shift
    FROM public.staff s
    LEFT JOIN public.staff_shift_assignments ssa 
           ON (ssa.staff_id = s.id AND ssa.status = 'Active')
    WHERE (s.user_id = p_user_id OR s.id = p_user_id)
      AND s.gym_id = p_gym_id
    ORDER BY ssa.created_at DESC NULLS LAST
    LIMIT 1;

    IF v_staff_id IS NULL THEN
        SELECT s.id, s.user_id, COALESCE(s.shift, 'Single Shift')
        INTO v_staff_id, v_profile_user_id, v_assigned_shift
        FROM public.staff s
        WHERE (s.user_id = p_user_id OR s.id = p_user_id)
        LIMIT 1;
    END IF;

    WITH today_logs AS (
        SELECT 
            al.id,
            al.check_in,
            al.check_out,
            al.working_minutes,
            al.status,
            ROW_NUMBER() OVER (ORDER BY al.check_in ASC) as log_num
        FROM public.attendance_logs al
        WHERE al.gym_id = p_gym_id
          AND (al.user_id = p_user_id OR al.user_id = v_staff_id OR al.user_id = v_profile_user_id)
          AND al.check_in::DATE = p_date
    )
    SELECT
        MAX(CASE WHEN log_num = 1 THEN to_char(check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') END),
        MAX(CASE WHEN log_num = 1 THEN CASE WHEN check_out IS NOT NULL THEN to_char(check_out AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') ELSE NULL END END),
        MAX(CASE WHEN log_num = 1 THEN CASE WHEN check_out IS NOT NULL THEN 'Checked Out' ELSE 'Checked In' END END),
        MAX(CASE WHEN log_num = 2 THEN to_char(check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') END),
        MAX(CASE WHEN log_num = 2 THEN CASE WHEN check_out IS NOT NULL THEN to_char(check_out AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') ELSE NULL END END),
        MAX(CASE WHEN log_num = 2 THEN CASE WHEN check_out IS NOT NULL THEN 'Checked Out' ELSE 'Checked In' END END),
        SUM(COALESCE(working_minutes, 0))::INT,
        -- Fix the MAX(uuid) issue by casting id to TEXT inside MAX, then casting the result back to UUID.
        MAX(CASE WHEN check_out IS NULL THEN id::TEXT END)::UUID
    INTO
        v_first_check_in,
        v_first_check_out,
        v_first_shift_status,
        v_second_check_in,
        v_second_check_out,
        v_second_shift_status,
        v_total_working_mins,
        v_open_log_id
    FROM today_logs;

    IF v_open_log_id IS NOT NULL THEN
        v_can_check_in := FALSE;
        v_can_check_out := TRUE;
    ELSE
        v_can_check_in := TRUE;
        v_can_check_out := FALSE;
    END IF;

    v_total_working_mins := COALESCE(v_total_working_mins, 0);
    v_hours := v_total_working_mins / 60;
    v_mins := v_total_working_mins % 60;
    v_working_hours_str := v_hours || 'h ' || lpad(v_mins::text, 2, '0') || 'm';

    RETURN jsonb_build_object(
        'assigned_shift', CASE WHEN v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN 'Two Shifts' ELSE COALESCE(v_assigned_shift, 'Single Shift') END,
        'working_hours_today', v_working_hours_str,
        'can_check_in', v_can_check_in,
        'can_check_out', v_can_check_out,
        'first_shift_name', 'Shift 1',
        'first_shift_check_in', v_first_check_in,
        'first_shift_check_out', v_first_check_out,
        'first_shift_status', COALESCE(v_first_shift_status, 'Not Checked In'),
        'second_shift_name', 'Shift 2',
        'second_shift_check_in', v_second_check_in,
        'second_shift_check_out', v_second_check_out,
        'second_shift_status', COALESCE(v_second_shift_status, 'Not Checked In'),
        'is_checked_in', (v_open_log_id IS NOT NULL OR v_first_check_in IS NOT NULL)
    );
END;
$$;




-- =============================================================================
-- PART 32 : fix_scan_attendance_rpc.sql
-- =============================================================================

-- =========================================================================
-- MIGRATION: fix_scan_attendance_rpc.sql
-- Description: Robust process_scan_attendance_v3 procedure for QR Check-In / Check-Out
-- =========================================================================

CREATE OR REPLACE FUNCTION public.process_scan_attendance_v3(
    p_token TEXT,
    p_user_id UUID,
    p_method TEXT DEFAULT 'Static QR',
    p_ssid TEXT DEFAULT '',
    p_bssid TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_now TIMESTAMPTZ := now();
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    
    v_gym_id UUID := NULL;
    v_user_type TEXT := NULL;
    v_user_name TEXT := 'User';
    v_user_status TEXT := 'Active';
    v_staff_id UUID := NULL;
    v_member_id UUID := NULL;
    
    v_open_log_id UUID := NULL;
    v_check_in_time TIMESTAMPTZ := NULL;
    v_working_mins INT := 0;
    v_time_str TEXT := to_char(v_local_now, 'HH12:MI AM');
    v_clean_token TEXT := trim(p_token);
BEGIN
    -- 1. Resolve Gym ID from token (static_qr_token or active gym settings or attendance_qr_tokens)
    SELECT gym_id INTO v_gym_id
    FROM public.attendance_settings
    WHERE static_qr_token = v_clean_token OR v_clean_token LIKE '%' || static_qr_token || '%'
    LIMIT 1;

    IF v_gym_id IS NULL THEN
        SELECT gym_id INTO v_gym_id
        FROM public.attendance_qr_tokens
        WHERE token = v_clean_token OR v_clean_token LIKE '%' || token || '%'
        LIMIT 1;
    END IF;

    IF v_gym_id IS NULL THEN
        SELECT id INTO v_gym_id FROM public.gyms LIMIT 1;
    END IF;

    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Gym not found for this QR Code.');
    END IF;

    -- 2. Identify Staff or Member
    SELECT 'Staff', s.name, s.status, s.id INTO v_user_type, v_user_name, v_user_status, v_staff_id
    FROM public.staff s
    WHERE (s.user_id = p_user_id OR s.id = p_user_id) AND s.gym_id = v_gym_id
    LIMIT 1;

    IF v_user_type IS NULL THEN
        SELECT 'Staff', s.name, s.status, s.id, s.gym_id INTO v_user_type, v_user_name, v_user_status, v_staff_id, v_gym_id
        FROM public.staff s
        WHERE (s.user_id = p_user_id OR s.id = p_user_id)
        LIMIT 1;
    END IF;

    IF v_user_type IS NULL THEN
        SELECT 'Member', m.name, m.status, m.id INTO v_user_type, v_user_name, v_user_status, v_member_id
        FROM public.members m
        WHERE (m.user_id = p_user_id OR m.id = p_user_id)
        LIMIT 1;
    END IF;

    IF v_user_type IS NULL THEN
        SELECT COALESCE(full_name, 'Staff Member') INTO v_user_name FROM public.profiles WHERE id = p_user_id;
        v_user_type := 'Staff';
        v_staff_id := p_user_id;
    END IF;

    -- 3. Check for existing open log (Checked In today but not Checked Out)
    SELECT id, check_in INTO v_open_log_id, v_check_in_time
    FROM public.attendance_logs
    WHERE gym_id = v_gym_id
      AND (user_id = p_user_id OR user_id = v_staff_id)
      AND check_out IS NULL
      AND check_in::DATE = v_local_date
    ORDER BY check_in DESC
    LIMIT 1;

    -- 4. Execute Check-Out or Check-In
    IF v_open_log_id IS NOT NULL THEN
        v_working_mins := EXTRACT(EPOCH FROM (v_now - v_check_in_time)) / 60;
        
        UPDATE public.attendance_logs
        SET check_out = v_now,
            working_minutes = COALESCE(v_working_mins, 0)
        WHERE id = v_open_log_id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'action', 'check_out',
            'checkOutTime', v_time_str,
            'workingMins', v_working_mins,
            'message', 'Checked out successfully!'
        );
    ELSE
        INSERT INTO public.attendance_logs (
            gym_id,
            user_id,
            user_type,
            check_in,
            status,
            working_minutes
        ) VALUES (
            v_gym_id,
            COALESCE(v_staff_id, p_user_id),
            v_user_type,
            v_now,
            'Present',
            0
        );

        RETURN jsonb_build_object(
            'success', TRUE,
            'action', 'check_in',
            'checkInTime', v_time_str,
            'message', 'Checked in successfully!'
        );
    END IF;
END;
$$;




-- =============================================================================
-- PART 33 : fix_staff_shift_attendance.sql
-- =============================================================================

-- ====================================================
-- GYMOS SQL MIGRATION: FIX STAFF SHIFT ATTENDANCE ENGINE
-- ====================================================
-- This script fixes staff check-in/out issues.
-- 1. Bypasses shift timing restriction on Check-Outs (Staff can check out at any time).
-- 2. Correctly handles normal shifts and overnight night shifts on Check-In.

CREATE OR REPLACE FUNCTION public.process_qr_attendance(
    p_token TEXT,
    p_user_type TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_scanner_uid UUID := auth.uid();
    v_local_now TIMESTAMPTZ := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_local_date DATE := v_local_now::DATE;
    v_local_date_str TEXT := to_char(v_local_now, 'dd-MM-yyyy'); -- Standardized to dd-MM-yyyy

    -- Identified Gym & Display
    v_gym_id UUID;
    v_display_id UUID;
    v_token_expires TIMESTAMPTZ;
    v_token_used BOOLEAN;
    v_token_valid BOOLEAN := FALSE;
    v_qr_type TEXT := 'Dynamic';

    -- Settings
    v_settings RECORD;

    -- User Profile / Member / Staff Identification
    v_resolved_user_type TEXT := NULL;
    v_user_name TEXT;
    v_member_id UUID;
    v_member_status TEXT;
    v_staff_id UUID;
    v_staff_status TEXT;

    -- Shift variables
    v_shift_assignment RECORD;
    v_shift_record RECORD;
    v_assigned_shift_type TEXT;
    v_shift_start TIME;
    v_shift_end TIME;
    v_late_after TIME;
    v_shift_dur INTERVAL;
    v_midpoint TIME;

    -- Attendance calculations
    v_existing_log RECORD;
    v_log_id UUID;
    v_check_in_time TIMESTAMPTZ;
    v_working_mins INT := 0;
    v_late_mins INT := 0;
    v_early_exit_mins INT := 0;
    v_status TEXT := 'Present';
    v_shift_status TEXT := 'Completed';

    v_formatted_check_in TEXT;
    v_formatted_check_out TEXT;
    v_err_msg TEXT;
BEGIN
    -- 0. Check Authentication
    IF v_scanner_uid IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'User not authenticated. Please log in.');
    END IF;

    -- 1. STEP 1: VALIDATE QR TOKEN (Identify Gym & Display from Token)
    -- Check Dynamic QR Token first
    SELECT gym_id, display_id, expires_at, is_used
    INTO v_gym_id, v_display_id, v_token_expires, v_token_used
    FROM public.attendance_qr_tokens
    WHERE token = p_token
    LIMIT 1;

    IF v_gym_id IS NOT NULL THEN
        -- Dynamic Token Found
        IF (v_token_expires < now()) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has expired. Please scan the active QR code.');
        END IF;

        IF v_token_used THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'QR Code has already been scanned.');
        END IF;

        v_token_valid := TRUE;
        v_qr_type := 'Dynamic';

        -- Mark Dynamic Token as Used immediately to prevent reuse
        UPDATE public.attendance_qr_tokens SET is_used = TRUE WHERE token = p_token;
    ELSE
        -- Check Static QR Token in attendance_settings
        SELECT gym_id, is_enabled, method, static_qr_token, late_time_setting
        INTO v_settings
        FROM public.attendance_settings
        WHERE static_qr_token = p_token
        LIMIT 1;

        IF v_settings IS NOT NULL THEN
            v_gym_id := v_settings.gym_id;
            v_token_valid := TRUE;
            v_qr_type := 'Static';
        END IF;
    END IF;

    -- Invalid QR Token Check
    IF NOT v_token_valid OR v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid or unrecognized QR Code.');
    END IF;

    -- STEP 2: VALIDATE DISPLAY (If dynamic QR linked to a Display TV)
    IF v_display_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.attendance_displays 
            WHERE id = v_display_id AND gym_id = v_gym_id AND is_verified = TRUE AND is_enabled = TRUE
        ) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance display device is unverified or disabled.');
        END IF;
    END IF;

    -- Fetch Gym Attendance Settings
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_gym_id;
    IF v_settings IS NOT NULL AND NOT COALESCE(v_settings.is_enabled, TRUE) THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Attendance marking is currently disabled by gym administration.');
    END IF;

    -- STEP 3: IDENTIFY USER (Member vs Staff) WITH ROLE ISOLATION
    -- If p_user_type is specified, we isolate checks strictly to that role.
    -- Otherwise, check Staff first, then Member.
    
    -- Check if Staff
    IF p_user_type IS NULL OR p_user_type = 'Staff' THEN
        SELECT id, name, status INTO v_staff_id, v_user_name, v_staff_status
        FROM public.staff
        WHERE user_id = v_scanner_uid AND gym_id = v_gym_id
        LIMIT 1;

        IF v_staff_id IS NOT NULL THEN
            v_resolved_user_type := 'Staff';
        END IF;
    END IF;

    -- Check if Member
    IF v_resolved_user_type IS NULL AND (p_user_type IS NULL OR p_user_type = 'Member') THEN
        SELECT id, status INTO v_member_id, v_member_status
        FROM public.members
        WHERE user_id = v_scanner_uid AND gym_id = v_gym_id
        LIMIT 1;

        IF v_member_id IS NOT NULL THEN
            v_resolved_user_type := 'Member';
            SELECT COALESCE(full_name, 'Member') INTO v_user_name FROM public.profiles WHERE id = v_scanner_uid;
        END IF;
    END IF;

    -- Cross-Gym Isolation Check: User belongs to another gym
    IF v_resolved_user_type IS NULL THEN
        IF EXISTS (SELECT 1 FROM public.members WHERE user_id = v_scanner_uid) OR EXISTS (SELECT 1 FROM public.staff WHERE user_id = v_scanner_uid) THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'You are trying to mark attendance in another gym.');
        ELSE
            RETURN jsonb_build_object('success', FALSE, 'reason', 'User record not associated with this Gym.');
        END IF;
    END IF;

    -- ====================================================
    -- MEMBER ATTENDANCE FLOW
    -- ====================================================
    IF v_resolved_user_type = 'Member' THEN
        -- Verify membership status
        IF v_member_status NOT IN ('Active', 'Trial') THEN
            RETURN jsonb_build_object('success', FALSE, 'reason', 'Membership is inactive or expired. Status: ' || COALESCE(v_member_status, 'Expired'));
        END IF;

        -- Check if attendance marked today (Timezone safe comparison)
        SELECT * INTO v_existing_log 
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date);

        IF v_existing_log IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', TRUE,
                'user_type', 'Member',
                'user_name', COALESCE(v_user_name, 'Member'),
                'status', v_existing_log.status,
                'check_in', to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'attendance_date', v_existing_log.date,
                'method', v_existing_log.method,
                'message', 'Attendance already marked for today.'
            );
        END IF;

        -- Create Member Check In
        INSERT INTO public.attendance_logs (
            gym_id, user_id, role, user_type, member_id, date, check_in, status, method, qr_type
        ) VALUES (
            v_gym_id, v_scanner_uid, 'Member', 'Member', v_member_id, v_local_date_str, now(), 'Present', COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
        ) RETURNING id INTO v_log_id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'already_marked', FALSE,
            'user_type', 'Member',
            'user_name', COALESCE(v_user_name, 'Member'),
            'status', 'Present',
            'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
            'attendance_date', v_local_date_str,
            'method', 'QR Code',
            'message', 'Member attendance checked in successfully!'
        );
    END IF;

    -- ====================================================
    -- STAFF ATTENDANCE & SHIFT ENGINE FLOW
    -- ====================================================
    IF v_resolved_user_type = 'Staff' THEN
        -- Resolve Assigned Shift for Staff
        SELECT * INTO v_shift_assignment
        FROM public.staff_shift_assignments
        WHERE staff_id = v_staff_id AND gym_id = v_gym_id AND status = 'Active'
        ORDER BY created_at DESC LIMIT 1;

        v_assigned_shift_type := COALESCE(v_shift_assignment.assignment_type, 'Single Shift');

        -- Lookup Shift Definition Timings
        IF v_assigned_shift_type = 'Morning Shift' THEN
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Morning Shift';
        ELSIF v_assigned_shift_type = 'Evening Shift' THEN
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Evening Shift';
        ELSE
            SELECT * INTO v_shift_record FROM public.gym_shifts WHERE gym_id = v_gym_id AND shift_type = 'Single Shift';
        END IF;

        -- Fetch existing staff attendance log for today (Timezone safe comparison)
        SELECT * INTO v_existing_log
        FROM public.attendance_logs
        WHERE user_id = v_scanner_uid 
          AND gym_id = v_gym_id 
          AND (date = v_local_date_str OR (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = v_local_date)
        ORDER BY check_in DESC LIMIT 1;

        -- SHIFT VALIDATION: Validate shift window if configured (ONLY ON CHECK-IN)
        IF (v_existing_log IS NULL OR v_existing_log.check_out IS NOT NULL) AND v_shift_record IS NOT NULL THEN
            DECLARE
                v_allowed_start TIME := (v_shift_record.start_time_24h - INTERVAL '1 hour')::TIME;
                v_allowed_end TIME := (v_shift_record.end_time_24h + INTERVAL '2 hours')::TIME;
                v_is_outside BOOLEAN := FALSE;
            BEGIN
                IF v_allowed_start <= v_allowed_end THEN
                    -- Normal Shift
                    IF v_local_time < v_allowed_start OR v_local_time > v_allowed_end THEN
                        v_is_outside := TRUE;
                    END IF;
                ELSE
                    -- Overnight Shift
                    IF v_local_time < v_allowed_start AND v_local_time > v_allowed_end THEN
                        v_is_outside := TRUE;
                    END IF;
                END IF;

                IF v_is_outside THEN
                    v_err_msg := 'You are not assigned to this shift. Your shift is ' || 
                                 COALESCE(v_shift_record.shift_type, 'Shift') || ' ' || 
                                 COALESCE(v_shift_record.start_time, '') || ' - ' || COALESCE(v_shift_record.end_time, '') || '.';
                    RETURN jsonb_build_object('success', FALSE, 'reason', v_err_msg);
                END IF;
            END;
        END IF;

        -- NO PREVIOUS LOG TODAY -> CREATE CHECK IN
        IF v_existing_log IS NULL OR v_existing_log.check_out IS NOT NULL THEN
            -- Calculate Late Minutes if configured
            v_status := 'Present';
            v_late_mins := 0;

            IF v_settings IS NOT NULL AND v_settings.late_time_setting IS NOT NULL AND v_settings.late_time_setting <> '' THEN
                BEGIN
                    v_late_after := v_settings.late_time_setting::TIME;
                    IF v_local_time > v_late_after THEN
                        v_status := 'Late';
                        v_late_mins := EXTRACT(EPOCH FROM (v_local_time - v_late_after)) / 60;
                    END IF;
                EXCEPTION WHEN OTHERS THEN
                    v_late_mins := 0;
                END;
            END IF;

            -- Check if check-in is past midpoint of the shift (Half Leave)
            IF v_shift_record IS NOT NULL THEN
                v_shift_dur := (v_shift_record.end_time_24h - v_shift_record.start_time_24h);
                IF v_shift_dur < INTERVAL '0' THEN
                    v_shift_dur := v_shift_dur + INTERVAL '24 hours';
                END IF;
                v_midpoint := (v_shift_record.start_time_24h + (v_shift_dur / 2))::TIME;
                
                IF v_shift_record.end_time_24h < v_shift_record.start_time_24h THEN
                    IF (v_local_time >= v_shift_record.start_time_24h AND v_local_time > v_midpoint) OR
                       (v_local_time < v_shift_record.start_time_24h AND (v_local_time + INTERVAL '24 hours')::TIME > v_midpoint) THEN
                        v_status := 'Half Leave';
                    END IF;
                ELSE
                    IF v_local_time > v_midpoint THEN
                        v_status := 'Half Leave';
                    END IF;
                END IF;
            END IF;

            INSERT INTO public.attendance_logs (
                gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, status, shift_status, late_minutes, method, qr_type
            ) VALUES (
                v_gym_id, v_scanner_uid, 'Staff', 'Staff', v_staff_id, v_shift_record.id, v_local_date_str, now(), v_status, 'Incomplete', v_late_mins, COALESCE(v_qr_type || ' QR', 'Static QR'), v_qr_type
            ) RETURNING id INTO v_log_id;

            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', FALSE,
                'user_type', 'Staff',
                'action', 'Check In',
                'status', v_status,
                'check_in', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'late_minutes', v_late_mins,
                'shift_status', 'Incomplete',
                'message', 'Staff Check In successful!'
            );
        END IF;

        -- EXISTING LOG WITH NO CHECK OUT -> PERFORM CHECK OUT
        IF v_existing_log IS NOT NULL AND v_existing_log.check_out IS NULL THEN
            v_working_mins := EXTRACT(EPOCH FROM (now() - v_existing_log.check_in)) / 60;
            v_early_exit_mins := 0;

            IF v_shift_record IS NOT NULL AND v_shift_record.end_time_24h IS NOT NULL THEN
                IF v_local_time < v_shift_record.end_time_24h THEN
                    v_early_exit_mins := EXTRACT(EPOCH FROM (v_shift_record.end_time_24h - v_local_time)) / 60;
                END IF;
            END IF;

            UPDATE public.attendance_logs
            SET check_out = now(),
                working_minutes = v_working_mins,
                early_exit_minutes = v_early_exit_mins,
                shift_status = 'Completed',
                updated_at = now()
            WHERE id = v_existing_log.id;

            RETURN jsonb_build_object(
                'success', TRUE,
                'already_marked', TRUE,
                'user_type', 'Staff',
                'action', 'Check Out',
                'status', v_existing_log.status,
                'check_in', to_char(v_existing_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'check_out', to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH:MI AM'),
                'working_minutes', v_working_mins,
                'early_exit_minutes', v_early_exit_mins,
                'shift_status', 'Completed',
                'message', 'Staff Check Out successful!'
            );
        END IF;
    END IF;

    RETURN jsonb_build_object('success', FALSE, 'reason', 'Unable to process attendance request.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.process_qr_attendance(TEXT, TEXT) TO anon, authenticated, service_role;




-- =============================================================================
-- PART 34 : fix_display_dynamic_qr.sql
-- =============================================================================

-- ====================================================
-- GYMOS - COMPLETE FIX FOR DYNAMIC QR DISPLAY
-- Run this ENTIRE script in Supabase SQL Editor
-- ====================================================

-- Ensure pgcrypto extension is enabled (needed for gen_random_bytes)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ====================================================
-- 1. FIX: get_display_static_qr (handles BOTH static & dynamic QR)
-- ====================================================
CREATE OR REPLACE FUNCTION public.get_display_static_qr(
    p_display_public_id TEXT,
    p_secret TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
    v_settings RECORD;
    v_dynamic_token TEXT;
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- Verify display device is active, verified, and matches the secret
    SELECT * INTO v_display 
    FROM public.attendance_displays 
    WHERE display_public_id = p_display_public_id;
    
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display not found.');
    END IF;
    
    IF NOT v_display.is_verified OR NOT v_display.is_enabled THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display is not verified or is disabled.');
    END IF;
    
    IF v_display.device_secret <> p_secret THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Invalid device credentials.');
    END IF;

    -- Fetch attendance settings for the gym
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_display.gym_id;

    IF v_settings IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'No attendance settings found for this gym. Please configure attendance settings first.');
    END IF;

    -- If mode is Dynamic QR, generate dynamic token securely
    IF v_settings.method IN ('Dynamic QR', 'Dynamic QR + WiFi', 'QR Only', 'QR + WiFi') THEN
        v_dynamic_token := 'dyn_' || encode(gen_random_bytes(12), 'hex');
        v_expires_at := now() + ((COALESCE(v_settings.qr_validity_seconds, 30) || ' seconds')::INTERVAL);

        INSERT INTO public.attendance_qr_tokens (gym_id, display_id, token, expires_at)
        VALUES (v_display.gym_id, v_display.id, v_dynamic_token, v_expires_at);

        RETURN jsonb_build_object(
            'success', TRUE,
            'qr_type', 'Dynamic',
            'static_qr_token', v_dynamic_token,
            'expires_in_seconds', COALESCE(v_settings.qr_validity_seconds, 30)
        );
    ELSE
        -- Return static token from settings
        RETURN jsonb_build_object(
            'success', TRUE,
            'qr_type', 'Static',
            'static_qr_token', COALESCE(v_settings.static_qr_token, 'static_default_token')
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_display_static_qr TO anon, authenticated, service_role;

-- ====================================================
-- 2. FIX: send_display_heartbeat (returns method + validity for real-time sync)
-- ====================================================
CREATE OR REPLACE FUNCTION public.send_display_heartbeat(
    p_public_id TEXT,
    p_secret TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_display RECORD;
    v_settings RECORD;
BEGIN
    SELECT * INTO v_display FROM public.attendance_displays WHERE display_public_id = p_public_id;
    IF v_display IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display not found');
    END IF;

    IF NOT v_display.is_verified OR v_display.device_secret <> p_secret THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display authorization failed');
    END IF;

    UPDATE public.attendance_displays
    SET last_seen = now()
    WHERE id = v_display.id;

    -- Fetch attendance settings for the gym to return current method & validity
    SELECT * INTO v_settings FROM public.attendance_settings WHERE gym_id = v_display.gym_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'is_enabled', v_display.is_enabled,
        'method', COALESCE(v_settings.method, 'Static QR'),
        'qr_validity_seconds', COALESCE(v_settings.qr_validity_seconds, 30)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.send_display_heartbeat TO anon, authenticated, service_role;

-- ====================================================
-- 3. ENSURE: attendance_qr_tokens table has correct schema
-- This adds missing columns if the table was created from an older migration
-- ====================================================
DO $$
BEGIN
    -- Add display_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'attendance_qr_tokens' 
        AND column_name = 'display_id'
    ) THEN
        ALTER TABLE public.attendance_qr_tokens ADD COLUMN display_id UUID REFERENCES public.attendance_displays(id) ON DELETE CASCADE;
    END IF;

    -- Add is_used column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'attendance_qr_tokens' 
        AND column_name = 'is_used'
    ) THEN
        ALTER TABLE public.attendance_qr_tokens ADD COLUMN is_used BOOLEAN DEFAULT FALSE NOT NULL;
    END IF;

    -- Add gym_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'attendance_qr_tokens' 
        AND column_name = 'gym_id'
    ) THEN
        ALTER TABLE public.attendance_qr_tokens ADD COLUMN gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Ensure RLS policies allow the SECURITY DEFINER functions to work
ALTER TABLE public.attendance_qr_tokens ENABLE ROW LEVEL SECURITY;

-- Grant access
GRANT ALL ON TABLE public.attendance_qr_tokens TO anon, authenticated, service_role;




-- =============================================================================
-- PART 35 : redeploy_attendance_fixes.sql
-- =============================================================================

-- =========================================================================
-- DATABASE MIGRATION SCRIPT: REDEPLOY ATTENDANCE & SHIFT FIXES
-- Copy and run this script in your Supabase SQL Editor to apply the fix.
-- =========================================================================

-- 1. DROP & REBUILD: get_staff_today_attendance_details_v2
-- Ensures logs are associated with Morning/Evening shifts by shift_id rather than sequence.
CREATE OR REPLACE FUNCTION public.get_staff_today_attendance_details_v2(
    p_user_id UUID,
    p_gym_id UUID,
    p_date DATE DEFAULT (now() AT TIME ZONE 'Asia/Kolkata')::DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff_id UUID := NULL;
    v_profile_user_id UUID := NULL;
    v_assigned_shift TEXT := 'Single Shift';
    v_first_check_in TEXT := NULL;
    v_first_check_out TEXT := NULL;
    v_second_check_in TEXT := NULL;
    v_second_check_out TEXT := NULL;
    v_first_shift_status TEXT := 'Not Checked In';
    v_second_shift_status TEXT := 'Not Checked In';
    v_total_working_mins INT := 0;
    v_can_check_in BOOLEAN := TRUE;
    v_can_check_out BOOLEAN := FALSE;
    v_open_log_id UUID := NULL;
    v_hours INT := 0;
    v_mins INT := 0;
    v_working_hours_str TEXT := '0h 00m';
    
    -- Helper variables for robust shift mapping
    v_morning_shift_id UUID := NULL;
    v_evening_shift_id UUID := NULL;
    v_morning_log RECORD;
    v_evening_log RECORD;
    v_single_log RECORD;
BEGIN
    -- Resolve Staff Record details
    SELECT s.id, s.user_id, COALESCE(NULLIF(ssa.assignment_type, ''), NULLIF(s.shift, ''), 'Single Shift')
    INTO v_staff_id, v_profile_user_id, v_assigned_shift
    FROM public.staff s
    LEFT JOIN public.staff_shift_assignments ssa 
           ON (ssa.staff_id = s.id AND ssa.status = 'Active')
    WHERE (s.user_id = p_user_id OR s.id = p_user_id)
      AND s.gym_id = p_gym_id
    ORDER BY ssa.created_at DESC NULLS LAST
    LIMIT 1;

    IF v_staff_id IS NULL THEN
        SELECT s.id, s.user_id, COALESCE(s.shift, 'Single Shift')
        INTO v_staff_id, v_profile_user_id, v_assigned_shift
        FROM public.staff s
        WHERE (s.user_id = p_user_id OR s.id = p_user_id)
        LIMIT 1;
    END IF;

    -- Fetch morning shift ID and evening shift ID
    SELECT id INTO v_morning_shift_id FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Morning Shift';
    SELECT id INTO v_evening_shift_id FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Evening Shift';

    -- Fetch logs for today's local date (Asia/Kolkata) and map them
    IF v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN
        -- Morning shift log
        SELECT * INTO v_morning_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
          AND shift_id = v_morning_shift_id
        ORDER BY check_in ASC
        LIMIT 1;

        -- Evening shift log
        SELECT * INTO v_evening_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
          AND shift_id = v_evening_shift_id
        ORDER BY check_in ASC
        LIMIT 1;

        -- Set Morning Shift details
        IF v_morning_log.id IS NOT NULL THEN
            IF v_morning_log.status = 'Absent' THEN
                v_first_shift_status := 'Absent';
            ELSE
                v_first_check_in := to_char(v_morning_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                IF v_morning_log.check_out IS NOT NULL THEN
                    v_first_check_out := to_char(v_morning_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    v_first_shift_status := 'Checked Out';
                ELSE
                    v_first_shift_status := 'Checked In';
                    v_open_log_id := v_morning_log.id;
                END IF;
            END IF;
            v_total_working_mins := v_total_working_mins + COALESCE(v_morning_log.working_minutes, 0);
        END IF;

        -- Set Evening Shift details
        IF v_evening_log.id IS NOT NULL THEN
            IF v_evening_log.status = 'Absent' THEN
                v_second_shift_status := 'Absent';
            ELSE
                v_second_check_in := to_char(v_evening_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                IF v_evening_log.check_out IS NOT NULL THEN
                    v_second_check_out := to_char(v_evening_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    v_second_shift_status := 'Checked Out';
                ELSE
                    v_second_shift_status := 'Checked In';
                    v_open_log_id := v_evening_log.id;
                END IF;
            END IF;
            v_total_working_mins := v_total_working_mins + COALESCE(v_evening_log.working_minutes, 0);
        END IF;
    ELSE
        -- Single shift log
        SELECT * INTO v_single_log 
        FROM public.attendance_logs
        WHERE gym_id = p_gym_id
          AND (user_id = p_user_id OR staff_id = v_staff_id OR user_id = v_profile_user_id)
          AND (check_in AT TIME ZONE 'Asia/Kolkata')::DATE = p_date
        ORDER BY check_in ASC
        LIMIT 1;

        IF v_single_log.id IS NOT NULL THEN
            IF v_single_log.status = 'Absent' THEN
                v_first_shift_status := 'Absent';
            ELSE
                v_first_check_in := to_char(v_single_log.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                IF v_single_log.check_out IS NOT NULL THEN
                    v_first_check_out := to_char(v_single_log.check_out AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM');
                    v_first_shift_status := 'Checked Out';
                ELSE
                    v_first_shift_status := 'Checked In';
                    v_open_log_id := v_single_log.id;
                END IF;
            END IF;
            v_total_working_mins := COALESCE(v_single_log.working_minutes, 0);
        END IF;
    END IF;

    IF v_open_log_id IS NOT NULL THEN
        v_can_check_in := FALSE;
        v_can_check_out := TRUE;
    ELSE
        v_can_check_in := TRUE;
        v_can_check_out := FALSE;
    END IF;

    v_total_working_mins := COALESCE(v_total_working_mins, 0);
    v_hours := v_total_working_mins / 60;
    v_mins := v_total_working_mins % 60;
    v_working_hours_str := v_hours || 'h ' || lpad(v_mins::text, 2, '0') || 'm';

    RETURN jsonb_build_object(
        'assigned_shift', CASE WHEN v_assigned_shift IN ('Two Shifts', 'Both Shifts') THEN 'Two Shifts' ELSE COALESCE(v_assigned_shift, 'Single Shift') END,
        'working_hours_today', v_working_hours_str,
        'can_check_in', v_can_check_in,
        'can_check_out', v_can_check_out,
        'first_shift_name', 'Shift 1',
        'first_shift_check_in', v_first_check_in,
        'first_shift_check_out', v_first_check_out,
        'first_shift_status', COALESCE(v_first_shift_status, 'Not Checked In'),
        'second_shift_name', 'Shift 2',
        'second_shift_check_in', v_second_check_in,
        'second_shift_check_out', v_second_check_out,
        'second_shift_status', COALESCE(v_second_shift_status, 'Not Checked In'),
        'is_checked_in', (v_open_log_id IS NOT NULL)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_today_attendance_details_v2(UUID, UUID, DATE) TO anon, authenticated, service_role;


-- 2. DROP & REBUILD: cron_auto_mark_absent
-- Prevents time wrap-around bugs and evaluates shift deadlines robustly across today and yesterday.
DROP FUNCTION IF EXISTS public.cron_auto_mark_absent();
CREATE OR REPLACE FUNCTION public.cron_auto_mark_absent()
RETURNS VOID AS $$
DECLARE
    v_local_now TIMESTAMP := now() AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := (now() AT TIME ZONE 'Asia/Kolkata')::TIME;
    v_local_date DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
    
    v_gym RECORD;
    v_staff RECORD;
    v_member RECORD;
    v_shift RECORD;
    v_assignment RECORD;
    v_exists BOOLEAN;
    v_latest_shift_end TIME;
    v_trigger_timestamp TIMESTAMPTZ;
    
    -- Variables for checking both today and yesterday to cover midnight crossovers
    v_check_date DATE;
    v_check_date_str TEXT;
BEGIN
    -- Loop through gyms where auto_mark_absent is enabled
    FOR v_gym IN 
        SELECT gym_id 
        FROM public.attendance_settings 
        WHERE auto_mark_absent = TRUE
    LOOP
        -- ==========================================
        -- 1. STAFF AUTO-ABSENT ENGINE
        -- ==========================================
        FOR v_staff IN 
            SELECT id, user_id 
            FROM public.staff 
            WHERE gym_id = v_gym.gym_id AND status = 'Active'
        LOOP
            -- Get active shift assignment
            SELECT * INTO v_assignment 
            FROM public.staff_shift_assignments 
            WHERE staff_id = v_staff.id AND gym_id = v_gym.gym_id AND status = 'Active'
            LIMIT 1;
            
            IF v_assignment IS NOT NULL THEN
                -- Check both today and yesterday
                FOR v_check_date IN SELECT v_local_date UNION SELECT (v_local_date - 1) LOOP
                    v_check_date_str := to_char(v_check_date, 'dd-MM-yyyy');
                    
                    -- CASE A: Both Shifts Assigned
                    IF v_assignment.assignment_type = 'Both Shifts' THEN
                        -- Check Morning Shift
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = 'Morning Shift';
                        IF v_shift IS NOT NULL THEN
                            v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            
                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;
                        
                        -- Check Evening Shift
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = 'Evening Shift';
                        IF v_shift IS NOT NULL THEN
                            v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            
                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;
                    
                    -- CASE B: Single/Morning/Evening Shift
                    ELSE
                        SELECT * INTO v_shift FROM public.gym_shifts WHERE id = v_assignment.shift_id;
                        IF v_shift IS NULL THEN
                            SELECT * INTO v_shift FROM public.gym_shifts WHERE gym_id = v_gym.gym_id AND shift_type = v_assignment.assignment_type;
                        END IF;
                        
                        IF v_shift IS NOT NULL THEN
                            IF v_shift.shift_type = 'Single Shift' THEN
                                v_trigger_timestamp := (v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata';
                            ELSE
                                v_trigger_timestamp := ((v_check_date::TEXT || ' ' || v_shift.end_time_24h::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '1 hour';
                            END IF;

                            IF now() > v_trigger_timestamp THEN
                                SELECT EXISTS (
                                    SELECT 1 FROM public.attendance_logs 
                                    WHERE (user_id = v_staff.user_id OR staff_id = v_staff.id)
                                      AND gym_id = v_gym.gym_id 
                                      AND date = v_check_date_str 
                                      AND shift_id = v_shift.id
                                ) INTO v_exists;
                                
                                IF NOT v_exists THEN
                                    INSERT INTO public.attendance_logs (
                                        gym_id, user_id, role, user_type, staff_id, shift_id, date, check_in, check_out, status, shift_status, method
                                    ) VALUES (
                                        v_gym.gym_id, v_staff.user_id, 'Staff', 'Staff', v_staff.id, v_shift.id, v_check_date_str, v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'Completed', 'System'
                                    );
                                END IF;
                            END IF;
                        END IF;
                    END IF;
                END LOOP;
            END IF;
        END LOOP;

        -- ==========================================
        -- 2. MEMBER AUTO-ABSENT ENGINE
        -- ==========================================
        -- Fetch the latest shift end time in the gym. Fallback to 10:00 PM if no shifts.
        SELECT COALESCE(MAX(end_time_24h), '22:00:00'::TIME) INTO v_latest_shift_end
        FROM public.gym_shifts
        WHERE gym_id = v_gym.gym_id;

        -- Trigger at 2 hours after latest shift ends
        v_trigger_timestamp := ((v_local_date::TEXT || ' ' || v_latest_shift_end::TEXT)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata') + INTERVAL '2 hours';

        IF now() > v_trigger_timestamp THEN
            FOR v_member IN 
                SELECT id, user_id 
                FROM public.members 
                WHERE gym_id = v_gym.gym_id AND status IN ('Active', 'Trial')
            LOOP
                SELECT EXISTS (
                    SELECT 1 FROM public.attendance_logs 
                    WHERE user_id = v_member.user_id 
                      AND gym_id = v_gym.gym_id 
                      AND date = to_char(v_local_date, 'dd-MM-yyyy') 
                      AND shift_id IS NULL
                ) INTO v_exists;
                
                IF NOT v_exists THEN
                    INSERT INTO public.attendance_logs (
                        gym_id, user_id, role, user_type, member_id, date, check_in, check_out, status, method
                    ) VALUES (
                        v_gym.gym_id, v_member.user_id, 'Member', 'Member', v_member.id, to_char(v_local_date, 'dd-MM-yyyy'), v_trigger_timestamp, v_trigger_timestamp, 'Absent', 'System'
                    );
                END IF;
            END LOOP;
        END IF;
        
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.cron_auto_mark_absent() TO anon, authenticated, service_role;


-- 3. DROP & REBUILD: generate_dynamic_qr_token
-- Automatically cleans up expired (older than 5 minutes) or used tokens to prevent database storage bloating.
CREATE OR REPLACE FUNCTION public.generate_dynamic_qr_token(p_gym_id UUID, p_display_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_token TEXT;
    v_nonce TEXT;
    v_expires_at TIMESTAMPTZ;
    v_validity_secs INT;
    v_is_verified BOOLEAN;
BEGIN
    -- Check if display session exists and is verified
    SELECT is_verified INTO v_is_verified 
    FROM public.attendance_display_sessions 
    WHERE display_id = p_display_id;

    IF v_is_verified IS NULL OR NOT v_is_verified THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'Display not verified or offline');
    END IF;

    SELECT qr_validity_seconds INTO v_validity_secs 
    FROM public.attendance_settings 
    WHERE gym_id = p_gym_id;

    v_nonce := gen_random_uuid()::text;
    v_expires_at := now() + (v_validity_secs || ' seconds')::INTERVAL;
    v_token := encode(digest(p_gym_id::text || v_nonce || v_expires_at::text, 'sha256'), 'hex');

    -- Clean up expired or used tokens for this display to save database storage
    DELETE FROM public.attendance_qr_tokens 
    WHERE display_id = p_display_id 
      AND (expires_at < now() - INTERVAL '5 minutes' OR is_used = TRUE);

    INSERT INTO public.attendance_qr_tokens (token, gym_id, display_id, nonce, expires_at)
    VALUES (v_token, p_gym_id, p_display_id, v_nonce, v_expires_at);

    RETURN jsonb_build_object(
        'success', TRUE,
        'token', v_token,
        'expires_at', v_expires_at,
        'validity', v_validity_secs
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.generate_dynamic_qr_token(UUID, UUID) TO anon, authenticated, service_role;





-- =============================================================================
-- PART 36 : redeploy_finance_sync_accruals.sql
-- =============================================================================

-- =========================================================================
-- DATABASE MIGRATION: redeploy_finance_sync_accruals.sql
-- Run this script in your Supabase SQL Editor to link salary payments 
-- to their target accrual months and sync all records with finance_transactions.
-- =========================================================================

-- 1. Create or replace the sync trigger function
CREATE OR REPLACE FUNCTION public.fn_sync_transactions_to_finance()
RETURNS TRIGGER AS $$
DECLARE
    v_payment_method TEXT := 'Cash';
    v_category TEXT := 'Other';
    v_expense_date DATE;
    v_revenue_date DATE;
    v_draft_month TEXT;
    v_notes TEXT;
BEGIN
    -- Avoid duplicate syncs if we insert directly or if it already exists
    IF EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = NEW.id::TEXT) THEN
        RETURN NEW;
    END IF;

    -- Map category to allowed enum check constraints in public.finance_transactions
    v_category := COALESCE(NEW.category, 'Other');
    IF v_category IN ('Salaries', 'Salary', 'Salary Advance') THEN
        v_category := 'Salary';
    ELSIF v_category NOT IN ('Membership', 'Salary', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other') THEN
        v_category := 'Other';
    END IF;

    -- Map payment mode to payment method
    BEGIN
        v_payment_method := COALESCE(NEW.payment_mode::TEXT, 'Cash');
        IF v_payment_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
            v_payment_method := 'Other';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_payment_method := 'Cash';
    END;

    -- Calculate expense_date and revenue_date
    v_expense_date := NEW.date;
    
    -- If category is Salary and reference_id is not null
    IF v_category = 'Salary' AND NEW.reference_id IS NOT NULL THEN
        -- Try to fetch salary month from salary drafts
        SELECT salary_month INTO v_draft_month
        FROM public.salary_drafts
        WHERE id = NEW.reference_id;

        IF v_draft_month IS NOT NULL THEN
            v_expense_date := to_date(v_draft_month, 'Month YYYY');
        END IF;
    END IF;

    -- If category is Salary and is an Advance (reference_id is linked to salary_advance_ledger)
    IF v_expense_date = NEW.date AND v_category = 'Salary' AND NEW.reference_id IS NOT NULL THEN
        SELECT given_date INTO v_expense_date
        FROM public.salary_advance_ledger
        WHERE id = NEW.reference_id;
        
        -- Fallback to date if not found
        IF v_expense_date IS NULL THEN
            v_expense_date := NEW.date;
        END IF;
    END IF;

    IF NEW.type = 'Revenue' THEN
        v_revenue_date := NEW.date;
    ELSE
        v_revenue_date := NULL;
    END IF;

    v_notes := COALESCE(NEW.title, '');

    INSERT INTO public.finance_transactions (
        gym_id,
        amount,
        type,
        category,
        payment_method,
        transaction_date,
        expense_date,
        revenue_date,
        entry_date,
        reference_id,
        created_by,
        notes
    )
    VALUES (
        NEW.gym_id,
        NEW.amount,
        NEW.type,
        v_category,
        v_payment_method,
        NEW.date::TIMESTAMPTZ, -- transaction_date (payment date shown in list)
        v_expense_date,        -- expense_date (accrual month for expense summation)
        v_revenue_date,        -- revenue_date (accrual month for revenue summation)
        NEW.date,
        NEW.id::TEXT,
        NEW.user_id,
        v_notes
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Drop and recreate the trigger on public.transactions
DROP TRIGGER IF EXISTS trg_sync_transactions_to_finance ON public.transactions;
CREATE TRIGGER trg_sync_transactions_to_finance
AFTER INSERT OR UPDATE ON public.transactions
FOR EACH ROW EXECUTE FUNCTION public.fn_sync_transactions_to_finance();

-- 3. Update get_finance_summary to calculate revenues and expenses using accrual dates (expense_date / revenue_date)
CREATE OR REPLACE FUNCTION public.get_finance_summary(p_gym_id UUID, p_target_date DATE)
RETURNS TABLE (
    total_revenue NUMERIC,
    total_expense NUMERIC,
    net_profit NUMERIC,
    monthly_revenue_data NUMERIC[]
) AS $$
DECLARE
    v_month_start DATE := date_trunc('month', p_target_date);
    v_month_end DATE := (date_trunc('month', p_target_date) + interval '1 month' - interval '1 day')::DATE;
    v_revenue_list NUMERIC[] := ARRAY[]::NUMERIC[];
    v_day INT;
    v_day_rev NUMERIC;
BEGIN
    -- Monthly Revenue (sum based on revenue_date, falling back to transaction_date)
    SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO total_revenue
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id
      AND type = 'Revenue'
      AND COALESCE(revenue_date, transaction_date::DATE) BETWEEN v_month_start AND v_month_end;

    -- Monthly Expense (sum based on expense_date, falling back to transaction_date)
    SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO total_expense
    FROM public.finance_transactions
    WHERE gym_id = p_gym_id
      AND type = 'Expense'
      AND COALESCE(expense_date, transaction_date::DATE) BETWEEN v_month_start AND v_month_end;

    -- Net Profit
    net_profit := total_revenue - total_expense;

    -- Calculate 6 data points for the sparkline chart dynamically (5-day intervals)
    FOR v_day IN 0..5 LOOP
        SELECT COALESCE(SUM(amount), 0.0)::NUMERIC INTO v_day_rev
        FROM public.finance_transactions
        WHERE gym_id = p_gym_id
          AND type = 'Revenue'
          AND COALESCE(revenue_date, transaction_date::DATE) >= (v_month_start + (v_day * 5) * interval '1 day')::DATE
          AND COALESCE(revenue_date, transaction_date::DATE) < (v_month_start + ((v_day + 1) * 5) * interval '1 day')::DATE;
        v_revenue_list := array_append(v_revenue_list, v_day_rev);
    END LOOP;

    monthly_revenue_data := v_revenue_list;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Sync existing historical transactions
DO $$
DECLARE
    r_tx RECORD;
    v_payment_method TEXT;
    v_category TEXT;
    v_expense_date DATE;
    v_revenue_date DATE;
    v_draft_month TEXT;
BEGIN
    FOR r_tx IN SELECT * FROM public.transactions
    LOOP
        -- Check if it already exists
        IF NOT EXISTS (SELECT 1 FROM public.finance_transactions WHERE reference_id = r_tx.id::TEXT) THEN
            
            -- Map category
            v_category := COALESCE(r_tx.category, 'Other');
            IF v_category IN ('Salaries', 'Salary', 'Salary Advance') THEN
                v_category := 'Salary';
            ELSIF v_category NOT IN ('Membership', 'Salary', 'Rent', 'Utilities', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other') THEN
                v_category := 'Other';
            END IF;

            -- Map payment method
            BEGIN
                v_payment_method := COALESCE(r_tx.payment_mode::TEXT, 'Cash');
                IF v_payment_method NOT IN ('Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other') THEN
                    v_payment_method := 'Other';
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_payment_method := 'Cash';
            END;

            -- Calculate expense_date and revenue_date
            v_expense_date := r_tx.date;
            IF v_category = 'Salary' AND r_tx.reference_id IS NOT NULL THEN
                SELECT salary_month INTO v_draft_month
                FROM public.salary_drafts
                WHERE id = r_tx.reference_id;

                IF v_draft_month IS NOT NULL THEN
                    v_expense_date := to_date(v_draft_month, 'Month YYYY');
                ELSE
                    -- Check if it is an advance ledger record instead
                    SELECT given_date INTO v_expense_date
                    FROM public.salary_advance_ledger
                    WHERE id = r_tx.reference_id;
                    
                    IF v_expense_date IS NULL THEN
                        v_expense_date := r_tx.date;
                    END IF;
                END IF;
            END IF;

            IF r_tx.type = 'Revenue' THEN
                v_revenue_date := r_tx.date;
            ELSE
                v_revenue_date := NULL;
            END IF;

            INSERT INTO public.finance_transactions (
                gym_id,
                amount,
                type,
                category,
                payment_method,
                transaction_date,
                expense_date,
                revenue_date,
                entry_date,
                reference_id,
                created_by,
                notes
            )
            VALUES (
                r_tx.gym_id,
                r_tx.amount,
                r_tx.type,
                v_category,
                v_payment_method,
                r_tx.date::TIMESTAMPTZ,
                v_expense_date,
                v_revenue_date,
                r_tx.date,
                r_tx.id::TEXT,
                r_tx.user_id,
                r_tx.title
            );
        END IF;
    END LOOP;
END
$$;



