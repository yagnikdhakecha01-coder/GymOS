# Phase 02: Staff Attendance Stability, Custom Shift Timings & Salary Joining Month Filter

## Objective
1. **Fix Staff Check-in Reverting / Disappearing Bug:**
   - Eliminate function overloading collision in Supabase: drop ambiguous duplicates of `get_staff_today_attendance_details_v2` and replace with a single, reliable definition.
   - Remove destructive `fn_ensure_shift_absent` call inside read/query function `get_staff_today_attendance_details_v2` (auto-absent belongs strictly in background cron).
   - Add a 5-minute debounce threshold in `process_qr_attendance` for staff so rapid consecutive scans or holding the camera near the QR code cannot accidentally trigger an instant check-out seconds after checking in.
2. **Shift & Time-Based Attendance (Owner-Configured Staff Timings):**
   - In `process_qr_attendance`, `cron_auto_mark_absent`, and `get_staff_today_attendance_details_v2`, prioritize the staff member's individual shift timings (`shift1_start`, `shift1_end`, `shift2_start`, `shift2_end`, `shift_type`) set by the gym owner on their staff profile, falling back to gym shift defaults.
   - Auto-absent marks staff absent 1 hour after their individual shift end time in IST (`Asia/Kolkata`), respecting Sundays and declared holidays.
3. **Staff Salary Tab Joining Date Filter:**
   - When the owner views the Staff Salary tab / Pending Salaries for a given month (e.g. Month 8 / August 2026), filter out any staff member who joined in a later month (e.g. Month 9 / September 2026).
   - Staff members must only appear in salary tabs from their joining month onwards.

---

## Tasks

### Wave 1: Database RPC & Backend Logic (Supabase)
- [ ] Drop the duplicate overloaded versions of `get_staff_today_attendance_details_v2(uuid, uuid, date)` and `get_staff_today_attendance_details_v2(uuid, uuid, uuid, date)`.
- [ ] Create a unified `get_staff_today_attendance_details_v2(p_user_id UUID, p_gym_id UUID, p_date DATE DEFAULT ...)` that resolves both `user_id` and `staff_id`, reads staff individual shift timings, queries existing attendance logs cleanly, and **does not** execute mutation/absent insertions during read operations.
- [ ] Update `process_qr_attendance` to:
  - Respect the staff member's custom shift timings (`shift1_start`, `shift1_end`, etc.).
  - Enforce a 5-minute check-out cooldown (if checked in within the last 5 minutes, prevent accidental check-out and return `already_marked = true`).
- [ ] Update `cron_auto_mark_absent` to evaluate staff shift assignments using individual staff timings set by the owner.
- [ ] Apply SQL migration via Supabase MCP tool.

### Wave 2: Frontend State & Salary Filtering (Flutter)
- [ ] In `lib/features/staff/staff_viewmodel.dart`:
  - Implement `isStaffEmployedInMonth(Staff staff, String monthStr)` comparing month and year against `staff.joinDate`.
  - Update `getPendingSalaryStaff(String month)` to exclude staff members who joined after `month`.
  - Update `getStaffPendingPayable` and `refreshStaffPayablesForMonth` to return `0.0` for months prior to employment.
- [ ] In `lib/features/attendance/staff_attendance_screen.dart`:
  - Ensure status check handles the single RPC response cleanly.
  - Maintain the checked-in state reliably without premature timeout or reversion.

### Wave 3: Verification & Compilation
- [ ] Verify Supabase RPC call with sample UUID returns clean JSON with no ambiguity error.
- [ ] Run `flutter analyze` across modified files to guarantee zero compile errors.
- [ ] Stage, commit, and push to GitHub.
