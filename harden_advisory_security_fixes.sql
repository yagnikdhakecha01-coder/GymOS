-- Pre-deployment Database Hardening Script: Fix Security Advisor Warnings
-- 1. Fix mutable search_path on 6 admin functions (prevents search-path hijacking attacks)
-- 2. Revoke execute privileges from anon and public roles on all 6 SECURITY DEFINER admin functions

-- 1. admin_auto_repair_anomaly
ALTER FUNCTION public.admin_auto_repair_anomaly(uuid, text, uuid) 
  SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.admin_auto_repair_anomaly(uuid, text, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_auto_repair_anomaly(uuid, text, uuid) TO authenticated, service_role;

-- 2. admin_delete_attendance
ALTER FUNCTION public.admin_delete_attendance(uuid) 
  SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.admin_delete_attendance(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_attendance(uuid) TO authenticated, service_role;

-- 3. admin_diagnose_gym_health
ALTER FUNCTION public.admin_diagnose_gym_health(uuid) 
  SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.admin_diagnose_gym_health(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_diagnose_gym_health(uuid) TO authenticated, service_role;

-- 4. admin_update_member_gamification
ALTER FUNCTION public.admin_update_member_gamification(uuid, integer, integer, text[]) 
  SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.admin_update_member_gamification(uuid, integer, integer, text[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_member_gamification(uuid, integer, integer, text[]) TO authenticated, service_role;

-- 5. admin_update_member_membership_and_finance
ALTER FUNCTION public.admin_update_member_membership_and_finance(uuid, text, date, date, numeric, numeric, numeric, numeric, text) 
  SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.admin_update_member_membership_and_finance(uuid, text, date, date, numeric, numeric, numeric, numeric, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_member_membership_and_finance(uuid, text, date, date, numeric, numeric, numeric, numeric, text) TO authenticated, service_role;

-- 6. admin_upsert_attendance
ALTER FUNCTION public.admin_upsert_attendance(uuid, text, uuid, date, text, timestamp with time zone, timestamp with time zone, uuid) 
  SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.admin_upsert_attendance(uuid, text, uuid, date, text, timestamp with time zone, timestamp with time zone, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_upsert_attendance(uuid, text, uuid, date, text, timestamp with time zone, timestamp with time zone, uuid) TO authenticated, service_role;
