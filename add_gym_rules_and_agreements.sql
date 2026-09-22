-- ==============================================================================
-- MIGRATION: GYM RULES AND MEMBER AGREEMENTS SYSTEM (PHASE 09)
-- ==============================================================================

-- 1. GYM RULES TABLE
CREATE TABLE IF NOT EXISTS public.gym_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE UNIQUE,
    version INTEGER NOT NULL DEFAULT 1,
    rules_data JSONB, -- Custom rules if customized by owner
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by UUID
);

-- Index for fast lookup by gym_id
CREATE INDEX IF NOT EXISTS idx_gym_rules_gym_id ON public.gym_rules(gym_id);

-- 2. MEMBER RULE AGREEMENTS TABLE
CREATE TABLE IF NOT EXISTS public.member_rule_agreements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    member_name TEXT,
    member_phone TEXT,
    rules_version INTEGER NOT NULL DEFAULT 1,
    language TEXT NOT NULL DEFAULT 'en', -- 'en', 'hi', 'gu'
    agreed BOOLEAN NOT NULL DEFAULT TRUE,
    agreed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    device_info TEXT,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_gym_member_rule_version UNIQUE (gym_id, member_id, rules_version)
);

-- Indexes for lightning fast queries
CREATE INDEX IF NOT EXISTS idx_member_rule_agreements_gym_member 
    ON public.member_rule_agreements(gym_id, member_id);
CREATE INDEX IF NOT EXISTS idx_member_rule_agreements_user_id 
    ON public.member_rule_agreements(user_id);
CREATE INDEX IF NOT EXISTS idx_member_rule_agreements_gym_agreed_at 
    ON public.member_rule_agreements(gym_id, agreed_at DESC);

-- 3. ENABLE ROW LEVEL SECURITY
ALTER TABLE public.gym_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_rule_agreements ENABLE ROW LEVEL SECURITY;

-- 4. RLS POLICIES FOR GYM_RULES
-- Anyone authenticated can view rules of their gym
DROP POLICY IF EXISTS "Allow users to view their gym rules" ON public.gym_rules;
CREATE POLICY "Allow users to view their gym rules"
    ON public.gym_rules
    FOR SELECT
    TO authenticated
    USING (
        gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM public.members WHERE user_id = auth.uid() AND gym_id = public.gym_rules.gym_id)
        OR EXISTS (SELECT 1 FROM public.gyms WHERE owner_id = auth.uid() AND id = public.gym_rules.gym_id)
    );

-- Gym Owners can insert/update gym rules
DROP POLICY IF EXISTS "Allow owners to manage their gym rules" ON public.gym_rules;
CREATE POLICY "Allow owners to manage their gym rules"
    ON public.gym_rules
    FOR ALL
    TO authenticated
    USING (
        gym_id IN (SELECT id FROM public.gyms WHERE owner_id = auth.uid())
        OR gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid() AND role = 'owner')
    )
    WITH CHECK (
        gym_id IN (SELECT id FROM public.gyms WHERE owner_id = auth.uid())
        OR gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid() AND role = 'owner')
    );

-- 5. RLS POLICIES FOR MEMBER_RULE_AGREEMENTS
-- Members can insert their own agreements
DROP POLICY IF EXISTS "Allow members to insert their own agreement" ON public.member_rule_agreements;
CREATE POLICY "Allow members to insert their own agreement"
    ON public.member_rule_agreements
    FOR INSERT
    TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.members 
            WHERE id = member_id AND (user_id = auth.uid() OR gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
        )
    );

-- Members can view their own agreements; Owners and staff can view agreements of their gym
DROP POLICY IF EXISTS "Allow users to read relevant agreements" ON public.member_rule_agreements;
CREATE POLICY "Allow users to read relevant agreements"
    ON public.member_rule_agreements
    FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid()
        OR gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid())
        OR gym_id IN (SELECT id FROM public.gyms WHERE owner_id = auth.uid())
    );

-- Trigger for automatic updated_at timestamp on gym_rules
CREATE OR REPLACE FUNCTION public.handle_gym_rules_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_gym_rules_updated_at ON public.gym_rules;
CREATE TRIGGER trg_gym_rules_updated_at
    BEFORE UPDATE ON public.gym_rules
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_gym_rules_updated_at();
