-- =========================================================================
-- DATABASE CLEANUP: clear_gym_data.sql
-- Run this script in your Supabase SQL Editor to wipe out all gym, owner,
-- member, staff, and transaction data, while KEEPING subscription plans,
-- admin accounts, and version flags intact.
-- =========================================================================

BEGIN;

-- 1. Disable all triggers and constraints temporarily to allow safe deletion
SET session_replication_role = 'replica';

-- 2. Clear all gym-specific operational tables
TRUNCATE TABLE 
    public.attendance_audit_log,
    public.attendance,
    public.xp_history,
    public.member_badge_status,
    public.member_achievements,
    public.membership_payments,
    public.member_memberships,
    public.members,
    public.leave_requests,
    public.salary_advance_ledger,
    public.salary_payment_commissions,
    public.salary_payments,
    public.pt_assignments,
    public.pt_sessions,
    public.salaries,
    public.staff,
    public.diet_plans,
    public.workout_plans,
    public.expenses,
    public.finance_transactions,
    public.transactions,
    public.membership_plans,
    public.invitations,
    public.holidays,
    public.notifications,
    public.support_messages,
    public.support_tickets,
    public.duplicate_gym_alerts,
    public.renewal_logs,
    public.subscription_history,
    public.payments,
    public.invoices,
    public.subscriptions,
    public.user_gym_associations,
    public.gyms,
    public.admin_sessions,
    public.audit_logs,
    public.platform_payments
CASCADE;

-- 3. Delete non-admin profiles
DELETE FROM public.profiles 
WHERE id NOT IN (
    SELECT user_id FROM public.admin_users WHERE user_id IS NOT NULL
);

-- 4. Delete non-admin auth user accounts
DELETE FROM auth.users 
WHERE id NOT IN (
    SELECT user_id FROM public.admin_users WHERE user_id IS NOT NULL
);

-- 5. Delete orphaned auth identities & sessions (prevents 400 Gotrue errors on next login)
DELETE FROM auth.identities 
WHERE user_id NOT IN (SELECT id FROM auth.users);

DELETE FROM auth.sessions 
WHERE user_id NOT IN (SELECT id FROM auth.users);

-- 6. Restore triggers and constraints
SET session_replication_role = 'origin';

COMMIT;
