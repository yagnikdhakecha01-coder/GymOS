-- ==============================================================================
-- MIGRATION: FIX PROFILES TRIGGER, INVITATION REDEMPTION, AND AUTO-LINK MEMBERS
-- Resolves Gym Rules Agreement loop and missing member agreements
-- ==============================================================================

-- 1. Ensure avatar_url exists in public.profiles and sync with photo_url
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;

UPDATE public.profiles 
SET avatar_url = photo_url 
WHERE avatar_url IS NULL AND photo_url IS NOT NULL;

UPDATE public.profiles 
SET photo_url = avatar_url 
WHERE photo_url IS NULL AND avatar_url IS NOT NULL;

-- 2. Backfill missing auth.users into public.profiles
INSERT INTO public.profiles (id, email, full_name, name, photo_url, avatar_url)
SELECT 
    u.id,
    COALESCE(u.email, ''),
    COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
    COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
    COALESCE(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture', ''),
    COALESCE(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture', '')
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
    avatar_url = COALESCE(public.profiles.avatar_url, EXCLUDED.avatar_url);

-- 3. Robust handle_new_user_profile trigger function
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
DECLARE
    v_name TEXT;
    v_photo TEXT;
BEGIN
    v_name := COALESCE(
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'name',
        split_part(NEW.email, '@', 1)
    );
    v_photo := COALESCE(
        NEW.raw_user_meta_data->>'avatar_url',
        NEW.raw_user_meta_data->>'picture',
        ''
    );

    INSERT INTO public.profiles (id, email, full_name, name, photo_url, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.email, ''),
        v_name,
        v_name,
        v_photo,
        v_photo
    )
    ON CONFLICT (id) DO UPDATE 
    SET 
        email = EXCLUDED.email,
        full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
        name = COALESCE(public.profiles.name, EXCLUDED.name),
        photo_url = COALESCE(public.profiles.photo_url, EXCLUDED.photo_url),
        avatar_url = COALESCE(public.profiles.avatar_url, EXCLUDED.avatar_url);
        
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Robust redeem_gym_invitation RPC function
CREATE OR REPLACE FUNCTION public.redeem_gym_invitation(
  p_code TEXT,
  p_mobile TEXT
) RETURNS JSONB AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_invite RECORD;
  v_gym_id UUID;
  v_role TEXT;
  v_full_name TEXT := '';
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Authentication required.');
  END IF;

  SELECT * INTO v_invite
  FROM public.invitations
  WHERE LOWER(TRIM(invitation_code)) = LOWER(TRIM(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid invitation code.');
  END IF;

  IF v_invite.code_used = TRUE OR v_invite.status NOT IN ('Pending', 'Active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'This invitation code is no longer active.');
  END IF;

  IF v_invite.expires_at IS NOT NULL AND now() > v_invite.expires_at THEN
    UPDATE public.invitations SET status = 'Expired' WHERE id = v_invite.id;
    RETURN jsonb_build_object('success', false, 'error', 'This invitation code has expired.');
  END IF;

  IF TRIM(v_invite.registered_mobile) <> TRIM(p_mobile) AND RIGHT(TRIM(v_invite.registered_mobile), 10) <> RIGHT(TRIM(p_mobile), 10) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Wrong Mobile Number.');
  END IF;

  v_gym_id := v_invite.gym_id;
  v_role := CASE WHEN v_invite.member_id IS NOT NULL THEN 'member' ELSE 'staff' END;

  IF v_invite.member_id IS NOT NULL THEN
    SELECT name INTO v_full_name FROM public.members WHERE id = v_invite.member_id;
  ELSIF v_invite.staff_id IS NOT NULL THEN
    SELECT name INTO v_full_name FROM public.staff WHERE id = v_invite.staff_id;
  END IF;

  -- 1. Ensure caller has a profile record (satisfies foreign key)
  INSERT INTO public.profiles (id, email, full_name, name)
  SELECT 
    v_caller_id,
    COALESCE(u.email, ''),
    COALESCE(v_full_name, u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
    COALESCE(v_full_name, u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1))
  FROM auth.users u WHERE u.id = v_caller_id
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name);

  -- 2. Ensure association exists
  IF NOT EXISTS (
    SELECT 1 FROM public.user_gym_associations
    WHERE user_id = v_caller_id AND gym_id = v_gym_id AND role = v_role
  ) THEN
    INSERT INTO public.user_gym_associations (user_id, gym_id, role, setup_completed)
    VALUES (v_caller_id, v_gym_id, v_role, TRUE)
    ON CONFLICT (user_id, gym_id, role) DO UPDATE SET setup_completed = TRUE;
  END IF;

  -- 3. Link member or staff record
  IF v_invite.member_id IS NOT NULL THEN
    UPDATE public.members
    SET user_id = v_caller_id, 
        status = 'Active',
        email = COALESCE(NULLIF(members.email, ''), (SELECT email FROM auth.users WHERE id = v_caller_id))
    WHERE id = v_invite.member_id;
  ELSIF v_invite.staff_id IS NOT NULL THEN
    UPDATE public.staff
    SET user_id = v_caller_id, status = 'Active'
    WHERE id = v_invite.staff_id;
  END IF;

  -- 4. Mark invitation as used
  UPDATE public.invitations
  SET code_used = TRUE,
      status = 'Used',
      activated_at = now()
  WHERE id = v_invite.id;

  RETURN jsonb_build_object(
    'success', true,
    'gym_id', v_gym_id,
    'role', v_role,
    'full_name', v_full_name
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Robust submit_member_rule_agreement RPC function
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
    v_gym_id UUID := p_gym_id;
    v_member_id UUID := p_member_id;
BEGIN
    v_uid := COALESCE(p_user_id, auth.uid());

    -- If member_id was not provided or empty, attempt auto-resolution from user_id
    IF v_member_id IS NULL AND v_uid IS NOT NULL THEN
        SELECT id, gym_id INTO v_member_id, v_gym_id 
        FROM public.members 
        WHERE user_id = v_uid 
        ORDER BY created_at DESC 
        LIMIT 1;
    END IF;

    -- If gym_id was not provided, fetch from member
    IF v_gym_id IS NULL AND v_member_id IS NOT NULL THEN
        SELECT gym_id INTO v_gym_id FROM public.members WHERE id = v_member_id;
    END IF;

    -- Auto fill name & phone from members table if missing
    IF v_member_id IS NOT NULL THEN
        SELECT name, phone INTO v_name, v_phone FROM public.members WHERE id = v_member_id;
        IF p_member_name IS NULL OR p_member_name = '' OR p_member_name = 'Member' THEN
            p_member_name := COALESCE(v_name, 'Member');
        END IF;
        IF p_member_phone IS NULL OR p_member_phone = '' THEN
            p_member_phone := COALESCE(v_phone, '');
        END IF;

        -- Auto link member to user if not linked yet
        IF v_uid IS NOT NULL THEN
            UPDATE public.members 
            SET user_id = v_uid 
            WHERE id = v_member_id AND user_id IS NULL;

            -- Also ensure user_gym_associations exists for this member
            IF v_gym_id IS NOT NULL THEN
                INSERT INTO public.user_gym_associations (user_id, gym_id, role, setup_completed)
                VALUES (v_uid, v_gym_id, 'member', TRUE)
                ON CONFLICT (user_id, gym_id, role) DO UPDATE SET setup_completed = TRUE;
            END IF;
        END IF;
    END IF;

    IF v_gym_id IS NULL OR v_member_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Gym ID or Member ID could not be resolved'
        );
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
        v_gym_id,
        v_member_id,
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

    RETURN jsonb_build_object(
        'id', v_record.id,
        'gym_id', v_record.gym_id,
        'member_id', v_record.member_id,
        'user_id', v_record.user_id,
        'member_name', v_record.member_name,
        'member_phone', v_record.member_phone,
        'rules_version', v_record.rules_version,
        'language', v_record.language,
        'agreed', v_record.agreed,
        'agreed_at', to_char(v_record.agreed_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS'),
        'device_info', v_record.device_info,
        'created_at', to_char(v_record.created_at AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.submit_member_rule_agreement TO authenticated, anon;

-- 6. Two-Way Auto-Linking Triggers
CREATE OR REPLACE FUNCTION public.handle_auto_link_member_on_auth_user()
RETURNS TRIGGER AS $$
DECLARE
    v_member RECORD;
    v_clean_phone TEXT;
BEGIN
    IF NEW.phone IS NOT NULL AND NEW.phone <> '' THEN
        v_clean_phone := RIGHT(REGEXP_REPLACE(NEW.phone, '\D', '', 'g'), 10);
    ELSE
        v_clean_phone := NULL;
    END IF;

    FOR v_member IN 
        SELECT id, gym_id, email, phone 
        FROM public.members 
        WHERE user_id IS NULL 
          AND (
              (NEW.email IS NOT NULL AND NEW.email <> '' AND LOWER(TRIM(email)) = LOWER(TRIM(NEW.email)))
              OR (v_clean_phone IS NOT NULL AND v_clean_phone <> '' AND RIGHT(REGEXP_REPLACE(phone, '\D', '', 'g'), 10) = v_clean_phone)
          )
    LOOP
        UPDATE public.members 
        SET user_id = NEW.id,
            status = 'Active',
            email = COALESCE(NULLIF(members.email, ''), NEW.email)
        WHERE id = v_member.id;

        INSERT INTO public.user_gym_associations (user_id, gym_id, role, setup_completed)
        VALUES (NEW.id, v_member.gym_id, 'member', TRUE)
        ON CONFLICT (user_id, gym_id, role) DO UPDATE SET setup_completed = TRUE;

        UPDATE public.invitations 
        SET code_used = TRUE,
            status = 'Used',
            activated_at = NOW()
        WHERE member_id = v_member.id AND code_used = FALSE;
    END LOOP;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_auto_link_member_on_auth_user ON auth.users;
CREATE TRIGGER trg_auto_link_member_on_auth_user
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_auto_link_member_on_auth_user();

CREATE OR REPLACE FUNCTION public.handle_auto_link_member_on_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_clean_phone TEXT;
BEGIN
    IF NEW.user_id IS NULL THEN
        IF NEW.phone IS NOT NULL AND NEW.phone <> '' THEN
            v_clean_phone := RIGHT(REGEXP_REPLACE(NEW.phone, '\D', '', 'g'), 10);
        ELSE
            v_clean_phone := NULL;
        END IF;

        SELECT id INTO v_user_id 
        FROM auth.users 
        WHERE (NEW.email IS NOT NULL AND NEW.email <> '' AND LOWER(TRIM(email)) = LOWER(TRIM(NEW.email)))
           OR (v_clean_phone IS NOT NULL AND v_clean_phone <> '' AND RIGHT(REGEXP_REPLACE(COALESCE(phone, ''), '\D', '', 'g'), 10) = v_clean_phone)
        ORDER BY created_at DESC 
        LIMIT 1;

        IF v_user_id IS NOT NULL THEN
            NEW.user_id := v_user_id;

            INSERT INTO public.profiles (id, email, full_name, name)
            VALUES (v_user_id, COALESCE(NEW.email, ''), NEW.name, NEW.name)
            ON CONFLICT (id) DO NOTHING;

            INSERT INTO public.user_gym_associations (user_id, gym_id, role, setup_completed)
            VALUES (v_user_id, NEW.gym_id, 'member', TRUE)
            ON CONFLICT (user_id, gym_id, role) DO UPDATE SET setup_completed = TRUE;
        END IF;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_auto_link_member_on_insert ON public.members;
CREATE TRIGGER trg_auto_link_member_on_insert
    BEFORE INSERT ON public.members
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_auto_link_member_on_insert();
