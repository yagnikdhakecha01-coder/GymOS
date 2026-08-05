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
