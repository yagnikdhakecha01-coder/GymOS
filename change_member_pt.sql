-- MIGRATION: CHANGE MEMBER PERSONAL TRAINER & SNAPSHOT COMMISSION PERCENTAGE
-- This script adds an RPC function to change a member's PT assignment.
-- It automatically deactivates any existing active assignment so that commission edits
-- apply only to future payments (not retroactively).

CREATE OR REPLACE FUNCTION public.change_member_pt(
    p_gym_id UUID,
    p_member_id UUID,
    p_pt_member BOOLEAN,
    p_staff_id UUID,
    p_commission_percentage NUMERIC
) RETURNS VOID AS $$
BEGIN
    -- 1. Inactivate any existing active PT assignments for this member
    UPDATE public.pt_assignments
    SET assignment_status = 'Inactive', updated_at = now()
    WHERE member_id = p_member_id AND assignment_status = 'Active';

    -- 2. If pt_member is true, insert the new active PT assignment
    IF p_pt_member = TRUE AND p_staff_id IS NOT NULL THEN
        INSERT INTO public.pt_assignments (
            gym_id,
            member_id,
            staff_id,
            commission_percentage,
            assignment_status,
            pt_start_date
        ) VALUES (
            p_gym_id,
            p_member_id,
            p_staff_id,
            p_commission_percentage,
            'Active',
            CURRENT_DATE
        );
    END IF;

    -- 3. Update the members table to keep it in sync
    UPDATE public.members
    SET 
        pt_member = p_pt_member,
        pt_trainer = CASE WHEN p_pt_member = TRUE THEN p_staff_id ELSE NULL END
    WHERE id = p_member_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions to standard roles
GRANT EXECUTE ON FUNCTION public.change_member_pt(UUID, UUID, BOOLEAN, UUID, NUMERIC) TO anon, authenticated, service_role;
