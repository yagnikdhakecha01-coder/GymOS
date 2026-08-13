-- =========================================================================
-- FIX: Staff "My Clients (PT)" not showing assigned members
-- Supabase SQL Editor mein poora script paste karke RUN karo
--
-- Root cause:
--   Owner member profile se trainer assign karta hai (members.pt_trainer)
--   lekin pt_assignments table sync nahi hoti thi, ya pt_member=false reh jata tha.
--
-- Yeh script:
--   1. pt_assignments table ensure karta hai
--   2. members update par auto-sync trigger lagata hai
--   3. change_member_pt RPC improve karta hai
--   4. get_trainer_clients RPC robust banata hai
--   5. Pehle se assigned members ka backfill karta hai
-- =========================================================================

-- -------------------------------------------------------------------------
-- STEP 1: Ensure pt_assignments table exists
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pt_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    commission_percentage NUMERIC(5, 2) NOT NULL DEFAULT 0.0 CHECK (commission_percentage >= 0),
    assignment_status TEXT NOT NULL DEFAULT 'Active' CHECK (assignment_status IN ('Active', 'Inactive')),
    pt_start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pt_assignments_lookup
    ON public.pt_assignments (member_id, staff_id, assignment_status);
CREATE INDEX IF NOT EXISTS idx_pt_assignments_staff
    ON public.pt_assignments (staff_id, assignment_status);
CREATE INDEX IF NOT EXISTS idx_pt_assignments_gym
    ON public.pt_assignments (gym_id);

ALTER TABLE public.pt_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pt_assignments_isolation ON public.pt_assignments;
CREATE POLICY pt_assignments_isolation ON public.pt_assignments
    FOR ALL TO authenticated
    USING (
        gym_id IN (
            SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
        )
    )
    WITH CHECK (
        gym_id IN (
            SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()
        )
    );

-- Optional member columns (safe if already exist)
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS email TEXT DEFAULT '';
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(12, 2) DEFAULT 0.0;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS total_received_amount NUMERIC(12, 2) DEFAULT 0.0;
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'Pending';

-- -------------------------------------------------------------------------
-- STEP 2: Auto-sync trigger — jab owner members.pt_trainer set kare
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_sync_pt_assignment_from_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_commission NUMERIC(5,2) := 0;
BEGIN
    -- Trainer assign hua
    IF NEW.pt_trainer IS NOT NULL THEN
        NEW.pt_member := TRUE;

        SELECT COALESCE(s.commission_percentage, 0) INTO v_commission
        FROM public.staff s
        WHERE s.id = NEW.pt_trainer
        LIMIT 1;

        -- Purane active assignments band karo (dusre trainer ke)
        UPDATE public.pt_assignments
        SET assignment_status = 'Inactive', updated_at = now()
        WHERE member_id = NEW.id
          AND assignment_status = 'Active'
          AND staff_id IS DISTINCT FROM NEW.pt_trainer;

        -- Naya active assignment create karo agar nahi hai
        IF NOT EXISTS (
            SELECT 1 FROM public.pt_assignments
            WHERE member_id = NEW.id
              AND staff_id = NEW.pt_trainer
              AND assignment_status = 'Active'
        ) THEN
            INSERT INTO public.pt_assignments (
                gym_id, member_id, staff_id,
                commission_percentage, assignment_status, pt_start_date
            ) VALUES (
                NEW.gym_id, NEW.id, NEW.pt_trainer,
                v_commission, 'Active', CURRENT_DATE
            );
        END IF;

    -- PT hata diya
    ELSIF TG_OP = 'UPDATE' AND (NEW.pt_trainer IS NULL OR NEW.pt_member = FALSE) THEN
        UPDATE public.pt_assignments
        SET assignment_status = 'Inactive', updated_at = now()
        WHERE member_id = NEW.id AND assignment_status = 'Active';

        IF NEW.pt_member = FALSE THEN
            NEW.pt_trainer := NULL;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_pt_assignment_from_member ON public.members;
CREATE TRIGGER trg_sync_pt_assignment_from_member
    BEFORE INSERT OR UPDATE OF pt_trainer, pt_member
    ON public.members
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_sync_pt_assignment_from_member();

