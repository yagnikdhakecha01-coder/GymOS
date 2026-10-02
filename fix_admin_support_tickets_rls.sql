-- =========================================================================
-- FIX: Allow Super Admin & Admins to View, Update & Reply to Support Tickets
-- =========================================================================

-- 1. Grant table privileges to authenticated and anon
GRANT ALL ON TABLE public.support_tickets TO authenticated, anon, service_role;
GRANT ALL ON TABLE public.support_messages TO authenticated, anon, service_role;

-- 2. Drop existing restrictive policies on support_tickets
DROP POLICY IF EXISTS "support_tickets_insert" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_read" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_update" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_delete" ON public.support_tickets;
DROP POLICY IF EXISTS "super_admin_all_support_tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "admin_all_support_tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "Permissive support_tickets policy" ON public.support_tickets;

-- 3. Super Admin / Admin Full Access for support_tickets
CREATE POLICY "admin_all_support_tickets"
ON public.support_tickets
FOR ALL
TO authenticated
USING (
    public.is_admin(auth.uid()) OR public.is_super_admin(auth.uid())
)
WITH CHECK (
    public.is_admin(auth.uid()) OR public.is_super_admin(auth.uid())
);

-- 4. User access for support_tickets
CREATE POLICY "user_select_support_tickets"
ON public.support_tickets
FOR SELECT
TO authenticated
USING (
    (owner_id = auth.uid()) OR
    (gym_id IN (SELECT fn_user_accessible_gym_ids(auth.uid()))) OR
    (gym_id IN (SELECT fn_user_gym_ids()))
);

CREATE POLICY "user_insert_support_tickets"
ON public.support_tickets
FOR INSERT
TO authenticated
WITH CHECK (
    (owner_id = auth.uid()) OR
    (gym_id IN (SELECT fn_user_accessible_gym_ids(auth.uid()))) OR
    (gym_id IN (SELECT fn_user_gym_ids()))
);

CREATE POLICY "user_update_support_tickets"
ON public.support_tickets
FOR UPDATE
TO authenticated
USING (
    (owner_id = auth.uid()) OR
    (gym_id IN (SELECT fn_user_accessible_gym_ids(auth.uid())))
)
WITH CHECK (
    (owner_id = auth.uid()) OR
    (gym_id IN (SELECT fn_user_accessible_gym_ids(auth.uid())))
);

-- 5. Drop existing policies on support_messages
DROP POLICY IF EXISTS "support_messages_gym_crud" ON public.support_messages;
DROP POLICY IF EXISTS "support_messages_insert" ON public.support_messages;
DROP POLICY IF EXISTS "support_messages_read" ON public.support_messages;
DROP POLICY IF EXISTS "admin_all_support_messages" ON public.support_messages;
DROP POLICY IF EXISTS "Permissive support_messages policy" ON public.support_messages;

-- 6. Super Admin / Admin Full Access for support_messages
CREATE POLICY "admin_all_support_messages"
ON public.support_messages
FOR ALL
TO authenticated
USING (
    public.is_admin(auth.uid()) OR public.is_super_admin(auth.uid())
)
WITH CHECK (
    public.is_admin(auth.uid()) OR public.is_super_admin(auth.uid())
);

-- 7. User access for support_messages
CREATE POLICY "user_select_support_messages"
ON public.support_messages
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.support_tickets t
        WHERE t.id = support_messages.ticket_id
          AND (
            t.owner_id = auth.uid() OR
            t.gym_id IN (SELECT fn_user_accessible_gym_ids(auth.uid())) OR
            t.gym_id IN (SELECT fn_user_gym_ids())
          )
    )
);

CREATE POLICY "user_insert_support_messages"
ON public.support_messages
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.support_tickets t
        WHERE t.id = support_messages.ticket_id
          AND (
            t.owner_id = auth.uid() OR
            t.gym_id IN (SELECT fn_user_accessible_gym_ids(auth.uid())) OR
            t.gym_id IN (SELECT fn_user_gym_ids())
          )
    )
);
