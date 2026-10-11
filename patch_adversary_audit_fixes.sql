-- ==============================================================================
-- GYMOS V1 ADVERSARY SECURITY AUDIT REMEDIATION PATCH
-- Hardening: Privilege Escalation, Invitation Exposure, Storage RLS, Financial Bounds
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. FIX PRIVILEGE ESCALATION ON user_gym_associations
-- Problem: Policy insert_associations checked ONLY (user_id = auth.uid()),
-- allowing any user to insert { user_id: auth.uid(), gym_id: <any>, role: 'owner' }.
-- Solution: Require that the user is the recorded owner of the gym, or an active owner/admin.
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "insert_associations" ON public.user_gym_associations;
DROP POLICY IF EXISTS "insert_associations_hardened" ON public.user_gym_associations;

CREATE POLICY "insert_associations_hardened"
ON public.user_gym_associations
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND (
    -- User is the creator/recorded owner of the gym
    EXISTS (
      SELECT 1 FROM public.gyms g
      WHERE g.id = gym_id AND g.owner_id = auth.uid()
    )
    -- Or insertion is performed by existing gym owner
    OR EXISTS (
      SELECT 1 FROM public.user_gym_associations uga
      WHERE uga.gym_id = user_gym_associations.gym_id
        AND uga.user_id = auth.uid()
        AND uga.role = 'owner'
    )
    -- Or Super Admin
    OR is_super_admin(auth.uid())
  )
);

-- ------------------------------------------------------------------------------
-- 2. LOCK DOWN invitations TABLE & CREATE SECURE REDEEM RPC
-- Problem: read_active_invitations & use_active_invitations allowed any user
-- to dump all unredeemed codes and registered phone numbers across all gyms.
-- Solution: Revoke public access to raw invitations table; create atomic RPC.
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "read_active_invitations" ON public.invitations;
DROP POLICY IF EXISTS "use_active_invitations" ON public.invitations;

