-- Drop table first to rebuild columns cleanly (including owner_id)
DROP TABLE IF EXISTS public.support_tickets CASCADE;

-- Create support_tickets table
CREATE TABLE public.support_tickets (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    title text NOT NULL,
    description text NOT NULL,
    priority text NOT NULL DEFAULT 'medium',
    status text NOT NULL DEFAULT 'Open',
    gym_id uuid REFERENCES public.gyms(id) ON DELETE CASCADE,
    gym_name text,
    owner_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Select policy: users can read their own support tickets
DROP POLICY IF EXISTS "Allow users to read their own support tickets" ON public.support_tickets;
CREATE POLICY "Allow users to read their own support tickets" 
ON public.support_tickets 
FOR SELECT 
USING (auth.uid() = owner_id);

-- Insert policy: authenticated users can insert support tickets
DROP POLICY IF EXISTS "Allow authenticated users to insert support tickets" ON public.support_tickets;
CREATE POLICY "Allow authenticated users to insert support tickets" 
ON public.support_tickets 
FOR INSERT 
WITH CHECK (auth.uid() = owner_id);

-- Admin policy: Allow all actions on support tickets
DROP POLICY IF EXISTS "Allow all actions on support tickets" ON public.support_tickets;
CREATE POLICY "Allow all actions on support tickets" 
ON public.support_tickets 
FOR ALL 
USING (true) 
WITH CHECK (true);
