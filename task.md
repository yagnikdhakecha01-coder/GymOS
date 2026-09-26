# Phase 12: Database-Level India Kolkata (IST) Timezone Standardization

- [x] 1. Scan Database Schema & Audit Time Handling <!-- id: 0 -->
  - [x] Scan 120+ tables & columns for date/time types in public schema <!-- id: 1 -->
  - [x] Audit role timezone configurations (anon, authenticated, authenticator, etc.) <!-- id: 2 -->
  - [x] Uncover timezone format bugs (month vs minute in `process_scan_attendance`) <!-- id: 3 -->
  - [x] Uncover double timezone shift (5.5hr delay in `get_owner_staff_cards_v1`) <!-- id: 4 -->
  - [x] Uncover pg_cron GMT drift bug (Job 1 running at 5:29 AM IST) <!-- id: 5 -->
  - [x] Audit live production data (142 attendance records, 40 members intact) <!-- id: 6 -->
- [x] 2. Implementation & Migration Script Execution <!-- id: 7 -->
  - [x] Apply `Asia/Kolkata` timezone to database and all connection roles <!-- id: 8 -->
  - [x] Standardize UTC column defaults to `now()` on 5 affected tables <!-- id: 9 -->
  - [x] Deploy corrected RPC functions (`get_owner_staff_cards_v1`, `process_scan_attendance`, `process_daily_absences_and_leaves`, `fn_ensure_shift_absent`) <!-- id: 10 -->
  - [x] Reschedule `pg_cron` jobs to exact IST times (11:59 PM IST = 18:29 UTC) <!-- id: 11 -->
- [x] 3. Database Verification & Validation <!-- id: 12 -->
  - [x] Verify session timezone resolution for PostgREST & authenticated queries <!-- id: 13 -->
  - [x] Test `get_owner_staff_cards_v1` and verify live staff last check-in displays exact IST <!-- id: 14 -->
  - [x] Confirm 0 live data records lost or mutated <!-- id: 15 -->
