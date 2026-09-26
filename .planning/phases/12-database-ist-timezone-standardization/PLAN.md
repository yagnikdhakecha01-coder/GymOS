# Phase 12: Database-Level India Kolkata (IST) Timezone Standardization

## Goal
Standardize all date, time, and timestamp handling at the **Database level (PostgreSQL / Supabase)** to Indian Standard Time (`Asia/Kolkata`, UTC+5:30). Ensure the existing mobile app automatically receives IST time without requiring any mobile app rebuild or APK/AAB update, while keeping 100% of live data completely safe and unmodified.

## User Review Required
> [!IMPORTANT]
> - **Zero App Update Needed**: Handled purely via PostgreSQL role configs, schema defaults, RPC function corrections, and pg_cron alignment.
> - **Live Data Safety**: Existing 142 attendance records and financial records already store valid UTC/IST timestamps. No historical records will be mutated, dropped, or corrupted.
> - **pg_cron UTC Alignment**: Supabase pg_cron runs on UTC (`GMT`). Midnight jobs (23:59 IST) will be rescheduled to `29 18 * * *` (18:29 UTC), fixing the bug where staff were marked absent at 5:29 AM in the morning.

## Audit Findings Summary
1. **Database & Role Timezones**:
   - `postgres` database has `TimeZone=Asia/Kolkata`, but API roles (`anon`, `authenticated`, `authenticator`, `service_role`) had no explicit role-level timezone set.
2. **PostgreSQL Format String Bug**:
   - `process_scan_attendance` used `to_char(now(), 'hh:mm a')`. In Postgres, `mm` is **Month** (09), not Minute (`mi`)! This printed month instead of minutes.
3. **Double Timezone Shift Bug**:
   - `get_owner_staff_cards_v1` had `ta.check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata'`, which shifted time 5.5 hours in the past (e.g. 9:00 AM check-in was displayed as 3:30 AM).
4. **pg_cron Midnight Drift Bug**:
   - `cron.job` #1 (`process_daily_absences_and_leaves`) was scheduled at `59 23 * * *` under GMT, running at 5:29 AM IST next morning and prematurely marking staff absent for the new day.
5. **UTC Default Columns**:
   - 5 tables (`attendance_audit_log`, `faqs`, `gym_backups`, `user_settings`, `workout_plans`) used `DEFAULT timezone('utc'::text, now())`, storing an unzoned timestamp that caused a 5.5 hour discrepancy.

## Proposed Changes

### 1. Database-Level Role Timezone Enactment
Set explicit session timezone for all Supabase connection roles:
```sql
ALTER DATABASE postgres SET timezone TO 'Asia/Kolkata';
ALTER ROLE anon SET timezone TO 'Asia/Kolkata';
ALTER ROLE authenticated SET timezone TO 'Asia/Kolkata';
ALTER ROLE authenticator SET timezone TO 'Asia/Kolkata';
ALTER ROLE service_role SET timezone TO 'Asia/Kolkata';
ALTER ROLE postgres SET timezone TO 'Asia/Kolkata';
```

### 2. Fix Column Default Expressions
Replace `timezone('utc'::text, now())` with `now()` on:
- `public.attendance_audit_log.created_at`
- `public.gym_backups.created_at`
- `public.user_settings.updated_at`
- `public.faqs.created_at`
- `public.workout_plans.created_at`

### 3. Hotfix PostgreSQL RPC Functions
- **`get_owner_staff_cards_v1`**:
  - Fix `last_check_in` calculation: replace double `AT TIME ZONE` with `to_char(ta.check_in AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')`.
- **`process_scan_attendance`**:
  - Fix `to_char(now(), 'hh:mm a')` -> `to_char(now() AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')`.
- **`process_daily_absences_and_leaves`**:
  - Ensure inserted timestamps explicitly use `(v_today::TEXT || ' 00:00:00')::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'`.
- **`fn_ensure_shift_absent`**:
  - Fix timestamp casting to produce true `TIMESTAMPTZ` with `+05:30`.
- **`process_qr_attendance`**:
  - Maintain rock-solid IST date checks and ensure return JSON check_in/check_out values format in `HH12:MI AM`.

### 4. Reschedule pg_cron Automated Jobs to IST
- Job 1 (`process_daily_absences_and_leaves`):
  - Change schedule from `59 23 * * *` to `29 18 * * *` (18:29 UTC = 23:59 IST end-of-day).
- Job 3 (`trigger_scheduled_auto_backup`):
  - Change schedule from `30 6,18 * * *` to `0 1,13 * * *` (01:00 & 13:00 UTC = 06:30 AM & 06:30 PM IST).

## Verification Plan
1. Test role timezone resolution for `anon`, `authenticated`, and direct pool.
2. Call `get_owner_staff_cards_v1` and verify `last_check_in` displays accurate IST time (no 5.5hr lag).
3. Test `process_scan_attendance` and `process_qr_attendance` time formatting.
4. Verify pg_cron job schedules in `cron.job`.
5. Verify live records in `attendance_logs` and `members` remain 100% intact.
