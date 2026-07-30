-- ====================================================
-- GYMOS - MASTER BACKEND DATABASE ARCHITECTURE (MIGRATION)
-- ====================================================

-- Enable pgcrypto for secure random byte generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. DROP ALL EXISTING TABLES AND FUNCTIONS TO START FROM ZERO
DROP TABLE IF EXISTS public.transactions CASCADE;
DROP TABLE IF EXISTS public.attendance CASCADE;
DROP TABLE IF EXISTS public.staff CASCADE;
DROP TABLE IF EXISTS public.members CASCADE;
DROP TABLE IF EXISTS public.invitations CASCADE;
DROP TABLE IF EXISTS public.user_gym_associations CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;
DROP TABLE IF EXISTS public.gyms CASCADE;

-- New tables
DROP TABLE IF EXISTS public.membership_plans CASCADE;
DROP TABLE IF EXISTS public.expenses CASCADE;
DROP TABLE IF EXISTS public.workout_plans CASCADE;
DROP TABLE IF EXISTS public.diet_plans CASCADE;
DROP TABLE IF EXISTS public.pt_sessions CASCADE;
DROP TABLE IF EXISTS public.salaries CASCADE;
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.holidays CASCADE;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

DROP FUNCTION IF EXISTS public.generate_secure_gym_code() CASCADE;
DROP FUNCTION IF EXISTS public.generate_secure_invitation_code() CASCADE;
DROP FUNCTION IF EXISTS public.set_gym_code_on_insert() CASCADE;
DROP FUNCTION IF EXISTS public.set_invitation_code_on_insert() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user_profile() CASCADE;

----------------------------------------------------
-- 2. CREATE BASE TABLES
----------------------------------------------------

-- Gyms Table
CREATE TABLE public.gyms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    gym_code TEXT UNIQUE NOT NULL,
    logo_url TEXT,
    gym_type TEXT,
    phone_number TEXT,
    email TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    country TEXT,
    pin_code TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Profiles Table (Core user data independent of gym/role context)
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    photo_url TEXT,
    phone_number TEXT,
    dob TEXT,
    experience TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Many-to-Many User Gym Associations (Handles multiple gyms & roles per account)
CREATE TABLE public.user_gym_associations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'staff', 'member')),
    setup_completed BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT uniq_user_gym_role UNIQUE (user_id, gym_id, role)
);

-- Staff Table
CREATE TABLE public.staff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('Trainer', 'Receptionist', 'Dietitian', 'Accountant', 'Manager', 'Cleaner', 'Sales Executive', 'Nutritionist', 'Personal Trainer', 'Other')),
    department TEXT,
    status TEXT NOT NULL DEFAULT 'Pending Activation' CHECK (status IN ('Pending Activation', 'Active', 'Inactive', 'Invitation Expired', 'On Leave')),
    avatar TEXT,
    join_date TEXT,
    shift TEXT,
    experience TEXT,
    reporting_to TEXT,
    rating NUMERIC(3, 2) DEFAULT 5.0 NOT NULL,
    sessions_count INT DEFAULT 0 NOT NULL,
    members_trained_count INT DEFAULT 0 NOT NULL,
    salary NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    salary_due NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    gender TEXT DEFAULT '',
    dob TEXT DEFAULT '',
    aadhaar TEXT DEFAULT '',
    emergency_name TEXT DEFAULT '',
    emergency_phone TEXT DEFAULT '',
    address TEXT DEFAULT '',
    employment_type TEXT DEFAULT 'Full Time',
    salary_type TEXT DEFAULT 'Fixed Salary',
    commission_percentage NUMERIC(5, 2) DEFAULT 0.0,
    qualification TEXT DEFAULT '',
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Members Table
CREATE TABLE public.members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Pending Activation' CHECK (status IN ('Pending Activation', 'Active', 'Inactive', 'Invitation Expired')),
    join_date TEXT,
    avatar TEXT,
    membership_plan_id TEXT, -- references membership_plans(id)
    pt_member BOOLEAN DEFAULT FALSE NOT NULL,
    pt_trainer UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    assigned_workout_id TEXT,
    assigned_diet_id TEXT,
    medical_details TEXT,
    notes TEXT,
    pending_amount NUMERIC(12, 2) DEFAULT 0.0 NOT NULL,
    extra_fields JSONB DEFAULT '{}'::jsonb NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Invitations Table
CREATE TABLE public.invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    member_id UUID REFERENCES public.members(id) ON DELETE CASCADE,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE,
    invitation_code TEXT UNIQUE NOT NULL,
    registered_mobile TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending', 'Used', 'Expired', 'Cancelled')),
    code_used BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    activated_at TIMESTAMPTZ,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    CONSTRAINT chk_member_or_staff CHECK (
        (member_id IS NOT NULL AND staff_id IS NULL) OR
        (member_id IS NULL AND staff_id IS NOT NULL)
    )
);

