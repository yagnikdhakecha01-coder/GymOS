-- ====================================================
-- GYMOS - CREATE FITNESS_GOALS AND CUSTOM_MEMBER_FIELDS TABLES
-- ====================================================

-- 1. Create Fitness Goals Table
CREATE TABLE IF NOT EXISTS public.fitness_goals (
    id TEXT PRIMARY KEY,
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT '💪',
    color TEXT NOT NULL DEFAULT '0xFF7C3AED',
    description TEXT DEFAULT '' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing for performance
CREATE INDEX IF NOT EXISTS idx_fitness_goals_gym ON public.fitness_goals(gym_id);

-- Enable RLS
ALTER TABLE public.fitness_goals ENABLE ROW LEVEL SECURITY;

-- Policy
DROP POLICY IF EXISTS fitness_goals_isolation ON public.fitness_goals;
CREATE POLICY fitness_goals_isolation ON public.fitness_goals
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- Grants
GRANT ALL ON TABLE public.fitness_goals TO anon, authenticated, service_role;


-- 2. Create Custom Member Fields Table
CREATE TABLE IF NOT EXISTS public.custom_member_fields (
    id TEXT PRIMARY KEY,
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE NOT NULL,
    label TEXT NOT NULL,
    field_type TEXT NOT NULL,
    options JSONB DEFAULT '[]'::jsonb NOT NULL,
    required BOOLEAN DEFAULT FALSE NOT NULL,
    visible BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexing for performance
CREATE INDEX IF NOT EXISTS idx_custom_member_fields_gym ON public.custom_member_fields(gym_id);

-- Enable RLS
ALTER TABLE public.custom_member_fields ENABLE ROW LEVEL SECURITY;

-- Policy
DROP POLICY IF EXISTS custom_member_fields_isolation ON public.custom_member_fields;
CREATE POLICY custom_member_fields_isolation ON public.custom_member_fields
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- Grants
GRANT ALL ON TABLE public.custom_member_fields TO anon, authenticated, service_role;
