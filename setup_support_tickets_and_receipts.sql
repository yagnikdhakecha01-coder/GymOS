-- =========================================================================
-- DATABASE MIGRATION: setup_support_tickets_and_receipts.sql
-- Run this script in your Supabase SQL Editor to support receptionists/staff
-- in Help & Support tickets and implement admin read receipt states.
-- =========================================================================

-- 1. Add is_read column to support_messages if it doesn't exist
ALTER TABLE public.support_messages ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT false;

-- 2. Drop the sender_role check constraint and recreate it to include 'staff'
ALTER TABLE public.support_messages DROP CONSTRAINT IF EXISTS support_messages_sender_role_check;
ALTER TABLE public.support_messages ADD CONSTRAINT support_messages_sender_role_check 
    CHECK (sender_role IN ('owner', 'staff', 'admin'));

-- 3. Update RLS policies on support_tickets to allow both owner and staff to read/insert
DROP POLICY IF EXISTS "Allow users to read their own support tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "Allow gym staff/owner to read support tickets" ON public.support_tickets;
CREATE POLICY "Allow gym staff/owner to read support tickets"
ON public.support_tickets
FOR SELECT
USING (
    auth.uid() = owner_id 
    OR EXISTS (
        SELECT 1 FROM public.user_gym_associations 
        WHERE user_gym_associations.gym_id = support_tickets.gym_id 
          AND user_gym_associations.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Allow authenticated users to insert support tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "Allow gym staff/owner to insert support tickets" ON public.support_tickets;
CREATE POLICY "Allow gym staff/owner to insert support tickets"
ON public.support_tickets
FOR INSERT
WITH CHECK (
    auth.uid() = owner_id 
    AND EXISTS (
        SELECT 1 FROM public.user_gym_associations 
        WHERE user_gym_associations.gym_id = support_tickets.gym_id 
          AND user_gym_associations.user_id = auth.uid()
    )
);

-- 4. Update RLS policies on support_messages to allow both owner and staff
DROP POLICY IF EXISTS "Allow users to read messages for their own tickets" ON public.support_messages;
DROP POLICY IF EXISTS "Allow gym staff/owner to read messages" ON public.support_messages;
CREATE POLICY "Allow gym staff/owner to read messages"
ON public.support_messages
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.support_tickets T
        JOIN public.user_gym_associations A ON T.gym_id = A.gym_id
        WHERE T.id = ticket_id AND A.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Allow users to insert messages for their own tickets" ON public.support_messages;
DROP POLICY IF EXISTS "Allow gym staff/owner to insert messages" ON public.support_messages;
CREATE POLICY "Allow gym staff/owner to insert messages"
ON public.support_messages
FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.support_tickets T
        JOIN public.user_gym_associations A ON T.gym_id = A.gym_id
        WHERE T.id = ticket_id AND A.user_id = auth.uid() AND T.status != 'Closed'
    )
);
