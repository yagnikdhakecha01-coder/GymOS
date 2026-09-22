# Phase 10: Admin Persistent Session & Auto-Backup Scheduler Restoration

## Phase Objective
1. Eliminate the 1-hour auto-logout issue on the GymOS Admin website by implementing proactive token refresh, `onAuthStateChange` listening, and session recovery.
2. Fix the automated database backup scheduler (`pg_cron` / `trigger_scheduled_auto_backup`) which stopped creating backups 2 days ago due to an authorization check in `full_database_export()`.
3. Build, deploy, and push all changes to GitHub (`gymos-v1-ui`).

## Root Cause Analysis
1. **Auto-Backup Stoppage (2 Days Ago)**:
   - On September 20, a security update added `IF NOT is_super_admin(auth.uid()) THEN RAISE EXCEPTION ...` inside `public.full_database_export()`.
   - When Supabase `pg_cron` runs, `current_user` is `'postgres'` and `auth.uid()` is `NULL`.
   - The check failed with `'Unauthorized: Super Admin access required'` and aborted the backup on every run.
2. **Admin 1-Hour Auto-Logout**:
   - Supabase JWT access tokens expire after 3,600s (1 hour).
   - `gymos_admin` did not enable `autoRefreshToken: true` or listen to `onAuthStateChange`.
   - When the token expired or browser tab went idle, queries threw `401 JWT Expired`, which triggered `_isAuthenticated = false` in `AuthProvider`, kicking the user back to the login screen.

## Tasks

### Wave 1: Supabase Database Backend (pg_cron & Backup RPCs)
- [ ] Update `public.full_database_export()` in PostgreSQL to authorize system execution (`current_user = 'postgres'`) and internal function calls.
- [ ] Update `public.trigger_scheduled_auto_backup()` to handle execution cleanly and update `platform_settings`.
- [ ] Test execution via `SELECT public.trigger_scheduled_auto_backup();` and verify snapshot in `database_backups`.

### Wave 2: GymOS Admin Session Persistence & Token Heartbeat
- [ ] In `gymos_admin/lib/core/services/supabase_service.dart`:
  - Add `FlutterAuthOptions(autoRefreshToken: true)` in `Supabase.initialize`.
  - Add `ensureValidSession()` helper to refresh expired/near-expiry sessions before executing requests.
- [ ] In `gymos_admin/lib/core/services/auth_service.dart`:
  - Call `ensureValidSession()` before verifying super admin role to prevent premature logouts.
- [ ] In `gymos_admin/lib/core/providers/auth_provider.dart`:
  - Subscribe to `onAuthStateChange` to handle `tokenRefreshed`, `signedIn`, and `initialSession` without data wipes.
  - Implement a 15-minute background session keep-alive heartbeat.
- [ ] In `gymos_admin/lib/features/database/database_screen.dart` & `google_drive_service.dart`:
  - Ensure backup snapshots always succeed into Supabase even if external cloud drive upload fails or requires re-authentication.

### Wave 3: Verification, Web Build & Git Push
- [ ] Run `flutter analyze` on `gymos_admin` to ensure zero errors.
- [ ] Compile admin web: `flutter build web --release` inside `gymos_admin/`.
- [ ] Deploy web assets to `super_admin/` and `netlify_super_admin_deploy/`.
- [ ] Git commit and push all changes to GitHub repository.
