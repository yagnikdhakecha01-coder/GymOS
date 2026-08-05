-- =========================================================================
-- DATABASE MIGRATION: setup_support_chat.sql
-- Run this script in your Supabase SQL Editor to set up support chat thread
-- =========================================================================

-- 1. Create support messages table
CREATE TABLE IF NOT EXISTS public.support_messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ticket_id UUID REFERENCES public.support_tickets(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    sender_role TEXT NOT NULL CHECK (sender_role IN ('owner', 'admin')),
    message TEXT,
    image_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

-- 2. Enable RLS on support messages
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- Allow users to read messages for their own tickets (if ticket is not Closed)
DROP POLICY IF EXISTS "Allow users to read messages for their own tickets" ON public.support_messages;
CREATE POLICY "Allow users to read messages for their own tickets"
ON public.support_messages FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.support_tickets 
        WHERE id = ticket_id AND owner_id = auth.uid() AND status != 'Closed'
    )
);

-- Allow users to insert messages for their own tickets (if ticket is not Closed)
DROP POLICY IF EXISTS "Allow users to insert messages for their own tickets" ON public.support_messages;
CREATE POLICY "Allow users to insert messages for their own tickets"
ON public.support_messages FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.support_tickets 
        WHERE id = ticket_id AND owner_id = auth.uid() AND status != 'Closed'
    )
);

-- Allow admin all access to support messages
DROP POLICY IF EXISTS "Allow admin all access to support messages" ON public.support_messages;
CREATE POLICY "Allow admin all access to support messages"
ON public.support_messages FOR ALL
USING (true)
WITH CHECK (true);

-- 3. Update support_tickets select policy: owners can read only open/active tickets
DROP POLICY IF EXISTS "Allow users to read their own support tickets" ON public.support_tickets;
CREATE POLICY "Allow users to read their own support tickets" 
ON public.support_tickets 
FOR SELECT 
USING (auth.uid() = owner_id AND status != 'Closed');

-- 4. Create support attachments bucket in Supabase storage
INSERT INTO storage.buckets (id, name, public) 
VALUES ('support_attachments', 'support_attachments', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies to allow public reads and authenticated uploads
DROP POLICY IF EXISTS "Allow public reads on support_attachments" ON storage.objects;
CREATE POLICY "Allow public reads on support_attachments"
ON storage.objects FOR SELECT USING (bucket_id = 'support_attachments');

DROP POLICY IF EXISTS "Allow auth users to insert in support_attachments" ON storage.objects;
CREATE POLICY "Allow auth users to insert in support_attachments"
ON storage.objects FOR INSERT WITH CHECK (
    bucket_id = 'support_attachments' AND auth.role() = 'authenticated'
);
