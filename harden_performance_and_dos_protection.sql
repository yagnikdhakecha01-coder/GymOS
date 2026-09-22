-- =============================================================================
-- GYMOS SECURITY HARDENING: PART 2 - ANTI-CRASH & ANTI-DOS ENGINE
-- PURPOSE: Prevent database crashes, CPU 100% locks, memory starvation,
--          and connection pool exhaustion.
-- SAFETY GUARANTEE: ZERO data modified. 100% non-destructive performance boost.
-- =============================================================================

BEGIN;

-- 1. DEFENSIVE SERVER TIMEOUTS (CRASH & HANG PREVENTION)
-- If a malicious actor or a poorly optimized query tries to scan 1,000,000 rows,
-- Postgres will cancel the query before the CPU pegs at 100% or takes down other users.

-- Set 10-second statement timeout for authenticated role (normal app traffic should complete in < 200ms)
ALTER ROLE authenticated SET statement_timeout = '10000'; -- 10 seconds

-- Set 5-second statement timeout for anon role (unauthenticated requests should be instant)
ALTER ROLE anon SET statement_timeout = '5000'; -- 5 seconds

-- Automatically terminate idle transactions that hold table locks for > 30 seconds
ALTER ROLE authenticated SET idle_in_transaction_session_timeout = '30000'; -- 30 seconds
ALTER ROLE anon SET idle_in_transaction_session_timeout = '10000'; -- 10 seconds

-- Set lock timeout to 5 seconds to prevent cascading deadlocks
ALTER ROLE authenticated SET lock_timeout = '5000'; -- 5 seconds
ALTER ROLE anon SET lock_timeout = '3000'; -- 3 seconds


-- 2. CRITICAL B-TREE INDEXES FOR ANTI-DOS & INSTANT TENANT ISOLATION
-- Without indexes, queries like `WHERE gym_id = ...` do a Full Table Scan (Seq Scan),
-- which burns 100% CPU when data grows. These indexes ensure O(log N) microsecond lookups.

-- Members table indexes
CREATE INDEX IF NOT EXISTS idx_members_gym_id ON public.members (gym_id);
CREATE INDEX IF NOT EXISTS idx_members_gym_status ON public.members (gym_id, status);
CREATE INDEX IF NOT EXISTS idx_members_gym_phone ON public.members (gym_id, phone);
CREATE INDEX IF NOT EXISTS idx_members_user_id ON public.members (user_id);

-- Attendance table indexes (Most frequent high-volume writes & reads)
CREATE INDEX IF NOT EXISTS idx_attendance_gym_id ON public.attendance (gym_id);
CREATE INDEX IF NOT EXISTS idx_attendance_gym_date ON public.attendance (gym_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_member_date ON public.attendance (member_id, date DESC);

-- Staff table indexes
CREATE INDEX IF NOT EXISTS idx_staff_gym_id ON public.staff (gym_id);
CREATE INDEX IF NOT EXISTS idx_staff_gym_user ON public.staff (gym_id, user_id);
CREATE INDEX IF NOT EXISTS idx_staff_gym_status ON public.staff (gym_id, status);

-- User Gym Associations (CRUCIAL for RLS Policy evaluation speed on every query)
CREATE INDEX IF NOT EXISTS idx_user_gym_associations_user_id ON public.user_gym_associations (user_id);
CREATE INDEX IF NOT EXISTS idx_user_gym_associations_gym_id ON public.user_gym_associations (gym_id);
CREATE INDEX IF NOT EXISTS idx_user_gym_associations_composite ON public.user_gym_associations (user_id, gym_id);

-- Finance Transactions (Ledger lookup acceleration)
CREATE INDEX IF NOT EXISTS idx_finance_gym_date ON public.finance_transactions (gym_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_finance_gym_type ON public.finance_transactions (gym_id, transaction_type);

-- Subscriptions table
CREATE INDEX IF NOT EXISTS idx_subscriptions_gym_id ON public.subscriptions (gym_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions (status);

-- Activity & Audit Logs
CREATE INDEX IF NOT EXISTS idx_activity_logs_gym_date ON public.activity_logs (gym_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_gym_date ON public.attendance_audit_log (gym_id, created_at DESC);

-- Salary & Advances
CREATE INDEX IF NOT EXISTS idx_salaries_gym_month ON public.salaries (gym_id, month_year);
CREATE INDEX IF NOT EXISTS idx_salary_advance_gym ON public.salary_advance_ledger (gym_id);

-- Membership Plans
CREATE INDEX IF NOT EXISTS idx_membership_plans_gym_active ON public.membership_plans (gym_id, is_active);

COMMIT;
