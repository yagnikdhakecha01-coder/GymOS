-- =========================================================================
-- FIX UNLINK ACCOUNT: fix_unlink_account.sql
-- Supabase SQL Editor mein paste karke Run karo
--
-- Fixes:
-- 1. Owner unlink kare to association + staff/member link dono delete hon
-- 2. RLS policy for delete on user_gym_associations
-- 3. Atomic RPC so partial unlink (user_id cleared but association remains) na ho
-- =========================================================================

-- 1. RLS: Owner can delete staff/member associations
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

-- 2. Helper: check admin (skip if already exists)
CREATE OR REPLACE FUNCTION public.is_admin(u_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_users WHERE user_id = u_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Atomic unlink RPC — owner calls this, guaranteed full unlink
CREATE OR REPLACE FUNCTION public.unlink_gym_account(
    p_record_id UUID,
    p_is_staff BOOLEAN DEFAULT TRUE
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_gym_id UUID;
    v_user_id UUID;
    v_role TEXT;
BEGIN
    IF p_is_staff THEN
        SELECT gym_id, user_id INTO v_gym_id, v_user_id
        FROM public.staff
        WHERE id = p_record_id;

        IF v_gym_id IS NULL THEN
            RAISE EXCEPTION 'Staff record not found';
        END IF;

        v_role := 'staff';
    ELSE
        SELECT gym_id, user_id INTO v_gym_id, v_user_id
        FROM public.members
        WHERE id = p_record_id;

        IF v_gym_id IS NULL THEN
            RAISE EXCEPTION 'Member record not found';
        END IF;

        v_role := 'member';
    END IF;

    -- Only gym owner or super admin can unlink
    IF NOT public.is_admin(auth.uid()) AND NOT EXISTS (
        SELECT 1 FROM public.user_gym_associations
        WHERE user_id = auth.uid() AND gym_id = v_gym_id AND role = 'owner'
    ) THEN
        RAISE EXCEPTION 'Not authorized to unlink this account';
    END IF;

    -- Remove gym association first
    IF v_user_id IS NOT NULL THEN
        DELETE FROM public.user_gym_associations
        WHERE user_id = v_user_id
          AND gym_id = v_gym_id
          AND role = v_role;
    END IF;

    -- Clear user link on staff/member record
    IF p_is_staff THEN
        UPDATE public.staff
        SET user_id = NULL,
            status = 'Pending Activation'
        WHERE id = p_record_id;
    ELSE
        UPDATE public.members
        SET user_id = NULL,
            status = 'Pending Activation'
        WHERE id = p_record_id;
    END IF;

    RETURN 'unlinked';
END;
$$;

GRANT EXECUTE ON FUNCTION public.unlink_gym_account(UUID, BOOLEAN) TO authenticated, service_role;

-- 4. Staff/member app can check if still linked (used by app polling)
CREATE OR REPLACE FUNCTION public.is_user_linked_to_gym(
    p_user_id UUID,
    p_gym_id UUID,
    p_role TEXT DEFAULT 'staff'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_linked BOOLEAN := FALSE;
    v_status TEXT;
BEGIN
    -- Must have association
    IF NOT EXISTS (
        SELECT 1 FROM public.user_gym_associations
        WHERE user_id = p_user_id AND gym_id = p_gym_id AND role = p_role
    ) THEN
        RETURN FALSE;
    END IF;

    IF p_role = 'staff' THEN
        SELECT status INTO v_status
        FROM public.staff
        WHERE user_id = p_user_id AND gym_id = p_gym_id
        LIMIT 1;

        v_linked := v_status IS NOT NULL AND v_status = 'Active';
    ELSE
        SELECT status INTO v_status
        FROM public.members
        WHERE user_id = p_user_id AND gym_id = p_gym_id
        LIMIT 1;

        v_linked := v_status IS NOT NULL AND v_status = 'Active';
    END IF;

    RETURN v_linked;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_user_linked_to_gym(UUID, UUID, TEXT) TO authenticated, service_role;

-- 5. CLEANUP: Fix already-unlinked accounts (association bachi ho lekin staff link nahi)
-- Pehle se unlink kiye gaye staff/members ke liye yeh chalao ek baar

DELETE FROM public.user_gym_associations uga
WHERE uga.role = 'staff'
  AND NOT EXISTS (
    SELECT 1 FROM public.staff s
    WHERE s.user_id = uga.user_id
      AND s.gym_id = uga.gym_id
      AND s.status = 'Active'
  );

DELETE FROM public.user_gym_associations uga
WHERE uga.role = 'member'
  AND NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.user_id = uga.user_id
      AND m.gym_id = uga.gym_id
      AND m.status = 'Active'
  );
