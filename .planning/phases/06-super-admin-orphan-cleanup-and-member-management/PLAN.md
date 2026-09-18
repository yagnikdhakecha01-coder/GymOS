# Phase 06: Super Admin Orphan Cleanup, Unlinked Entries Tab, Members & Staff Visibility Fix, and Owner-Level Member Management with Strong RLS

## Problem Description
1. **Apex Premium GYM Orphan Financial Entry**:
   - In Apex Premium GYM, member `e8ec1892-029c-4278-8aee-35c8dd470289` was deleted, but an automatic initial payment of ₹2,000 (`d8dbf320-246f-45bd-ae1f-f7420ef0ab43`) remained in `finance_transactions`.
2. **Super Admin "Unlinked Entries" Tab Needed**:
   - The Super Admin portal needs a dedicated tab in the gym dashboard to inspect any orphaned/unlinked financial transactions whose `reference_id` belongs to a deleted member, and provide a "Delete Everywhere" action that cascade-cleans all traces across tables.
3. **Members Not Showing in Super Admin Portal**:
   - In `AdminGymDashboardScreen`, `_loadMembersData()` queried `.select('*, member_memberships(membership_plans(name))')`.
   - `membership_plans` has column `title`, NOT `name`, causing a PostgREST 400 Bad Request error.
   - `member_memberships` table RLS lacked a policy for `is_super_admin(auth.uid())`.
   - Field mappings assumed `full_name`, `phone_number`, `avatar_url` instead of `name`, `phone`, `avatar`.
4. **Staff List Visibility & Empty State**:
   - In `_loadStaffData()`, staff query and card styling need to cleanly display role, phone, salary, avatar, and handle gyms with no staff gracefully.
5. **Interactive Member Cards with Owner-Level Capabilities & Strong RLS**:
   - Super Admin needs to click on member cards to view all member profile details, membership details, payment breakdown, attendance/payment history, and perform owner-level operations (edit member, record payment, delete member).
   - Strict security: Only authenticated super admins/admins should have access; normal users and members remain restricted by strong RLS.

## Tasks

### Task 1: Supabase Backend - Delete Apex Orphan Entry, Add Cleanup RPC & Strong RLS
- Delete orphan transaction `d8dbf320-246f-45bd-ae1f-f7420ef0ab43`.
- Create `admin_delete_unlinked_entry(p_tx_id uuid, p_gym_id uuid, p_ref_id text)` with `SECURITY DEFINER` and strict `is_super_admin(auth.uid()) OR is_admin(auth.uid())` check.
- Add `super_admin_all_member_memberships` RLS policy to `member_memberships`.
- Add `super_admin_all_membership_payments` and `super_admin_all_attendance_logs` policies if missing.

### Task 2: Fix Members & Staff Tab Loading in `gymos_admin`
- In `gymos_admin/lib/features/gyms/admin_gym_dashboard_screen.dart`:
  - Fix `_loadMembersData()`: fetch `members` with `.select('*')` and map `membership_plans` by ID to `title`.
  - Fix field mappings (`name`, `phone`, `avatar`, `status`, `payment_status`, `pending_amount`).
  - Fix `_loadStaffData()`: fetch `staff` directly with `.select('*')` and map fields properly.
  - Provide polished empty states for both tabs.

### Task 3: Implement "Unlinked Entries" Tab in Super Admin
- Add 4th tab: "Unlinked Entries" with broken-link icon.
- Detect orphaned entries in `finance_transactions` where `category = 'Membership'` and `reference_id` is missing from `members`.
- Display details: Amount, date, method, reference ID, notes.
- Implement "Delete Everywhere" button calling `admin_delete_unlinked_entry`.

### Task 4: Interactive Member Card & Owner-Level Management Dialog
- Make member cards clickable.
- Open comprehensive dialog showing:
  - Full personal info, membership plan info, duration, payment balance, notes, medical details.
  - Recent attendance & transaction history.
  - Owner Actions: Edit Member, Record/Collect Payment, Delete Member.
- Guard all actions so they run with Super Admin authority and enforce strict error handling.

## Verification Plan
- Supabase SQL verification via MCP tool.
- Run `flutter analyze` in `gymos_admin/`.
- Verify UI and tabs in browser.
