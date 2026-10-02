# Phase 19: Multi-Role Same-Account Persistence and Profile Switching

## Goal
Fix the issue where accounts with multiple roles on the same email (e.g., both Gym Owner and Gym Member) automatically switch to the Member profile after closing and reopening the app or after token refresh. Ensure rock-solid role persistence, deterministic active association restoration, and seamless profile switching.

---

## Root Cause Analysis

1. **`MemberAppViewModel` Session Hijack on Token Refresh / Initial Session**:
   - `MemberAppViewModel` has a constructor listener:
     ```dart
     SupabaseService.client.auth.onAuthStateChange.listen(...)
     ```
     Whenever `AuthChangeEvent.tokenRefreshed` (which Supabase triggers periodically every hour) or `AuthChangeEvent.initialSession` fires, it calls `loadMemberDataFromSupabase()`.
   - In `loadMemberDataFromSupabase()` (lines 828-834):
     ```dart
     await prefs.setString('gymos_user_role', 'member');
     if (gymId != null) {
       await prefs.setString('gymos_gym_info', jsonEncode({'id': gymId, 'name': _gymName}));
     }
     ```
     This unconditionally overwrites the active role to `'member'` and gym info to the member's gym in `SharedPreferences`, completely wiping out the owner session without any user interaction!

2. **Fragile Association Restoration in `AuthViewModel.loadCurrentProfile()`**:
   - When the app is closed and reopened, `loadCurrentProfile()` tries to match the saved session using `savedGym['id']` and `savedRole`.
   - There was no unique `active_association_id` stored in `LocalStorageService`.
   - If `matchedAssoc == null`, line 800 fell back to `_userAssociations.first`, which was often the member association if it was returned first by Supabase.
   - It then immediately called `await _storage.setUserRole(_selectedRole!)`, permanently overwriting the stored role to member.

3. **`GymSwitcherBottomSheet` Hiding Cross-Role Profiles**:
   - In `GymSwitcherBottomSheet.build()`:
     ```dart
     final associations = authVm.userAssociations.where((assoc) {
       if (activeRole == null) return true;
       return assoc.role == activeRole;
     }).toList();
     ```
     This filtered out any association that didn't match the current role. If logged in as an Owner, the user's Member profile was hidden, preventing manual profile switching.

---

## Implementation Plan

### Wave 1: Prevent `MemberAppViewModel` from Overwriting Active Role & Gym Info
- **Target File**: `lib/features/member_app/member_app_viewmodel.dart`
- In `MemberAppViewModel()` constructor:
  - Check the active role in `SharedPreferences` before triggering `loadMemberDataFromSupabase()` on `onAuthStateChange`.
  - If the active role is `owner` or `staff`, DO NOT call `loadMemberDataFromSupabase()` in the background on auth events.
- In `loadMemberDataFromSupabase()`:
  - Only write `gymos_user_role` and `gymos_gym_info` to `prefs` IF the currently active role is explicitly `member` or empty.
  - Never overwrite an active `owner` or `staff` session.

### Wave 2: Deterministic Active Association Persistence in `AuthViewModel` & `LocalStorageService`
- **Target Files**:
  - `lib/core/services/local_storage.dart`
  - `lib/features/authentication/auth_viewmodel.dart`
- In `LocalStorageService`:
  - Add `keyActiveAssociationId = 'gymos_active_association_id'`.
  - Add `getActiveAssociationId()` and `setActiveAssociationId(String id)`.
- In `AuthViewModel.selectAssociation(UserGymAssociation assoc)`:
  - Persist `assoc.id` via `_storage.setActiveAssociationId(assoc.id)`.
  - Persist `assoc.role.name` and gym info.
- In `AuthViewModel.loadCurrentProfile()`:
  - Prioritize matching by `savedAssocId` first:
    `matchedAssoc = _userAssociations.firstWhereOrNull((a) => a.id == savedAssocId)`.
  - If null, match by `savedGym['id']` AND `savedRole`.
  - If null, match by `savedRole` alone.
  - If still null and `_userAssociations.length > 1`, DO NOT arbitrarily pick `_userAssociations.first`. Instead, leave `_activeAssociation = null` so the app routes cleanly to `GymRoleSelectorScreen`.
  - When `matchedAssoc` is resolved, save `setActiveAssociationId(assoc.id)` and `setUserRole(assoc.role.name)`.

### Wave 3: Enable Multi-Role Switching in `GymSwitcherBottomSheet`
- **Target File**: `lib/features/dashboard/gym_switcher_bottom_sheet.dart`
- In `GymSwitcherBottomSheet.build()`:
  - Remove the `assoc.role == activeRole` filter so that all valid associations (Owner, Staff, Member) appear in "My Profiles".
  - Ensure the active association has a distinct badge or checkmark indicator.
  - Confirm switching to a different role reloads the respective ViewModel state and routes cleanly.

### Wave 4: Validation & Quality Gate
- Run `flutter analyze` to ensure zero compilation or type errors.
- Verify simulated role persistence:
  - Owner login -> stores owner role and association ID.
  - Token refresh simulation -> `MemberAppViewModel` does not corrupt stored role.
  - App reopen simulation -> `loadCurrentProfile` restores exact owner association.
  - Multi-profile switcher allows switching between Owner and Member profiles seamlessly.