-- -------------------------------------------------------------------------
-- STEP 3: Owner PT assignment RPC (app se call hota hai)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.change_member_pt(
    p_gym_id UUID,
    p_member_id UUID,
    p_pt_member BOOLEAN,
    p_staff_id UUID,
    p_commission_percentage NUMERIC
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_pt_member = TRUE AND p_staff_id IS NOT NULL THEN
        UPDATE public.members
        SET
            pt_member = TRUE,
            pt_trainer = p_staff_id
        WHERE id = p_member_id AND gym_id = p_gym_id;

        UPDATE public.pt_assignments
        SET assignment_status = 'Inactive', updated_at = now()
        WHERE member_id = p_member_id AND assignment_status = 'Active';

        INSERT INTO public.pt_assignments (
            gym_id, member_id, staff_id,
            commission_percentage, assignment_status, pt_start_date
        ) VALUES (
            p_gym_id, p_member_id, p_staff_id,
            COALESCE(p_commission_percentage, 0), 'Active', CURRENT_DATE
        );
    ELSE
        UPDATE public.members
        SET pt_member = FALSE, pt_trainer = NULL
        WHERE id = p_member_id AND gym_id = p_gym_id;

        UPDATE public.pt_assignments
        SET assignment_status = 'Inactive', updated_at = now()
        WHERE member_id = p_member_id AND assignment_status = 'Active';
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.change_member_pt(UUID, UUID, BOOLEAN, UUID, NUMERIC)
    TO anon, authenticated, service_role;

-- -------------------------------------------------------------------------
-- STEP 4: Staff "My Clients" RPC — saare assigned members dikhao
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_trainer_clients(p_staff_id UUID)
RETURNS TABLE (
    member_id UUID,
    member_name TEXT,
    member_email TEXT,
    member_phone TEXT,
    member_avatar TEXT,
    member_status TEXT,
    program TEXT,
    assignment_status TEXT,
    pt_start_date TEXT,
    membership_plan_id UUID,
    medical_details TEXT,
    notes TEXT,
    total_received_amount NUMERIC,
    pending_amount NUMERIC,
    discount_amount NUMERIC,
    payment_status TEXT,
    extra_fields JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (m.id)
        m.id AS member_id,
        m.name::text AS member_name,
        COALESCE(m.email, '')::text AS member_email,
        COALESCE(m.phone, '')::text AS member_phone,
        COALESCE(m.avatar, '')::text AS member_avatar,
        m.status::text AS member_status,
        ('PT - ' || COALESCE(pa.commission_percentage, s.commission_percentage, 0)::text || '% Comm.')::text AS program,
        COALESCE(pa.assignment_status, 'Active')::text AS assignment_status,
        COALESCE(pa.pt_start_date::text, m.join_date::text, '')::text AS pt_start_date,
        (CASE
            WHEN m.membership_plan_id IS NOT NULL
                 AND m.membership_plan_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            THEN m.membership_plan_id::uuid
            ELSE NULL
         END) AS membership_plan_id,
        COALESCE(m.medical_details, '')::text AS medical_details,
        COALESCE(m.notes, '')::text AS notes,
        COALESCE(m.total_received_amount, 0)::numeric AS total_received_amount,
        COALESCE(m.pending_amount, 0)::numeric AS pending_amount,
        COALESCE(m.discount_amount, 0)::numeric AS discount_amount,
        COALESCE(m.payment_status, 'Pending')::text AS payment_status,
        COALESCE(m.extra_fields, '{}'::jsonb) AS extra_fields
    FROM public.staff s
    INNER JOIN public.members m ON m.gym_id = s.gym_id
    LEFT JOIN public.pt_assignments pa
        ON pa.member_id = m.id
       AND pa.staff_id = p_staff_id
       AND pa.assignment_status = 'Active'
    WHERE s.id = p_staff_id
      AND (
          m.pt_trainer = p_staff_id
          OR pa.id IS NOT NULL
      )
    ORDER BY m.id, pa.created_at DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_trainer_clients(UUID)
    TO anon, authenticated, service_role;

-- -------------------------------------------------------------------------
-- STEP 5: BACKFILL — pehle se assign kiye members ab dikhenge
-- -------------------------------------------------------------------------

-- pt_member flag fix karo jahan trainer set hai
UPDATE public.members
SET pt_member = TRUE
WHERE pt_trainer IS NOT NULL AND pt_member = FALSE;

-- pt_assignments mein missing rows insert karo
INSERT INTO public.pt_assignments (
    gym_id, member_id, staff_id,
    commission_percentage, assignment_status, pt_start_date
)
SELECT
    m.gym_id,
    m.id,
    m.pt_trainer,
    COALESCE(st.commission_percentage, 0),
    'Active',
    COALESCE(
        CASE
            WHEN m.join_date IS NOT NULL AND m.join_date ~ '^\d{4}-\d{2}-\d{2}'
            THEN m.join_date::date
            ELSE NULL
        END,
        CURRENT_DATE
    )
FROM public.members m
JOIN public.staff st ON st.id = m.pt_trainer
WHERE m.pt_trainer IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.pt_assignments pa
      WHERE pa.member_id = m.id
        AND pa.staff_id = m.pt_trainer
        AND pa.assignment_status = 'Active'
  );

-- -------------------------------------------------------------------------
-- VERIFY (optional — test ke liye staff UUID daalo)
-- -------------------------------------------------------------------------
-- SELECT * FROM public.get_trainer_clients('YOUR-STAFF-UUID-HERE');
