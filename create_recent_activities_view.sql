-- ====================================================
-- GYMOS - CREATE RECENT ACTIVITIES UNION VIEW
-- ====================================================

CREATE OR REPLACE VIEW public.vw_recent_activities AS
-- 1. Membership Payments
SELECT 
    p.id::text AS id,
    p.gym_id AS gym_id,
    'Payment' AS activity_type,
    'Payment Received' AS title,
    CONCAT('Received ₹', p.amount, ' from ', m.name) AS description,
    p.created_at AS created_at
FROM public.membership_payments p
JOIN public.member_memberships mm ON p.member_membership_id = mm.id
JOIN public.members m ON mm.member_id = m.id

UNION ALL

-- 2. Salary Advances
SELECT 
    sa.id::text AS id,
    sa.gym_id AS gym_id,
    'Advance' AS activity_type,
    'Salary Advance' AS title,
    CONCAT('Salary advance of ₹', sa.advance_amount, ' for ', s.name, ' is ', sa.status) AS description,
    sa.created_at AS created_at
FROM public.salary_advance_ledger sa
JOIN public.staff s ON sa.staff_id = s.id

UNION ALL

-- 3. Leave Requests
SELECT 
    lr.id::text AS id,
    lr.gym_id AS gym_id,
    'Leave' AS activity_type,
    'Leave Request' AS title,
    CONCAT('Leave request for ', s.name, ' is ', lr.status) AS description,
    lr.created_at AS created_at
FROM public.leave_requests lr
JOIN public.staff s ON lr.staff_id = s.id

UNION ALL

-- 4. Membership Renewals
SELECT 
    mm.id::text AS id,
    mm.gym_id AS gym_id,
    'Membership' AS activity_type,
    'Membership Renewed' AS title,
    CONCAT(m.name, ' renewed plan: ', mp.title) AS description,
    mm.created_at AS created_at
FROM public.member_memberships mm
JOIN public.members m ON mm.member_id = m.id
JOIN public.membership_plans mp ON mm.plan_id = mp.id

UNION ALL

-- 5. General Expenses (Direct, excluding salary recoveries)
SELECT 
    ft.id::text AS id,
    ft.gym_id AS gym_id,
    'Expense' AS activity_type,
    'Expense Logged' AS title,
    CONCAT(ft.category, COALESCE(': ' || ft.notes, ''), ' of ₹', ft.amount) AS description,
    ft.created_at AS created_at
FROM public.finance_transactions ft
WHERE ft.type = 'Expense' AND ft.category <> 'Salary';

-- Grant permissions to view
GRANT SELECT ON public.vw_recent_activities TO anon, authenticated, service_role;