CREATE OR REPLACE FUNCTION public.redeem_gym_invitation(
  p_code TEXT,
  p_mobile TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_invite RECORD;
  v_gym_id UUID;
  v_role TEXT;
  v_full_name TEXT := '';
  v_is_already_linked BOOLEAN := FALSE;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required.');
  END IF;

  -- 1. Exact match (case-insensitive)
  SELECT * INTO v_invite
  FROM public.invitations
  WHERE LOWER(TRIM(invitation_code)) = LOWER(TRIM(p_code))
  FOR UPDATE;

  -- 1b. Fuzzy match fallback for visually similar characters (0 vs O, 1 vs I/l)
  IF NOT FOUND THEN
    SELECT * INTO v_invite
    FROM public.invitations
    WHERE REPLACE(REPLACE(REPLACE(LOWER(TRIM(invitation_code)), 'o', '0'), 'l', '1'), 'i', '1') = 
          REPLACE(REPLACE(REPLACE(LOWER(TRIM(p_code)), 'o', '0'), 'l', '1'), 'i', '1')
    FOR UPDATE;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid invitation code.');
  END IF;

  IF v_invite.expires_at IS NOT NULL AND now() > v_invite.expires_at THEN
    UPDATE public.invitations SET status = 'Expired' WHERE id = v_invite.id;
    RETURN jsonb_build_object('success', false, 'error', 'This invitation code has expired.');
  END IF;

  -- 2. Verify mobile number
  IF TRIM(v_invite.registered_mobile) <> TRIM(p_mobile) AND RIGHT(TRIM(v_invite.registered_mobile), 10) <> RIGHT(TRIM(p_mobile), 10) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Wrong Mobile Number.');
  END IF;

  v_gym_id := v_invite.gym_id;
  v_role := CASE WHEN v_invite.member_id IS NOT NULL THEN 'member' ELSE 'staff' END;

  -- Fetch name
  IF v_invite.member_id IS NOT NULL THEN
    SELECT name INTO v_full_name FROM public.members WHERE id = v_invite.member_id;
  ELSIF v_invite.staff_id IS NOT NULL THEN
    SELECT name INTO v_full_name FROM public.staff WHERE id = v_invite.staff_id;
  END IF;

  -- Check if this member or staff record is ALREADY linked to this caller
  IF v_invite.member_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.members WHERE id = v_invite.member_id AND user_id = v_caller_id) THEN
      v_is_already_linked := TRUE;
    END IF;
  ELSIF v_invite.staff_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.staff WHERE id = v_invite.staff_id AND user_id = v_caller_id) THEN
      v_is_already_linked := TRUE;
    END IF;
  END IF;

  -- Only reject as inactive if this invitation was used by someone else or cancelled, and NOT linked to current caller
  IF NOT v_is_already_linked THEN
    IF v_invite.code_used = TRUE OR v_invite.status NOT IN ('Pending', 'Active') THEN
      RETURN jsonb_build_object('success', false, 'error', 'This invitation code is no longer active.');
    END IF;
  END IF;

  -- 3. Ensure caller has a profile record (satisfies foreign key)
  INSERT INTO public.profiles (id, email, full_name, name)
  SELECT 
    v_caller_id,
    COALESCE(u.email, ''),
    COALESCE(v_full_name, u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
    COALESCE(v_full_name, u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1))
  FROM auth.users u WHERE u.id = v_caller_id
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name);

  -- 4. Upsert association if not already existing
  IF NOT EXISTS (
    SELECT 1 FROM public.user_gym_associations
    WHERE user_id = v_caller_id AND gym_id = v_gym_id AND role = v_role
  ) THEN
    INSERT INTO public.user_gym_associations (user_id, gym_id, role, setup_completed)
    VALUES (v_caller_id, v_gym_id, v_role, TRUE)
    ON CONFLICT (user_id, gym_id, role) DO UPDATE SET setup_completed = TRUE;
  END IF;

  -- 5. Link member or staff record
  IF v_invite.member_id IS NOT NULL THEN
    UPDATE public.members
    SET user_id = v_caller_id, 
        status = 'Active',
        email = COALESCE(NULLIF(members.email, ''), (SELECT email FROM auth.users WHERE id = v_caller_id))
    WHERE id = v_invite.member_id;
  ELSIF v_invite.staff_id IS NOT NULL THEN
    UPDATE public.staff
    SET user_id = v_caller_id, status = 'Active'
    WHERE id = v_invite.staff_id;
  END IF;

  -- 6. Mark invitation as used
  UPDATE public.invitations
  SET code_used = TRUE,
      status = 'Used',
      activated_at = COALESCE(activated_at, now())
  WHERE id = v_invite.id;

  RETURN jsonb_build_object(
    'success', true,
    'gym_id', v_gym_id,
    'role', v_role,
    'full_name', v_full_name
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.redeem_gym_invitation(TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.redeem_gym_invitation(TEXT, TEXT) TO authenticated;

-- ------------------------------------------------------------------------------
-- 3. HARDEN STORAGE POLICIES
-- Problem: Unauthenticated 'anon' could upload and overwrite avatar files.
-- Solution: Require 'authenticated' role for insertions and updates.
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Allow anon insert to avatars" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon update to avatars" ON storage.objects;
DROP POLICY IF EXISTS "Allow auth users to insert in support_attachments" ON storage.objects;
DROP POLICY IF EXISTS "authenticated_insert_avatars" ON storage.objects;
DROP POLICY IF EXISTS "authenticated_update_avatars" ON storage.objects;
DROP POLICY IF EXISTS "authenticated_insert_support_attachments" ON storage.objects;

CREATE POLICY "authenticated_insert_avatars"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "authenticated_update_avatars"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'avatars')
WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "authenticated_insert_support_attachments"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'support_attachments');

-- ------------------------------------------------------------------------------
-- 4. FINANCIAL TABLES: NON-NEGATIVE INTEGRITY CONSTRAINTS
-- Prevent negative balance injection, negative prices, and negative fees.
-- ------------------------------------------------------------------------------
DO $$
BEGIN
  -- 1. payments table
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'payments_amount_non_negative'
  ) THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_amount_non_negative CHECK (amount >= 0);
  END IF;

  -- 2. transactions table
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'transactions_amount_non_negative'
  ) THEN
    ALTER TABLE public.transactions ADD CONSTRAINT transactions_amount_non_negative CHECK (amount >= 0);
  END IF;

  -- 3. expenses table
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expenses_amount_non_negative'
  ) THEN
    ALTER TABLE public.expenses ADD CONSTRAINT expenses_amount_non_negative CHECK (amount >= 0);
  END IF;

  -- 4. membership_payments table
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'membership_payments_amount_non_negative'
  ) THEN
    ALTER TABLE public.membership_payments ADD CONSTRAINT membership_payments_amount_non_negative CHECK (amount >= 0);
  END IF;

  -- 5. invoices table
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'invoices_amount_non_negative'
  ) THEN
    ALTER TABLE public.invoices ADD CONSTRAINT invoices_amount_non_negative CHECK (amount >= 0);
  END IF;

  -- 6. members table non-negative amounts
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'members_amounts_non_negative'
  ) THEN
    ALTER TABLE public.members ADD CONSTRAINT members_amounts_non_negative
      CHECK (COALESCE(pending_amount, 0) >= 0 AND COALESCE(discount_amount, 0) >= 0 AND COALESCE(total_received_amount, 0) >= 0);
  END IF;
END $$;
