# Phase 11: Granular Member Deletion & Smart Conflict-Free Restore

## Goal
Implement a multi-level soft deletion and smart restore system across the GymOS Mobile App and Super Admin Portal:
1. Allow gym owners to choose whether to delete **Profile Only** (keep finance ledger intact) or **All Data** (cascade delete finance + attendance).
2. Archive everything securely in `deleted_members` with zero permanent data loss on normal deletion.
3. Smart 1-click restore that detects existing financial transactions (re-links without duplicating amounts) or recreates missing ones.

## User Review Required
> [!IMPORTANT]
> - Normal deletion in both Mobile App and Admin Portal will now always archive to `deleted_members` table instead of hard deleting.
> - Only explicit "Wipe Permanently" from the Admin Deleted Archive will hard delete records.

## Proposed Steps

### Step 1: Database Migration (SQL & Supabase RPC)
- Enhance `deleted_members` table with `delete_scope` ('profile_only' | 'all') and `deleted_by_role`.
- Upgrade `admin_archive_delete_member(p_member_id UUID, p_gym_id UUID, p_delete_scope TEXT)`:
  - If `delete_scope = 'profile_only'`: Only delete from `members`; keep `finance_transactions`.
  - If `delete_scope = 'all'`: Backup and delete from `finance_transactions`, `attendance_logs`, `member_memberships`, and `members`.
- Upgrade `admin_restore_deleted_member(p_deleted_id UUID)`:
  - Restore member profile.
  - If financial transactions already exist in `finance_transactions`: Update `reference_id` to link to restored member (prevents double accounting).
  - If financial transactions are missing: Re-insert them.
  - Restore memberships & attendance logs.
  - Clean up archive row.

### Step 2: Mobile App (Owner Member Deletion Dialog & Repository)
- In `lib/core/repository/gym_repository.dart`: Call `admin_archive_delete_member` with selected scope.
- In `lib/features/members/member_profile_screen.dart`:
  - Show Radio/Checkbox dialog:
    - ⚪ **Delete Profile Only (Recommended)**: Retain revenue & payment history in gym ledger.
    - 🔴 **Delete Profile & All Associated Data**: Remove payments and attendance from active ledger.

### Step 3: Admin Web Dashboard & GitHub Push
- In `gymos_admin/lib/features/gyms/admin_gym_dashboard_screen.dart`:
  - Add scope choice when deleting from admin portal.
  - Show deletion scope badge in Deleted Archive grid.
  - Test and verify 1-click restore re-linking.
  - Compile web release and push to `GYMOS-ADMIN` GitHub repository.

## Verification
- Run database RPC tests for both `profile_only` and `all` scopes.
- Verify no duplicate transactions appear after restore.
- Verify GitHub sync.
