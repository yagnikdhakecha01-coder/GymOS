# Phase 34: Database Persistence Audit & Fixes (Owner & Staff Dashboards)

## Context & Audit Summary
During a rigorous line-by-line audit of the GymOS application focusing on the **Owner Dashboard** and **Staff/Receptionist Portals**, several areas were uncovered where user input or mutations either fail to reach Supabase database tables or fall back to local-only persistence:

1. **Gym Information (`gym_info_screen.dart` & `gym_settings_viewmodel.dart`):**
   - **Flaw:** Updating Gym Name, Phone, Email, Address, Timing, and Weekly Off only writes to local `SharedPreferences` via `AuthViewModel.setGymInfo()`. It never executes an `UPDATE` on the Supabase `gyms` table.
   - **Fix:** Update `GymSettingsViewModel.saveGymInfo()` to execute `SupabaseService.client.from('gyms').update({...}).eq('id', gymId)` and sync local preferences.

2. **Staff Roles Upsert (`gym_repository.dart` & `staff_roles_screen.dart`):**
   - **Flaw:** `saveStaffRoles()` executes `SupabaseService.client.from('staff_roles').upsert(roles)`. Supabase table `staff_roles` has a unique constraint `uniq_gym_role_name (gym_id, role_name)`. Without `onConflict: 'gym_id, role_name'`, PostgREST defaults to conflicting on `id`, triggering unique violation error `23505` when saving default roles without an existing UUID.
   - **Fix:** Add `onConflict: 'gym_id, role_name'` to the upsert call.

3. **Broadcast Announcement Deletion Sync (`announcements_service.dart` & `broadcast_screen.dart`):**
   - **Flaw:** In `BroadcastScreen`, new announcements are given a local ID `ann_${timestamp}`. When inserted into Supabase `announcements`, the `id` field is omitted, prompting Postgres to generate a UUID. When `AnnouncementsService.deleteAnnouncement(ann.id)` runs, it searches by the local string ID (`ann_...`), which matches 0 rows in Supabase.
   - **Fix:** Pass a valid UUID in `insert()` or capture and update the newly generated UUID in the announcement object so deletes target the correct database row.

4. **Receptionist Broadcast Dialog (`receptionist_dashboard_screen.dart`):**
   - **Flaw:** In `_showBroadcastDialog`, clicking "Send" only executes `vm.logActivity('Broadcast Sent: $msg', 'more')` and shows a SnackBar. It never inserts a row into `announcements` or `notifications`.
   - **Fix:** Wire `_showBroadcastDialog` to call `AnnouncementsService.addAnnouncement` so broadcasts reach both the database and members/staff.

5. **Staff Screen Hardcoded Join Date (`staff_screen.dart`):**
   - **Flaw:** Creating a staff member via the bottom sheet sets `joinDate: '16 Jul 2026'` statically.
   - **Fix:** Set `joinDate` to today's date formatted as `dd MMM yyyy` dynamically.

6. **Diet Plan Error Feedback (`diet_detail_screen.dart`):**
   - **Flaw:** `dietVm.saveDiet(newPlan)` returns a database error string if Supabase fails, but `diet_detail_screen.dart` ignores the return value and displays `SaveSuccessScreen`.
   - **Fix:** Check the returned error and display an error alert if the database save fails.

---

## Tasks

### Task 1: Fix Gym Information Persistence to Supabase
- **Target Files:**
  - `lib/features/gym_settings/gym_settings_viewmodel.dart`
  - `lib/features/gym_settings/gym_info_screen.dart`
- **Actions:**
  - In `gym_settings_viewmodel.dart`, convert `saveGymInfo` to `Future<bool> saveGymInfo(...)`.
  - Update `gyms` table in Supabase:
    ```dart
    final gymId = _authViewModel.activeAssociation?.gymId ?? _authViewModel.gymInfo?['id'];
    if (gymId != null && SupabaseService.isInitialized) {
      await SupabaseService.client.from('gyms').update({
        'name': name,
        'gym_name': name,
        'phone_number': phone,
        'email': email,
        'address': address,
        'logo_url': logo,
      }).eq('id', gymId);
    }
    ```
  - Also update and cache local info.
  - In `gym_info_screen.dart`, await `saveGymInfo` with error handling.

### Task 2: Fix Staff Roles Upsert Constraint
- **Target Files:**
  - `lib/core/repository/gym_repository.dart`
- **Actions:**
  - In `saveStaffRoles`:
    ```dart
    await SupabaseService.client
        .from('staff_roles')
        .upsert(roles, onConflict: 'gym_id, role_name');
    ```

### Task 3: Fix Broadcast Announcement ID Sync & Deletion
- **Target Files:**
  - `lib/core/services/announcements_service.dart`
  - `lib/features/dashboard/broadcast_screen.dart`
- **Actions:**
  - In `announcements_service.dart`: When inserting into `announcements`, generate a valid UUID v4 for the announcement, insert it, and save the ID.
  - Ensure `deleteAnnouncement` successfully removes the row from Supabase.

### Task 4: Connect Receptionist Broadcast to Supabase
- **Target Files:**
  - `lib/features/receptionist/portal/receptionist_dashboard_screen.dart`
- **Actions:**
  - In `_showBroadcastDialog`, call `AnnouncementsService.addAnnouncement(...)` with the active gym ID so announcements are saved in `announcements` and notifications fan out to members.

### Task 5: Dynamic Join Date for Quick Staff Creation
- **Target Files:**
  - `lib/features/staff/staff_screen.dart`
- **Actions:**
  - Replace `'16 Jul 2026'` with `DateFormat('dd MMM yyyy').format(DateTime.now())`.

### Task 6: Error Handling for Diet Plan Database Save
- **Target Files:**
  - `lib/features/diet/diet_detail_screen.dart`
- **Actions:**
  - Check the returned error from `dietVm.saveDiet(newPlan)` and notify user if Supabase persistence failed.

---

## Verification Criteria
1. Changing Gym Information in Owner Settings persists to Supabase `gyms` table and reloads correctly on fresh app start.
2. Saving staff roles in Gym Settings does not fail on unique constraint `uniq_gym_role_name`.
3. Broadcast announcements created by Owner and Receptionist are stored in Supabase `announcements` and can be deleted cleanly.
4. Newly created staff members reflect today's join date.
5. `flutter analyze` passes with 0 errors.
