-- =========================================================================
-- COMPLETE FIX FOR SUPPORT TICKETS & CHAT PERMISSIONS (PostgrestException 42501)
-- Run this script in your Supabase SQL Editor.
-- =========================================================================

-- 1. Ensure support_tickets table exists with correct schema
CREATE TABLE IF NOT EXISTS public.support_tickets (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'medium',
    status TEXT NOT NULL DEFAULT 'Open',
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE,
    gym_name TEXT,
    owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Ensure support_messages table exists
CREATE TABLE IF NOT EXISTS public.support_messages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ticket_id UUID REFERENCES public.support_tickets(id) ON DELETE CASCADE NOT NULL,
    sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    sender_role TEXT NOT NULL DEFAULT 'owner',
    message TEXT,
    image_url TEXT,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. GRANT REQUIRED TABLE PRIVILEGES TO AUTHENTICATED AND ANON ROLES
-- This resolves PostgrestException 42501 permission denied!
GRANT ALL ON TABLE public.support_tickets TO authenticated, anon, service_role;
GRANT ALL ON TABLE public.support_messages TO authenticated, anon, service_role;

-- 4. Enable Row Level Security
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- 5. Drop old restrictive policies
DROP POLICY IF EXISTS "Allow users to read their own support tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "Allow gym staff/owner to read support tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "Allow authenticated users to insert support tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "Allow gym staff/owner to insert support tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "Allow all actions on support tickets" ON public.support_tickets;
DROP POLICY IF EXISTS "Permissive support_tickets policy" ON public.support_tickets;

DROP POLICY IF EXISTS "Allow users to read messages for their own tickets" ON public.support_messages;
DROP POLICY IF EXISTS "Allow users to insert messages for their own tickets" ON public.support_messages;
DROP POLICY IF EXISTS "Allow admin all access to support messages" ON public.support_messages;
DROP POLICY IF EXISTS "Permissive support_messages policy" ON public.support_messages;

-- 6. Create clean, permissive policies for support_tickets
CREATE POLICY "Permissive support_tickets policy" 
ON public.support_tickets 
FOR ALL 
TO public
USING (true) 
WITH CHECK (true);

-- 7. Create clean, permissive policies for support_messages
CREATE POLICY "Permissive support_messages policy" 
ON public.support_messages 
FOR ALL 
TO public
USING (true) 
WITH CHECK (true);

-- 8. Storage bucket & policies for attachments
INSERT INTO storage.buckets (id, name, public) 
VALUES ('support_attachments', 'support_attachments', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Allow public reads on support_attachments" ON storage.objects;
CREATE POLICY "Allow public reads on support_attachments"
ON storage.objects FOR SELECT USING (bucket_id = 'support_attachments');

DROP POLICY IF EXISTS "Allow auth users to insert in support_attachments" ON storage.objects;
CREATE POLICY "Allow auth users to insert in support_attachments"
ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'support_attachments');
