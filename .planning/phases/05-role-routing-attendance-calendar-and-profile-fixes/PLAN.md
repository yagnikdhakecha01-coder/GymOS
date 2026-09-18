# Phase 05: Role Routing, Attendance Calendar & Profile Fixes

## Problem Description
1. **Role Routing Misdirection**:
   - A user logging in with an email linked to staff who chooses "Gym Member" on the role selection screen is mistakenly routed into the Staff portal because `authVm.login` blindly sets `_selectedRole = assoc.role.name` when `_userAssociations.length == 1`.
   - The app must honor the user's selected role (`selectedRole`). If no association/profile exists for that selected role, route to `MemberCodeScreen()` for Member/Staff or `FirstTimeSetupScreen()` for Owner so the user can connect via invitation code.
2. **Attendance History Calendar Auto-Back / Pop Bug**:
   - In Staff Attendance -> View History, clicking next/previous month on the calendar triggers `repo.fetchAttendanceLogsFromSupabase()`, which calls `notifyListeners()`.
   - `_onRepoUpdated()` and `_checkCurrentStatus()` in `staff_attendance_screen.dart` do not exempt `AttendanceState.history`, immediately overriding `_currentState` to `notCheckedIn` or `checkedIn`.
   - Additionally, background timers calling listeners every ~30s cause an auto-back even when idle.
3. **Staff Profile Department Accuracy**:
   - In `staff_more_screen.dart`, when `matchingStaff` is empty, it falls back to `staffVm.allStaff.first`, displaying random staff member information.
   - Also, `Staff.fromJson` defaulted missing department to `'Training'`.
4. **Member Body Stats Blanking vs Default Guessing**:
   - In `member_app_viewmodel.dart`, `_weight = '76 kg'`, `_height = '178 cm'`, `_bodyFat = '14.5%'` are hardcoded default initial values.
   - If the gym owner leaves weight and height blank when creating or managing a member, they must remain blank (`''` / display `'—'`), allowing the member to manually enter them later.

## Tasks

### Task 1: Enforce Selected Role & Missing Profile Code Screen Fallback
- In `lib/features/authentication/auth_viewmodel.dart`:
  - When setting active association in `login()`, filter `_userAssociations` by `_selectedRole`.
  - If a matching association exists for the selected role: activate it.
  - If no matching association exists for the selected role: keep `_selectedRole`, set `_activeAssociation = null`, and update `_currentProfile` accordingly.
- In `lib/features/authentication/login_screen.dart`:
  - In `_navigateToRoleDashboard`:
    - Filter `authVm.userAssociations` by `authVm.selectedRole`.
    - If empty: route `owner` to `FirstTimeSetupScreen()` and `member`/`staff` to `MemberCodeScreen()`.
    - If 1 match: select that association and route to dashboard.
    - If > 1 matches: route to `GymRoleSelectorScreen()`.

### Task 2: Fix Attendance Calendar Auto-Back & Background Pop
- In `lib/features/attendance/staff_attendance_screen.dart`:
  - Add `_currentState == AttendanceState.history` guard in `_onRepoUpdated()`.
  - Add `_currentState == AttendanceState.history` guard in `_checkCurrentStatus()`.
  - Wrap scaffold with `PopScope` to handle Android back gesture when viewing history to return to `notCheckedIn` state instead of popping the shell.

### Task 3: Fix Staff Profile Department Accuracy
- In `lib/features/staff/portal/staff_more_screen.dart`:
  - Lookup staff using `authVm.staffRecord` or matching by `userId == profileUserId || id == profileUserId || email == authVm.currentUser?.email`.
  - Eliminate fallback to `staffVm.allStaff.first`.
  - If department is empty, display `'—'`.
- In `lib/core/models/staff.dart`:
  - In `Staff.fromJson`, parse `department: (json['department'] as String?)?.trim() ?? ''`.

### Task 4: Fix Member Body Stats Blank Handling
- In `lib/features/member_app/member_app_viewmodel.dart`:
  - Initialize `_weight = ''`, `_height = ''`, `_bodyFat = ''`, `_fitnessGoal = ''`.
  - In `loadMemberDataFromSupabase()`: If `extra['weight']` / `height` are empty/null and no `member_body_logs` record exists, set them to empty string `''`.
- In `lib/features/member_app/screens/member_profile_screen.dart`:
  - Display `'—'` when `weight`, `height`, or `bodyFat` are empty.

## Verification Plan
- Static analysis with `flutter analyze` on modified files.
- Manual test flows verified across role switching, calendar navigation, staff department resolution, and member body stats display.
