-- ==============================================================================
-- MIGRATION: FIX AGREEMENT UPSERT & ADD OWNER CUSTOM RULES RPC
-- ==============================================================================

-- 1. Ensure UPDATE policy exists on member_rule_agreements
DROP POLICY IF EXISTS "Allow members to update their own agreement" ON public.member_rule_agreements;
CREATE POLICY "Allow members to update their own agreement"
    ON public.member_rule_agreements
    FOR UPDATE
    TO authenticated
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.members 
            WHERE id = member_id AND (user_id = auth.uid() OR gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
        )
    )
    WITH CHECK (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.members 
            WHERE id = member_id AND (user_id = auth.uid() OR gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()))
        )
    );

-- 2. SECURITY DEFINER RPC: submit_member_rule_agreement
CREATE OR REPLACE FUNCTION public.submit_member_rule_agreement(
    p_gym_id UUID,
    p_member_id UUID,
    p_user_id UUID DEFAULT NULL,
    p_member_name TEXT DEFAULT 'Member',
    p_member_phone TEXT DEFAULT '',
    p_rules_version INT DEFAULT 1,
    p_language TEXT DEFAULT 'en',
    p_device_info TEXT DEFAULT 'Mobile App'
) RETURNS JSONB AS $$
DECLARE
    v_record RECORD;
    v_uid UUID;
    v_name TEXT;
    v_phone TEXT;
BEGIN
    v_uid := COALESCE(p_user_id, auth.uid());
    
    -- Auto fill name & phone from members table if missing
    SELECT name, phone INTO v_name, v_phone FROM public.members WHERE id = p_member_id;
    IF p_member_name IS NULL OR p_member_name = '' OR p_member_name = 'Member' THEN
        p_member_name := COALESCE(v_name, 'Member');
    END IF;
    IF p_member_phone IS NULL OR p_member_phone = '' THEN
        p_member_phone := COALESCE(v_phone, '');
    END IF;

    INSERT INTO public.member_rule_agreements (
        gym_id,
        member_id,
        user_id,
        member_name,
        member_phone,
        rules_version,
        language,
        agreed,
        agreed_at,
        device_info
    ) VALUES (
        p_gym_id,
        p_member_id,
        v_uid,
        p_member_name,
        p_member_phone,
        COALESCE(p_rules_version, 1),
        COALESCE(p_language, 'en'),
        TRUE,
        NOW(),
        COALESCE(p_device_info, 'Mobile App')
    )
    ON CONFLICT (gym_id, member_id, rules_version)
    DO UPDATE SET
        user_id = COALESCE(EXCLUDED.user_id, member_rule_agreements.user_id),
        member_name = EXCLUDED.member_name,
        member_phone = EXCLUDED.member_phone,
        language = EXCLUDED.language,
        agreed = TRUE,
        agreed_at = NOW(),
        device_info = EXCLUDED.device_info
    RETURNING * INTO v_record;

    RETURN to_jsonb(v_record);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. SECURITY DEFINER RPC: save_gym_custom_rules
CREATE OR REPLACE FUNCTION public.save_gym_custom_rules(
    p_gym_id UUID,
    p_rules_data JSONB
) RETURNS JSONB AS $$
DECLARE
    v_record RECORD;
    v_new_version INT;
BEGIN
    -- Get current version or 1
    SELECT COALESCE(version, 0) + 1 INTO v_new_version FROM public.gym_rules WHERE gym_id = p_gym_id;
    IF v_new_version IS NULL OR v_new_version < 1 THEN
        v_new_version := 1;
    END IF;

    INSERT INTO public.gym_rules (
        gym_id,
        version,
        rules_data,
        is_active,
        updated_at,
        updated_by
    ) VALUES (
        p_gym_id,
        v_new_version,
        p_rules_data,
        TRUE,
        NOW(),
        auth.uid()
    )
    ON CONFLICT (gym_id)
    DO UPDATE SET
        version = v_new_version,
        rules_data = EXCLUDED.rules_data,
        is_active = TRUE,
        updated_at = NOW(),
        updated_by = auth.uid()
    RETURNING * INTO v_record;

    RETURN to_jsonb(v_record);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.submit_member_rule_agreement TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.save_gym_custom_rules TO authenticated;
