# Phase 08: Member & Staff Update Persistence (Supabase & Offline Sync), Diet Plan Viewer (Apex Gym Fix), and Release APK Build & Git Push

## Problem Description
1. **Member & Staff Detail Updates Disappear / Not Saving to Online Supabase Database**:
   - When gym owners or staff navigate to the Members tab, click on a member (or staff), and edit details (name, phone, email, notes, blood group, address, measurements, status, shift), the update was only saving to local memory or volatile local cache.
   - Upon closing and reopening the app, the changes vanished because:
     a) `saveMember` in `gym_repository.dart` was attempting a blind `upsert` with an incomplete data map (missing `email`, sending `membership_plan_id: ""` which triggered FK check violations on `member_memberships`, and falling back to a misconfigured queue).
     b) It caught errors silently (`catch (e) { print(...) }`) without notifying the UI, leading the UI to report success while the server rejected the operation.
     c) The `fn_on_member_plan_changed` trigger in Supabase tried to create `member_memberships` records even if `membership_plan_id` was empty or non-existent in `membership_plans`.
     d) The RLS policies on `members` and `staff` lacked support for direct member self-access and staff role access beyond `user_gym_associations`.
     e) When direct upsert failed, the CRUD queue stored it with `action: 'insert'` instead of `'update'`, causing subsequent background syncs to fail repeatedly until abandoned.
2. **Member Diet Screen - "View Diet Plan" Does Nothing / Apex Gym Members Cannot See Diet Plan**:
   - In `lib/features/member_app/screens/member_diet_screen.dart`, the "View Diet Plan" button had an empty handler: `onPressed: () {}`.
   - In `MemberAppViewModel`, only the plan title string was fetched, but full diet plan details (meals, macros, schedule) were never loaded or cached.
   - For Apex Premium GYM (`f896e071-c136-458a-842c-5e171b746f96`), active members have assigned diet plans in Supabase (`Weight Loss` and `Weight Gain` with comprehensive meal schedules), but members could never view them because the button was completely unlinked.
3. **Release APK Build & Git Push**:
   - Build a production release APK and place it in the workspace root folder as `Gym OS.apk`.
   - Push all code and planning commits to GitHub remote `origin/main`.

## Proposed Changes

### 1. Supabase Database Backend (`fix_member_staff_persistence_and_rls.sql`)
- **Fix Trigger `fn_on_member_plan_changed`**:
  - Add sanity check `IF NEW.membership_plan_id IS NOT NULL AND NEW.membership_plan_id <> '' AND NEW.membership_plan_id <> 'null' THEN`.
  - Check `IF FOUND THEN` before inserting into `member_memberships` so non-existent or invalid plan IDs do not trigger FK violations.
- **Update RLS Policies on `members` and `staff`**:
  - Ensure owners (via `user_gym_associations`), staff (via `staff` table user_id or `user_gym_associations`), and members themselves (via `user_id = auth.uid()`) can view and update records.

### 2. Gym Repository & ViewModel (`lib/core/repository/gym_repository.dart` & `members_viewmodel.dart` & `staff_viewmodel.dart`)
- **`saveMember`**:
  - Differentiate between INSERT (new member) and UPDATE (existing member `index >= 0`).
  - For UPDATE, call `SupabaseService.client.from('members').update(updateData).eq('id', member.id)` directly.
  - Include `email: member.email` in update/insert payload.
  - Sanitize `membership_plan_id`: set to `null` if empty or `'null'` to prevent FK errors.
  - If direct update throws an error, rethrow so UI can handle it or show error feedback, while queuing with `action: 'update'`.
  - Immediately reflect the updated record in local memory and cache so subsequent fetch operations retain changes.
- **`saveStaff`**:
  - Differentiate between INSERT and UPDATE.
  - For UPDATE, call `SupabaseService.client.from('staff').update(updateData).eq('id', staff.id)` directly.
  - Queue as `action: 'update'` if offline.

### 3. Member Diet Plan Detail View (`lib/features/member_app/`)
- **`MemberAppViewModel`**:
  - Load full `DietPlan` object for member's `assigned_diet_id`.
  - Fall back to gym's default diet plan if not assigned yet.
  - Cache to `SharedPreferences` for 0ms instant loading.
- **`MemberDietPlanDetailScreen`**:
  - Create a modern, aesthetic screen displaying the Diet Plan:
    - Macros hero card (Calories, Protein, Carbs, Fat) with visual tags.
    - Meal-by-meal schedule timeline (Morning, Breakfast, Mid-Morning, Lunch, Evening Snack, Dinner, Before Bed).
    - Meal timings and healthy food recommendations.
- **`member_diet_screen.dart`**:
  - Wire the "View Diet Plan" button to navigate to `MemberDietPlanDetailScreen`.

### 4. Build & Push
- Run `flutter build apk --release`.
- Copy generated APK to root folder as `Gym OS.apk`.
- Run `git add`, `git commit`, and `git push origin main`.

## Verification Plan
1. Test SQL migration on Supabase using `execute_sql`.
2. Run `flutter analyze` on modified files to ensure 0 errors.
3. Verify member and staff updates persist properly to Supabase.
4. Verify "View Diet Plan" renders meals for Apex Gym members and other gyms.
5. Verify `Gym OS.apk` is generated in root and git push is successful.