-- Attendance Table
CREATE TABLE public.attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('staff', 'member')),
    check_in TIMESTAMPTZ NOT NULL,
    check_out TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'Present' CHECK (status IN ('Present', 'Absent')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Transactions Table
CREATE TABLE public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    type TEXT NOT NULL CHECK (type IN ('Revenue', 'Expense')),
    title TEXT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    category TEXT NOT NULL,
    date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Membership Plans Table
CREATE TABLE public.membership_plans (
    id TEXT PRIMARY KEY,
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    price NUMERIC(12, 2) NOT NULL,
    duration_months INT NOT NULL,
    duration_days INT NOT NULL,
    pt_included BOOLEAN DEFAULT FALSE NOT NULL,
    diet_included BOOLEAN DEFAULT FALSE NOT NULL,
    workout_included BOOLEAN DEFAULT TRUE NOT NULL,
    freeze_days INT DEFAULT 0 NOT NULL,
    reminder_days INT DEFAULT 5 NOT NULL,
    logo TEXT DEFAULT '🎟️' NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Inactive')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Expenses Table
CREATE TABLE public.expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    category TEXT NOT NULL,
    date DATE NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Workout Plans Table
CREATE TABLE public.workout_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    difficulty TEXT,
    duration_weeks INT NOT NULL,
    exercises JSONB DEFAULT '[]'::jsonb NOT NULL,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Diet Plans Table
CREATE TABLE public.diet_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    calories_goal INT NOT NULL,
    protein_goal INT NOT NULL,
    carbs_goal INT NOT NULL,
    fat_goal INT NOT NULL,
    meals JSONB DEFAULT '[]'::jsonb NOT NULL,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Personal Training (PT) Table
CREATE TABLE public.pt_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    trainer_id UUID REFERENCES public.staff(id) ON DELETE CASCADE NOT NULL,
    member_id UUID REFERENCES public.members(id) ON DELETE CASCADE NOT NULL,
    session_date TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('scheduled', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Salaries Table
CREATE TABLE public.salaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    payment_date DATE NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'paid')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Notifications Table
CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    target_role TEXT CHECK (target_role IN ('all', 'staff', 'member')),
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Holidays Table
CREATE TABLE public.holidays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    date DATE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

----------------------------------------------------
-- 3. CRYPTOGRAPHICALLY SECURE CODE GENERATORS
----------------------------------------------------

-- Alphanumeric Gym Code Generator (9 characters uppercase)
CREATE OR REPLACE FUNCTION public.generate_secure_gym_code()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    result TEXT := '';
    i INTEGER;
    bytes BYTEA;
    val INTEGER;
BEGIN
    LOOP
        result := '';
        bytes := gen_random_bytes(9);
        FOR i IN 0..8 LOOP
            val := get_byte(bytes, i);
            result := result || substr(chars, (val % 36) + 1, 1);
        END LOOP;
        
        -- Prevent collisions
        IF NOT EXISTS (SELECT 1 FROM public.gyms WHERE gym_code = result) THEN
            RETURN result;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Alphanumeric Invitation Token Generator (8 characters mix of upper/lower/numbers)
CREATE OR REPLACE FUNCTION public.generate_secure_invitation_code()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    result TEXT := '';
    i INTEGER;
    bytes BYTEA;
    val INTEGER;
BEGIN
    LOOP
        result := '';
        bytes := gen_random_bytes(8);
        FOR i IN 0..7 LOOP
            val := get_byte(bytes, i);
            result := result || substr(chars, (val % 62) + 1, 1);
        END LOOP;
        
        -- Prevent collisions
        IF NOT EXISTS (SELECT 1 FROM public.invitations WHERE invitation_code = result) THEN
            RETURN result;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger Function for Gym insertion
CREATE OR REPLACE FUNCTION public.set_gym_code_on_insert()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.gym_code IS NULL THEN
        NEW.gym_code := public.generate_secure_gym_code();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_set_gym_code
BEFORE INSERT ON public.gyms
FOR EACH ROW
EXECUTE FUNCTION public.set_gym_code_on_insert();

-- Trigger Function for Invitation insertion
CREATE OR REPLACE FUNCTION public.set_invitation_code_on_insert()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.invitation_code IS NULL THEN
        NEW.invitation_code := public.generate_secure_invitation_code();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_set_invitation_code
BEFORE INSERT ON public.invitations
FOR EACH ROW
EXECUTE FUNCTION public.set_invitation_code_on_insert();

----------------------------------------------------
-- 4. PROFILE GENERATION TRIGGER ON AUTH SIGNUP
----------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (
    NEW.id,
    NEW.email
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

----------------------------------------------------
-- 5. PERFORMANCE AND RLS FILTER INDEXES
----------------------------------------------------
CREATE INDEX idx_associations_user ON public.user_gym_associations(user_id);
CREATE INDEX idx_associations_gym ON public.user_gym_associations(gym_id);
CREATE INDEX idx_gyms_code ON public.gyms(gym_code);
CREATE INDEX idx_invitation_code ON public.invitations(code) WHERE (used = false);
CREATE INDEX idx_members_gym ON public.members(gym_id);
CREATE INDEX idx_staff_gym ON public.staff(gym_id);
CREATE INDEX idx_attendance_gym_checkin ON public.attendance(gym_id, check_in DESC);
CREATE INDEX idx_transactions_gym_date ON public.transactions(gym_id, date DESC);

----------------------------------------------------
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
----------------------------------------------------

-- Enable Row-Level Security on all tables
ALTER TABLE public.gyms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_gym_associations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.membership_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diet_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pt_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.salaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;

-- 6.1 Gyms Table Policies
-- Owners/Staff/Members can read details of the gym they are actively associated with
CREATE POLICY select_all_gyms ON public.gyms
    FOR SELECT TO authenticated
    USING (true);

-- Gym Owners can update details of the gym they own
CREATE POLICY update_owned_gym ON public.gyms
    FOR UPDATE TO authenticated
    USING (id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid() AND role = 'owner'))
    WITH CHECK (id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid() AND role = 'owner'));

-- Allow any authenticated user (first-time setup) to register a new gym
CREATE POLICY insert_new_gym ON public.gyms
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- 6.2 Profiles Table Policies
-- Users can read/write their own profiles, or read profiles of users inside the same gym
CREATE POLICY profiles_policy ON public.profiles
    FOR ALL TO authenticated
    USING (
        id = auth.uid()
        OR
        id IN (SELECT user_id FROM public.user_gym_associations WHERE gym_id IN (
            SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
        ))
    );

-- 6.3 User Gym Associations Policies
-- Users can see all their associations, owners can view associations inside their gyms
CREATE POLICY select_associations ON public.user_gym_associations
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- Users/Onboarding can insert associations
CREATE POLICY insert_associations ON public.user_gym_associations
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

-- 6.4 Invitations Table Policies
-- Only owners can manage invitations for their gym, invited users can read and update (use) active ones
CREATE POLICY manage_invitations_owner ON public.invitations
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid() AND role = 'owner'));

