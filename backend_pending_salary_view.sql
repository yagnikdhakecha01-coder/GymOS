-- ====================================================
-- GYMOS - DYNAMIC BACKEND PENDING SALARY VIEW
-- ====================================================
-- Run this in your Supabase SQL Editor to compute Pending Salary
-- (Salary + Commission - Advance) directly inside the Database View!

CREATE OR REPLACE VIEW public.vw_pending_salary_list AS
SELECT 
    s.id AS staff_id,
    s.gym_id,
    s.name,
    s.role,
    s.avatar,
    s.salary AS base_salary,
    COALESCE((
        SELECT SUM(cl.amount) 
        FROM public.commission_ledger cl 
        WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
    ), 0.0) AS pending_commission,
    COALESCE((
        SELECT SUM(sa.amount) 
        FROM public.salary_advances sa 
        WHERE sa.staff_id = s.id 
          AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
    ), 0.0) AS total_advance,
    -- Formula: (Base Salary + Pending Commission) - Total Advance
    GREATEST(
        (s.salary + COALESCE((
            SELECT SUM(cl.amount) 
            FROM public.commission_ledger cl 
            WHERE cl.staff_id = s.id AND cl.status = 'Pending'::public.commission_status
        ), 0.0)) - COALESCE((
            SELECT SUM(sa.amount) 
            FROM public.salary_advances sa 
            WHERE sa.staff_id = s.id 
              AND sa.status IN ('Approved'::public.advance_status, 'Given'::public.advance_status, 'Pending'::public.advance_status)
        ), 0.0), 
        0.0
    ) AS net_pending_salary
FROM public.staff s
WHERE NOT EXISTS (
    SELECT 1 FROM public.salary_drafts sd 
    WHERE sd.staff_id = s.id 
      AND sd.salary_month = to_char(now(), 'Month YYYY')
      AND sd.status = 'Paid'::public.draft_status
);

-- Grant View Access
GRANT SELECT ON public.vw_pending_salary_list TO anon, authenticated, service_role;
