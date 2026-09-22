-- ============================================================================
-- GYMOS PRIVACY & GDPR ACCOUNT DELETION ENHANCEMENT
-- Ensures complete PII erasure and anonymization while maintaining
-- historical financial and aggregate attendance integrity.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_user_account(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
BEGIN
  -- 1. Authorization check: caller must be deleting their own account OR be super admin
  IF NOT (auth.uid() = p_user_id OR is_super_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: Cannot delete another user account';
  END IF;

  -- 2. Anonymize historical attendance logs (GDPR Right to be Forgotten)
  -- Replaces member/staff names and identifiers with anonymized placeholders
  -- so gym attendance aggregations remain intact without retaining any personal data.
  UPDATE public.attendance_logs 
  SET name = '[Deleted User]', 
      user_id = NULL, 
      member_id = NULL, 
      staff_id = NULL,
      device_info = '[REDACTED]'
  WHERE user_id = p_user_id 
     OR member_id IN (SELECT id FROM public.members WHERE user_id = p_user_id)
     OR staff_id IN (SELECT id FROM public.staff WHERE user_id = p_user_id);

  -- 3. Anonymize financial transaction reference labels and notes
  UPDATE public.finance_transactions
  SET notes = 'Former Member / User Account Deleted'
  WHERE reference_id IN (SELECT id::text FROM public.members WHERE user_id = p_user_id)
     OR reference_id = p_user_id::text;

  -- 4. Delete private fitness, workout, measurements, and health logs
  DELETE FROM public.member_body_logs WHERE member_id IN (SELECT id::text FROM public.members WHERE user_id = p_user_id);
  DELETE FROM public.member_workout_sets WHERE member_id IN (SELECT id::text FROM public.members WHERE user_id = p_user_id);
  DELETE FROM public.member_personal_records WHERE member_id IN (SELECT id::text FROM public.members WHERE user_id = p_user_id);
  DELETE FROM public.member_weekly_schedule WHERE member_id IN (SELECT id::text FROM public.members WHERE user_id = p_user_id);
  DELETE FROM public.member_fitness_goals WHERE member_id IN (SELECT id::text FROM public.members WHERE user_id = p_user_id);
  DELETE FROM public.member_daily_logs WHERE member_id IN (SELECT id::text FROM public.members WHERE user_id = p_user_id);
  DELETE FROM public.member_memberships WHERE member_id IN (SELECT id::text FROM public.members WHERE user_id = p_user_id);

  -- 5. Delete member profile row
  DELETE FROM public.members WHERE user_id = p_user_id;

  -- 6. Delete staff profile row
  DELETE FROM public.staff WHERE user_id = p_user_id;

  -- 7. Delete gym associations, user profile, and preferences
  DELETE FROM public.user_gym_associations WHERE user_id = p_user_id;
  DELETE FROM public.user_profiles WHERE id = p_user_id;
  DELETE FROM public.user_settings WHERE user_id = p_user_id;

  -- 8. Delete authentication credentials from auth.users
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Error in delete_user_account: %', SQLERRM;
  RETURN false;
END;
$function$;

-- Revoke public execution and grant only to authenticated users and service_role
REVOKE EXECUTE ON FUNCTION public.delete_user_account(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account(uuid) TO authenticated, service_role;
