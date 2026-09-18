# Phase 04: Permanent Session Persistence & Prevention of Unexpected Logouts

## Phase Objective
Ensure users (Gym Owners, Staff, and Members) remain permanently logged in across app restarts, token expirations, and network fluctuations. Logout must ONLY happen if:
1. The user explicitly and manually clicks "Logout" in settings/profile.
2. The Gym Owner explicitly unlinks a Staff or Member account in Supabase (verified without false positives from network drops).

## Identified Root Causes
1. **Aggressive 3-Second Polling (`_checkUnlinkedStatus`)**: `MemberShell`, `StaffShell`, and `ReceptionistShell` ran an aggressive 3-second timer querying `authVm.forceLogoutIfUnlinked()`. Any transient network timeout or slow mobile connection caused `getUserGymAssociations()` to return `null` -> empty list -> treated as "unlinked by owner", wiping local storage and forcing logout.
2. **`SplashScreen` Routing Flaw**: If `currentSession` was expired (JWT expires in 1 hour) or null on cold start before background token refresh, the splash screen bypassed `_storage.isLoggedIn()` and redirected to `RoleSelectionScreen`. Also, any network exception in `_verifyAndRoute()` dropped into a generic catch block that kicked the user back to the login screen instead of routing to the cached dashboard.
3. **`onAuthStateChange` Triggering Data Wipe on `session == null`**: In `GymRepository` and `MemberAppViewModel`, `if (event == AuthChangeEvent.signedOut || session == null)` wiped all data and flipped `_isLoggedIn = false` during transient nulls or token rotation.
4. **`AuthViewModel` Constructor Overwriting Login State**: `_isLoggedIn` checked `currentSession != null` instead of trusting `_storage.isLoggedIn()`.
5. **Database `is_user_linked_to_gym` treating 'Expired' members as Unlinked**: The RPC required `status = 'Active'`; members with expired memberships were treated as unlinked and kicked out.
6. **Owners Subjected to Unlink Checks**: Gym Owners should never be checked for unlinking.

## Tasks

### Wave 1: Database RPC Hardening (Supabase)
- [x] Update `is_user_linked_to_gym(p_user_id, p_gym_id, p_role)` in SQL/migration:
  - For members: User is linked if `user_gym_associations` exists AND `members.user_id = p_user_id` (status can be 'Active', 'Expired', 'Inactive' etc. — only `user_id IS NULL` or missing association represents unlinked).
  - For staff: User is linked if `user_gym_associations` exists AND `staff.user_id = p_user_id`.
  - For owners: Always returns `TRUE`.
- [x] Apply SQL update via Supabase MCP / migration script.

### Wave 2: Core Auth & Session Persistence Hardening
- [x] In `lib/core/services/supabase_service.dart`:
  - Ensure `Supabase.initialize` enables automatic token refresh.
  - Add helper `ensureValidSession()` to attempt background session refresh or recovery when expired without throwing.
- [x] In `lib/features/authentication/auth_viewmodel.dart`:
  - In constructor: initialize `_isLoggedIn` from `_storage.isLoggedIn()`.
  - In `getUnlinkBlockReason()`:
    - Return `null` immediately if role is `owner`.
    - If network error / exception occurs, return `null` (DO NOT treat network failure as unlinked).
    - Only return unlinked if the server definitively and successfully confirms the user is unlinked (`is_user_linked_to_gym == false` or explicit 404 with verified internet connectivity).
- [x] In `lib/core/repository/gym_repository.dart`:
  - In `_authStateSubscription`: Only clear data when `event == AuthChangeEvent.signedOut` (DO NOT clear on `session == null` or token refresh).
- [x] In `lib/features/member_app/member_app_viewmodel.dart`:
  - In `_authStateSubscription`: Only clear data on `event == AuthChangeEvent.signedOut`.
  - Support `tokenRefreshed` and `initialSession` events to load data seamlessly.

### Wave 3: Splash Screen & Shell Protection
- [x] In `lib/features/authentication/splash_screen.dart`:
  - If `_storage.isLoggedIn()` is true OR `currentSession != null`: route to role dashboard even if offline or session refresh is in progress.
  - In `_verifyAndRoute()`: On network error / timeout, proceed to cached dashboard instead of throwing user to `RoleSelectionScreen`.
- [x] In `lib/core/services/unlink_guard.dart`:
  - Ensure unlink guard never triggers if user is an owner, and handles offline states cleanly.
- [x] In `lib/features/member_app/screens/member_shell.dart`, `lib/features/staff/portal/staff_shell.dart`, and `lib/features/receptionist/portal/receptionist_shell.dart`:
  - Remove aggressive 3-second `Timer.periodic`.
  - Replace with lifecycle check on app resume (`didChangeAppLifecycleState`) or relaxed periodic check (e.g. 5 minutes) with strict connectivity validation.

### Wave 4: Verification & Flutter Analyze
- [x] Run `flutter analyze` on modified files.
- [x] Test offline launch, session expiration recovery, and manual logout vs unlinking behavior.
