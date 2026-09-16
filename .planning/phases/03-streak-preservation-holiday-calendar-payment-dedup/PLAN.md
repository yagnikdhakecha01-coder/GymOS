# Phase 03: Rest Day & Holiday Streak Preservation, Calendar Holidays & Payment History Deduplication

## Phase Objective
Ensure member attendance streaks are preserved across Workout Plan Rest Days, declared Gym Holidays, and Sundays; guarantee Sundays and Holidays are properly marked in attendance calendars; protect staff from late/absent entries on off-days; and eliminate duplicate payment history records in the Member App's "My Membership" screen.

## Tasks

### Wave 1: Database Logic & Deduplication (Supabase MCP)
- [ ] Create `fn_is_member_excused_day(p_gym_id, p_assigned_workout_id, p_date)` helper function.
- [ ] Upgrade `get_member_attendance_streak_v1(p_user_id)` to calculate active streak backward skipping excused days (Sundays, gym holidays, workout plan rest days) without resetting to 0 when today is in progress or on an off-day.
- [ ] Upgrade `process_qr_attendance` to mark staff as Present (with late_minutes = 0) on Sundays and Gym Holidays.
- [ ] Deduplicate `membership_payments` rows in Supabase.

### Wave 2: Member App Logic & Payment History Deduplication
- [ ] In `lib/features/member_app/member_app_viewmodel.dart`:
  - Remove initial mock entries from `_paymentHistory`.
  - Add robust deduplication across `finance_transactions`, `membership_payments`, and `member_memberships`.
  - Enforce rest days from assigned workout plan and prevent member manual rest day selection.
- [ ] In `lib/features/member_app/widgets/member_activity_heatmap_widget.dart`:
  - Align local streak algorithm with excused day logic (Sundays, holidays, rest days).

### Wave 3: Calendar Display & Staff Protection
- [ ] In `lib/features/member_app/screens/member_attendance_screen.dart`:
  - Highlight Sundays and declared holidays as "Holiday" with purple styling.
  - Add legend entry for Holiday / Sunday.
- [ ] In `lib/features/staff/staff_profile_screen.dart`:
  - Treat Sundays and Gym Holidays as "Weekly Holiday" / "Holiday", not counting toward Absent.

### Wave 4: Verification & Git Push
- [ ] Run `flutter analyze lib/features/member_app/ lib/features/staff/`.
- [ ] Commit and push to `origin main`.
