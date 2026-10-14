# Phase 35: Member Portal Workout Plan Sync, Multi-Split Display & Offline Architecture

## Context & Problem Diagnosis
During a deep architectural scan of the Member Portal workout subsystem (`member_app_viewmodel.dart`, `member_dashboard_screen.dart`, `member_training_screen.dart`, and `member_workout_plan_screen.dart`), the following critical bugs and disconnects were identified:

1. **False "Rest Day" on Home & Training Screens for Unassigned Members:**
   - **Root Cause:** In `member_app_viewmodel.dart:838-842`, when `_assignedWorkoutId.isEmpty`, the viewmodel unconditionally sets:
     ```dart
     _assignedWorkoutTitle = '';
     _todaySplits = ['Rest Day'];
     _todayMuscleGroup = 'Rest Day';
     ```
     This causes members without an assigned plan to see "Wednesday's Training: Rest Day" and "Rest day — recovery is part of training!" on work days, giving the false impression that today is an actual rest day rather than a missing plan assignment.
   - **Fix:** If no plan is assigned, display `"No Plan Assigned"` or fallback gracefully to the Gym's default/general workout routine, providing a CTA to request a workout plan from the trainer/owner.

2. **Multiple Splits (e.g. Chest Day + Bicep Day) Glitch & Rest Day Display:**
   - **Root Cause:** In `workout_plans`, owners configure multiple splits for a day as:
     `"Monday": [{"title": "Chest Day"}, {"title": "Bicep Day"}]`.
     While `member_app_viewmodel.dart:824` joins splits as `_todayMuscleGroup = _todaySplits.join(' + ')`, multiple components still check `muscle.contains('Rest')` or fail to match day names (case-sensitivity or localized weekdays). Furthermore, on app startup, offline boot, or throttled fetches, `member_app_viewmodel.dart:502` only had access to yesterday's single cached string `member_cached_today_muscle`, falling back to `Rest Day` whenever a new day started without a successful server hit.
   - **Fix:** Normalize schedule parsing, handle multi-split day labels cleanly ("Chest & Bicep Day"), and ensure `isRestDay` is strictly `true` ONLY when the schedule explicitly declares a Rest Day.

3. **"My Plan" Screen Complete Disconnect from Owner's Plan:**
   - **Root Cause:** When members tap "My Plan" in `member_training_screen.dart`, it opens `MemberWorkoutPlanScreen`. This screen only queries `member_weekly_schedule`, which is completely empty (`[]`). It **never** reads `workout_plans` or `assignedWorkoutId`!
   - As a result, it falls back to hardcoded static mockup days:
     - Mon: Chest & Triceps
     - Tue: Back & Biceps
     - Wed: Legs & Core ...
     Every single member in the gym sees the exact same hardcoded routine, completely ignoring what the gym owner assigned!
   - **Fix:** `MemberWorkoutPlanScreen` must prioritize the member's assigned `workout_plans` schedule. It should map the owner's 7-day schedule directly into Monday..Sunday slots (including multi-split titles and exercises). If a member customizes their plan, their personalized tweaks are stored as an overlay while retaining a "Reset to Owner's Plan" option.

4. **Missing 7-Day Offline Cache Architecture:**
   - **Root Cause:** Currently, the app only fetches today's split and saves a single string `member_cached_today_muscle`. It does not cache the full 7-day routine. Hence, every single day or app restart requires a server network request to Supabase to find out what today's workout is.
   - **Fix:** Cache the entire 7-day schedule map (`workout_plans.schedule`) in local `SharedPreferences`. The app computes today's workout dynamically from local cache using `DateTime.now().weekday` without hitting Supabase repeatedly. Background sync updates the cache whenever the plan ID or version changes.

---

## Tasks

### Task 1: Fix Member App Viewmodel Daily Workout Computation & Multi-Split Support
- **Target File:** `lib/features/member_app/member_app_viewmodel.dart`
- **Actions:**
  - Store full 7-day schedule in `_weeklyWorkoutSchedule` and cache under `'member_cached_workout_schedule_$_memberId'`.
  - Add helper `void _computeTodayWorkoutFromSchedule()` that reads the 7-day schedule for `DateTime.now()` (Monday..Sunday):
    - If `todayList` contains valid workouts, populate `_todaySplits` and `_todayMuscleGroup` (e.g., `"Chest & Bicep Day"`).
    - If `todayList` contains `"Rest Day"`, mark as Rest Day.
    - If no plan assigned, set `_todayMuscleGroup = 'No Plan Assigned'` and `_todaySplits = []`.
  - On app launch (`_loadCachedMemberData`), immediately run `_computeTodayWorkoutFromSchedule()` so offline users get the exact right workout for today without server requests.
  - In `fetchWorkoutPlanTask()`, fetch the plan from Supabase, update `_weeklyWorkoutSchedule`, cache the full JSON, and recompute today's splits.

### Task 2: Fix Home Dashboard & Training Screen Workout Cards
- **Target Files:**
  - `lib/features/member_app/screens/member_dashboard_screen.dart`
  - `lib/features/member_app/screens/member_training_screen.dart`
- **Actions:**
  - In `member_dashboard_screen.dart`:
    - Cleanly display single split or multi-splits (e.g. "Chest Day + Bicep Day" or "Chest & Bicep").
    - If no plan is assigned, display "No Workout Plan Assigned" with a polite subtitle ("Ask your trainer or gym owner to assign your personalized workout plan") instead of "Rest Day".
  - In `member_training_screen.dart`:
    - Ensure `muscle.contains('Rest')` is only true for genuine rest days, not unassigned plans.
    - Fix Guided Workout button and subtitle for multi-splits.

### Task 3: Overhaul "My Plan" Screen to Load Owner-Assigned Plan
- **Target File:** `lib/features/member_app/screens/member_workout_plan_screen.dart`
- **Actions:**
  - Read `assignedWorkoutId` and full schedule from `MemberAppViewModel` or local cache before falling back to defaults.
  - Map owner's days (`Monday`..`Sunday`) directly into day indices 1..7:
    - Set `muscle_group` to the title(s) defined by the owner (e.g. "Chest & Bicep Day").
    - Set `is_rest_day` to true if owner scheduled "Rest Day".
  - Support member customizations while maintaining an "Owner Plan" baseline and a "Restore Gym Plan" button.
  - Cache the resolved schedule in `SharedPreferences` so "My Plan" loads 100% offline with zero lag.

### Task 4: Realtime / Smart Cache Invalidation on Plan Update
- **Target Files:**
  - `lib/features/member_app/member_app_viewmodel.dart`
  - `lib/core/repository/gym_repository.dart`
- **Actions:**
  - When owner updates or assigns a workout plan in `GymRepository`, notify or trigger real-time update.
  - Member app checks `assigned_workout_id` on refresh: if changed, immediately pulls new plan and refreshes local cache.

---

## Verification Criteria
1. **Unassigned Member:** A member with no assigned workout sees "No Workout Plan Assigned" instead of "Rest Day".
2. **Multi-Split Day:** When an owner schedules e.g. "Chest Day" and "Bicep Day" on the same day, Member Home and Training screen display both splits clearly ("Chest & Bicep Day") without showing "Rest Day".
3. **"My Plan" Accuracy:** Navigating to "My Plan" displays the exact 7-day schedule assigned by the gym owner (Monday through Sunday), not static hardcoded defaults.
4. **Offline Resilience:** Disconnecting internet and changing system date advances today's workout dynamically from local cache with zero server errors.
