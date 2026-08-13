-- =========================================================================
-- BACKFILL: Pehle se assigned PT members ab staff ko dikhenge
-- Supabase SQL Editor mein paste karke RUN karo (sirf ek baar)
-- =========================================================================

-- 1. get_trainer_clients RPC (latest — pt_trainer OR pt_assignments dono se)
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

GRANT EXECUTE ON FUNCTION public.get_trainer_clients(UUID) TO anon, authenticated, service_role;

-- 2. pt_assignments table agar nahi hai to banao
CREATE TABLE IF NOT EXISTS public.pt_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    commission_percentage NUMERIC(5, 2) NOT NULL DEFAULT 0.0,
    assignment_status TEXT NOT NULL DEFAULT 'Active',
    pt_start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3. FIX A: members jinke paas trainer set hai — pt_member = true karo
UPDATE public.members
SET pt_member = TRUE
WHERE pt_trainer IS NOT NULL
  AND (pt_member IS NULL OR pt_member = FALSE);

-- 4. FIX B: members.pt_trainer khali hai lekin pt_assignments mein Active row hai
UPDATE public.members m
SET
    pt_trainer = pa.staff_id,
    pt_member = TRUE
FROM public.pt_assignments pa
WHERE pa.member_id = m.id
  AND pa.assignment_status = 'Active'
  AND m.pt_trainer IS NULL;

-- 5. FIX C: members.pt_trainer set hai lekin pt_assignments row missing — insert karo
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
    CURRENT_DATE
FROM public.members m
INNER JOIN public.staff st ON st.id = m.pt_trainer AND st.gym_id = m.gym_id
WHERE m.pt_trainer IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.pt_assignments pa
      WHERE pa.member_id = m.id
        AND pa.staff_id = m.pt_trainer
        AND pa.assignment_status = 'Active'
  );

-- 6. Verify — kitne members ab sync ho gaye
SELECT
    s.name AS trainer_name,
    s.id AS staff_id,
    COUNT(m.id) AS assigned_clients
FROM public.staff s
LEFT JOIN public.members m ON m.pt_trainer = s.id AND m.gym_id = s.gym_id
WHERE s.role ILIKE '%trainer%' OR s.role ILIKE '%Trainer%'
GROUP BY s.id, s.name
ORDER BY assigned_clients DESC;

-- Test ek trainer ke liye (staff UUID yahan daalo):
-- SELECT * FROM public.get_trainer_clients('YOUR-STAFF-UUID');
