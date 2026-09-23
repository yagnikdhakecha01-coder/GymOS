-- ========================================================
-- AUTOMATIC MEMBER INVITATION CODE GENERATION TRIGGER
-- ========================================================

CREATE OR REPLACE FUNCTION public.fn_generate_invitation_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result TEXT := '';
    i INT;
BEGIN
    FOR i IN 1..6 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_auto_create_member_invitation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_code TEXT;
    v_attempts INT := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.invitations 
        WHERE member_id = NEW.id AND code_used = false
    ) THEN
        LOOP
            v_code := public.fn_generate_invitation_code();
            IF NOT EXISTS (SELECT 1 FROM public.invitations WHERE invitation_code = v_code) THEN
                EXIT;
            END IF;
            v_attempts := v_attempts + 1;
            IF v_attempts > 10 THEN
                v_code := v_code || floor(random() * 90 + 10)::text;
                EXIT;
            END IF;
        END LOOP;

        INSERT INTO public.invitations (
            id,
            gym_id,
            member_id,
            invitation_code,
            registered_mobile,
            status,
            code_used,
            created_at,
            expires_at
        ) VALUES (
            gen_random_uuid(),
            NEW.gym_id,
            NEW.id,
            v_code,
            COALESCE(NEW.phone, ''),
            'Pending',
            false,
            NOW(),
            NOW() + INTERVAL '30 days'
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_create_member_invitation ON public.members;
CREATE TRIGGER trg_auto_create_member_invitation
AFTER INSERT ON public.members
FOR EACH ROW
EXECUTE FUNCTION public.fn_auto_create_member_invitation();