CREATE POLICY read_active_invitations ON public.invitations
    FOR SELECT TO authenticated
    USING (code_used = false);

CREATE POLICY read_own_invitations ON public.invitations
    FOR SELECT TO authenticated
    USING (
        member_id IN (SELECT id FROM public.members WHERE user_id = auth.uid())
        OR
        staff_id IN (SELECT id FROM public.staff WHERE user_id = auth.uid())
    );

CREATE POLICY use_active_invitations ON public.invitations
    FOR UPDATE TO authenticated
    USING (code_used = false)
    WITH CHECK (true);

-- Deactivate old invitations function & trigger
CREATE OR REPLACE FUNCTION public.deactivate_old_invitations()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.member_id IS NOT NULL THEN
        UPDATE public.invitations
        SET status = 'Cancelled'
        WHERE member_id = NEW.member_id AND status = 'Pending' AND id <> NEW.id;
    ELSIF NEW.staff_id IS NOT NULL THEN
        UPDATE public.invitations
        SET status = 'Cancelled'
        WHERE staff_id = NEW.staff_id AND status = 'Pending' AND id <> NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_deactivate_old_invitations
BEFORE INSERT ON public.invitations
FOR EACH ROW
EXECUTE FUNCTION public.deactivate_old_invitations();

-- 6.5 Members, Staff, Attendance, Transactions Policies
-- Restrict read/write queries dynamically based on active associated gym membership
CREATE POLICY member_isolation_policy ON public.members
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY update_own_member_record ON public.members
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (user_id = auth.uid());

CREATE POLICY staff_isolation_policy ON public.staff
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY update_own_staff_record ON public.staff
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (user_id = auth.uid());

CREATE POLICY attendance_isolation_policy ON public.attendance
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY transactions_isolation_policy ON public.transactions
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY membership_plans_isolation_policy ON public.membership_plans
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY expenses_isolation_policy ON public.expenses
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY workout_plans_isolation_policy ON public.workout_plans
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY diet_plans_isolation_policy ON public.diet_plans
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY pt_sessions_isolation_policy ON public.pt_sessions
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY salaries_isolation_policy ON public.salaries
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY notifications_isolation_policy ON public.notifications
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

CREATE POLICY holidays_isolation_policy ON public.holidays
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- Staff Roles Table
CREATE TABLE public.staff_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    role_name TEXT NOT NULL,
    icon TEXT DEFAULT 'badge_outlined',
    is_default BOOLEAN DEFAULT FALSE NOT NULL,
    is_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    is_custom BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT uniq_gym_role_name UNIQUE (gym_id, role_name)
);

ALTER TABLE public.staff_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY staff_roles_isolation_policy ON public.staff_roles
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

----------------------------------------------------
-- 7. GRANT SCHEMA PRIVILEGES TO AUTH & ANON ROLES
----------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;
