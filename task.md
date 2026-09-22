# Google Drive Auto-Renewal & 12-Hour Backup Scheduler

- [x] 1. Supabase Backend: Setup 12-Hour pg_cron schedule & update `trigger_scheduled_auto_backup()`
  - [x] Schedule `pg_cron` at `30 6,18 * * *` (12:00 PM & 12:00 AM IST)
  - [x] Update `platform_settings` table (`auto_backup_config`) with 12-hour interval
  - [x] Test execution via `SELECT public.trigger_scheduled_auto_backup();`
- [x] 2. GymOS Admin Web: Google Drive Service & OAuth Auto-Renewal
  - [x] Update `auth_service.dart` `signInWithGoogle()` to request Google Drive scopes and offline access
  - [x] Update `auth_provider.dart` to automatically save provider tokens to `platform_settings` upon Google login
  - [x] Update `google_drive_service.dart` with default Web Client ID and robust silent auto-renewal
  - [x] Update `database_screen.dart` to add 1-Click Google Drive connect button and 12-Hour frequency option
- [x] 3. Build & Deploy
  - [x] Compile `gymos_admin` for web: `flutter build web --release`
  - [x] Deploy build artifacts to `netlify_super_admin_deploy` and `super_admin` folders
- [x] 4. Verification & Testing
  - [x] Verify `pg_cron` job status in Supabase (Job 3: `auto_database_backup_12h`)
  - [x] Test live build via browser subagent and verify Google login & clean UI
