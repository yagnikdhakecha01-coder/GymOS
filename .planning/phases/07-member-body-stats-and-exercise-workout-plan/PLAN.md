# Phase 07: Member Portal - Body Stats Overhaul (Goal-First, Once-Per-Day, RLS & Cache) & Exercise Workout Plan System (1RM Removal, Routine Builder, Today's Day Sync)

## Problem Description
1. **Body Stats Goal Placement & First-Time Flow**:
   - Currently, goal setting is buried at the very bottom of the log form and defaults to a hardcoded 75kg in `SharedPreferences`.
   - Member needs a goal-first workflow: When opening Body Stats for the first time without a goal, an onboarding goal modal must appear immediately.
   - The Goal Card must reside at the very TOP of the screen, clearly showing the member's target weight, goal type (Weight Loss / Muscle Gain / Maintenance), and current progress.
   - Logging stats must be unlocked only after setting a goal.
2. **Once-Per-Day Logging Constraint**:
   - Members should only log body stats once per day.
   - If today's stats are already logged, the UI must show today's logged values and offer an "Edit Today's Stats" mode instead of inserting duplicate rows.
3. **Database Persistence, Full RLS & Offline-Fast Caching**:
   - `member_fitness_goals` and `member_body_logs` must have rock-solid Supabase RLS policies with explicit `WITH CHECK` clauses for `member_id IN (SELECT id FROM members WHERE user_id = auth.uid())` and gym staff/owner access.
   - Local caching via `SharedPreferences` ensures instant 0ms screen loading, followed by smooth background synchronization.
4. **Exercises UI Cleanup**:
   - Remove lone emoji placeholders in `_OpenGymExerciseDetailSheet` (e.g. bare `🏋️` on image/gif load failure) and replace with modern styled icons.
   - Remove the `Estimated 1RM Calculator` container, formula calculation, and steppers completely as requested.
5. **Real "Add to My Plan" & "My Workout Plan" Routine System**:
   - "Add to my plan" previously only showed a dummy snackbar. It must allow members to pick a day of the week (Monday - Sunday / Today), set target sets & reps, and save to `member_weekly_schedule` (`exercises` JSONB) both locally and in Supabase.
   - A dedicated "My Workout Plan" screen displays the member's customized 7-day routine, current day highlight, and scheduled exercises with delete/reorder capability.
6. **Dashboard Today's Day & Muscle Group Synchronization**:
   - On `MemberDashboardScreen` (Today's Training card) and `MemberTrainingScreen`, navigating to Exercises must pass today's scheduled muscle group (e.g. "Chest", "Chest & Back", "Legs").
   - `MemberExerciseLibraryScreen` must automatically pre-filter and display today's exercises matching the day's routine, with a banner to reset or browse all.

## Implementation Tasks

### Task 1: Supabase Backend - Schema Updates & Strong RLS Policies
- File: `supabase_member_features_migration.sql` / DB Migration
- Add `exercises JSONB DEFAULT '[]'::jsonb` to `member_weekly_schedule`.
- Add `goal_type TEXT DEFAULT 'Weight Loss'` to `member_fitness_goals`.
- Update RLS policies for `member_body_logs`, `member_fitness_goals`, and `member_weekly_schedule` with explicit `WITH CHECK` conditions ensuring authenticated members can seamlessly insert and update their own records.

### Task 2: Body Stats Screen Overhaul (`member_body_stats_screen.dart`)
- Position the Fitness Goal card at the TOP of the screen (showing Goal Weight, Goal Type, Remaining kg, and "Edit Goal" action).
- First-time flow: if no goal is set (`_goalWeight <= 0`), immediately prompt the Goal Setup dialog on initial screen load.
- Guard logging: Stats logging form is enabled only once a goal exists.
- Once-per-day enforcement: Detect if today's date (`yyyy-MM-dd`) is already logged. If so, display a clean "Logged Today" card with an "Edit Today's Stats" action.
- Local cache first (`SharedPreferences`), background Supabase sync with conflict handling on `(member_id, logged_date)`.

### Task 3: Exercise Library Clean Up & 1RM Removal (`member_exercise_library_screen.dart`)
- Remove the `Estimated 1RM Calculator` widget, steppers, and Epley calculation.
- Replace bare emoji fallbacks (e.g., `Text('🏋️')`) with clean `Icon(Icons.fitness_center_rounded)` inside a styled card container.
- Accept optional `initialMuscleGroup` parameter to automatically filter the library when launched from Dashboard or Today's Training.
- Add a filter header banner: "Showing exercises for Today: [Muscle Group]" with a "View All" button.

### Task 4: Workout Plan Engine & "Add to My Plan" Integration
- Implement `MemberWorkoutPlanScreen` (or sheet) showing the 7-day schedule (Mon-Sun), highlighting today's workout, listing planned exercises with sets & reps.
- Wire "Add to my plan" button in `_OpenGymExerciseDetailSheet` and list items to open a Day & Sets/Reps selector, persisting to `member_weekly_schedule` in Supabase & local cache.
- Expose "My Workout Plan" from `MemberTrainingScreen` and `MemberExerciseLibraryScreen`.

### Task 5: Dashboard & Today's Training Dynamic Linkage
- In `member_app_viewmodel.dart`: Load today's muscle group from `member_weekly_schedule` (custom schedule) or assigned workout plan.
- In `member_dashboard_screen.dart` and `member_training_screen.dart`: When tapping Exercises or Today's exercises, route to `MemberExerciseLibraryScreen(initialMuscleGroup: vm.todayMuscleGroup)`.

## Verification Plan
- Supabase SQL execution via MCP tool and RLS policy verification.
- Run `flutter analyze` across `lib/features/member_app/` to ensure 0 errors/warnings.
- Manual/flow verification of:
  - First-time goal prompt and top card placement.
  - Same-day log restriction and edit mode.
  - 1RM calculator removal and placeholder icon rendering.
  - Adding exercise to a day and verifying it in "My Workout Plan".
  - Opening Exercises from dashboard and seeing today's muscle group pre-filtered.
