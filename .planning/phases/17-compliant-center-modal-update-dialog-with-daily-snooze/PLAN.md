# Phase 17: Compliant Center-Modal Update Dialog with Daily Snooze

## Goal
Transform the full-screen blocking force-update screen into a compliant, center-aligned modal dialog with an `[X]` close button, `Later` button, and `Update Now` button, featuring a daily snooze mechanism (dismissed once, won't show again until the next day). Ensure the app is never hard-blocked on startup, fully adhering to Google Play Store and Apple App Store review guidelines.

---

## Context & Requirements

1. **Compliance with App Store & Google Play Review Guidelines**:
   - Full-screen blocking screens on launch with disabled back navigation (`PopScope(canPop: false)`) risk immediate app rejection under Google Play (Broken Functionality / Policy Violations) and Apple App Store (Guideline 2.1 - App Completeness).
   - Reviewers and users must be able to dismiss or postpone the update to test or use the app.

2. **Center Modal Dialog (Replacing Full-Screen Blocker)**:
   - Must be displayed as a centered floating dialog (`Dialog` / `AlertDialog`), not a full-screen replacement route.
   - **Top Right Corner**: An `[X]` close icon button for fast dismissal.
   - **Body**: GymOS update icon badge, Version indicator (e.g., `v1.0.9`), friendly announcement message, and expandable/scrollable "What's New" release notes.
   - **Bottom Row**: Two buttons:
     - Secondary button: `Later` (snoozes for the day and closes).
     - Primary button: `Update Now` (opens Play Store / App Store link).

3. **Daily Snooze Logic (Once per Day)**:
   - When the user taps `Later`, `[X]`, back button, or clicks outside:
     - Record the dismissal date (`YYYY-MM-DD`) in `SharedPreferences` (key: `gymos_update_snooze_date`).
     - For the rest of the calendar day, the dialog will **never** re-trigger (even during 30-second poll loops in `AlertsNotificationEngine` or upon app restart).
     - The next calendar day (`DateTime.now()` date != saved snooze date), if an update is still published and required, the dialog can reappear once.

4. **Silent Startup When No Update or Already Snoozed**:
   - On app launch (`SplashScreen` & initial load), the app must NOT show any dialog by default unless:
     - `result.isUpdateAvailable == true`
     - Force/recommended update flag is active
     - AND `isSnoozedToday() == false`
   - Remove the hard-blocking `Navigator.pushReplacement(..., ForceUpdateScreen)` from `SplashScreen`.

---

## Detailed Task Waves

### Wave 1: Snooze Service & SharedPreferences Persistence
- [x] Add snooze management functions to `VersionCheckService`:
  - `static const String _snoozeDateKey = 'gymos_update_snooze_date';`
  - `static Future<bool> isSnoozedToday()`: checks if saved date string equals today's date (`yyyy-MM-dd`).
  - `static Future<void> snoozeForToday()`: writes today's date string into `SharedPreferences`.
  - `static Future<void> clearSnooze()`: helper to reset snooze if needed.
- [x] Ensure all date comparisons use device local date format (`yyyy-MM-dd`).

### Wave 2: Center-Modal Update Dialog UI (`UpdatePromptDialog`)
- [x] Create `UpdatePromptDialog` in `lib/core/services/version_check_service.dart`:
  - Center card with `maxWidth: 380`, rounded borders (`24px`), theme-aware card styling.
  - **Top Row**: Version pill badge (`v1.0.x`) and `[X]` close icon button with tactile tap surface.
  - **Content**:
    - Update icon with vibrant glowing circle container.
    - Title: `"Update Available"`.
    - Clean description without cluttered release notes (store pages handle notes).
  - **Action Buttons**:
    - `Later` button: Outlined button, triggers `VersionCheckService.snoozeForToday()` and dismisses dialog.
    - `Update` button: Primary filled button with download icon, opens Play Store / App Store via `launchStoreUrl`.
  - Wrapped in `PopScope(canPop: true)` to automatically trigger snooze on back button or outside dismiss.

### Wave 3: Integration & Cleanup in Engine, Splash Screen & Alerts Loop
- [x] Update `splash_screen.dart`:
  - Removed blocking route push to `ForceUpdateScreen`.
  - Allows splash screen to transition smoothly into the main app flow without getting stuck.
- [x] Update `VersionCheckEngine`:
  - Checks `await VersionCheckService.isSnoozedToday()` before showing any update dialog.
  - Replaced blocking full screen with `showUpdateDialog(result, targetContext)`.
  - Guards `isShowingDialog` lock to prevent duplicate dialogs.
- [x] Update `alerts_notification_engine.dart`:
  - Verified 30-second periodic poll checks `isSnoozedToday()` and never repeatedly prompts snoozed users.

### Wave 4: Validation & Quality Gate
- [x] Verified zero errors, zero warnings across `version_check_service.dart`, `alerts_notification_engine.dart`, and `splash_screen.dart` with `flutter analyze`.
- [x] App is compliant with Google Play Store & Apple App Store guidelines (no launch lockout).
