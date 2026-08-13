-- =========================================================================
-- DATABASE FUNCTION: get_trainer_clients
-- Run this in your Supabase SQL Editor to retrieve a trainer's assigned
-- member details directly from the database.
-- =========================================================================

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
