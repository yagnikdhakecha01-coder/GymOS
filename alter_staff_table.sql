-- Run this migration in your Supabase SQL Editor to add the new staff fields and create the staff roles table.

-- 1. Drop existing role constraint from staff table to allow dynamic roles
ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_role_check;
ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_status_check;

-- 2. Add status check back with On Leave option
ALTER TABLE public.staff ADD CONSTRAINT staff_status_check 
  CHECK (status IN ('Pending Activation', 'Active', 'Inactive', 'Invitation Expired', 'On Leave'));

-- 3. Add new columns to staff table
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS gender TEXT DEFAULT '';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS dob TEXT DEFAULT '';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS aadhaar TEXT DEFAULT '';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS emergency_name TEXT DEFAULT '';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS emergency_phone TEXT DEFAULT '';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS address TEXT DEFAULT '';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS employment_type TEXT DEFAULT 'Full Time';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS salary_type TEXT DEFAULT 'Fixed Salary';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS commission_percentage NUMERIC(5, 2) DEFAULT 0.0;
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS qualification TEXT DEFAULT '';
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT '';

-- 4. Create Staff Roles table
CREATE TABLE IF NOT EXISTS public.staff_roles (
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

DROP POLICY IF EXISTS staff_roles_isolation_policy ON public.staff_roles;
CREATE POLICY staff_roles_isolation_policy ON public.staff_roles
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));
