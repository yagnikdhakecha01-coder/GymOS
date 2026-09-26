# Phase 14: Biometric Secret Persistence & Secure Custom Branding Upload

## Goal
Fix biometric secret key retrieval, persistence, and regeneration in Attendance Settings, and upgrade Custom App Branding to allow direct, secure logo image uploads from the phone without exposing Supabase URLs or allowing malicious files.

## Plan Breakdown

### Wave 1: Database RPCs & Storage Security
- [x] Fix `regenerate_gym_biometric_secret(p_gym_id UUID)` to check ownership via `user_gym_associations` (role `owner`/`admin`) instead of `gyms.owner_id` (which was NULL).
- [x] Create `get_or_create_gym_biometric_settings(p_gym_id UUID)` RPC returning `{ enabled, secret, device_count }`, automatically generating a 64-character secret if not present.
- [x] Create `toggle_gym_biometric_attendance(p_gym_id UUID, p_enabled BOOLEAN)` RPC to persist state securely.
- [x] Fix RLS policy on `gym_biometric_devices` to use `user_gym_associations`.
- [x] Create/configure Supabase Storage bucket `branding` with public read, 5MB file size limit, and strict mime type restriction (`image/jpeg`, `image/png`, `image/webp`).

### Wave 2: Attendance Settings Biometric UI Fix
- [x] Update `owner_settings_screen.dart`:
  - Fetch biometric settings using `get_or_create_gym_biometric_settings(gymId)` on load.
  - Persist toggle changes using `toggle_gym_biometric_attendance(gymId, val)`.
  - Fix secret key visibility toggle and clipboard copy.
  - Call fixed `regenerate_gym_biometric_secret(gymId)` and update UI state immediately.
  - Ensure back navigation and re-entry retains enabled state and secret key without turning off.

### Wave 3: Custom App Branding Direct Phone Upload & Anti-Virus Validation
- [x] Update `custom_branding_screen.dart`:
  - Replace raw URL input with phone image picker (Camera / Gallery).
  - Implement client-side antivirus and sanitization checks:
    - Allowed extensions: `.jpg`, `.jpeg`, `.png`, `.webp`.
    - File size ceiling: 5MB maximum.
    - Magic bytes signature inspection (JPEG, PNG, WebP header bytes) via `ImageSecurityService` to block executable payloads disguised as images.
    - Path and filename sanitization.
  - Upload to `branding` bucket and store sanitized URL.
  - Keep Supabase URL hidden from UI while showing live mockup with selected/uploaded logo.

### Wave 4: Release Verification & Build
- [x] Run `flutter analyze` to ensure zero errors.
- [x] Bump version to `1.0.7+25` in `pubspec.yaml` and `app_config.dart`.
- [x] Build release AAB (`gymos-release-v1.0.7-25.aab`).
- [x] Build release APK (`gymos-release-v1.0.7-25.apk`).
- [x] Generate comprehensive release notes for closed testing.
