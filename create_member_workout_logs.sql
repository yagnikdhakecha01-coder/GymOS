-- ====================================================
-- CREATE MEMBER WORKOUT LOGS TABLE
-- ====================================================

CREATE TABLE IF NOT EXISTS public.member_workout_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    muscle TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('Completed', 'Not Done')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT unique_member_date UNIQUE (member_id, date)
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.member_workout_logs ENABLE ROW LEVEL SECURITY;

-- Create policy for authenticated users
DROP POLICY IF EXISTS member_workout_logs_isolation ON public.member_workout_logs;
CREATE POLICY member_workout_logs_isolation ON public.member_workout_logs 
    FOR ALL 
    TO authenticated 
    USING (true)
    WITH CHECK (true);
