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
