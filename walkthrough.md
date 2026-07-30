# Walkthrough: Gym Owner First-Time Setup Wizard

The premium 4-step wizard onboarding experience specifically for new Gym Owners has been implemented. When a Gym Owner logs in for the first time, they are guided through a multi-step setup to enter Gym Info, Owner Info, review details, and view a success screen. Upon finishing, the setup status is stored in Supabase, and subsequent logins redirect directly to the Owner Dashboard.

10. Open the **Members** tab when there are 0-3 members. Drag up/down on the screen and verify that the 4 stat cards remain locked in place and do NOT slide up unnecessarily. When 4 or more members exist, verify that scrolling smoothly collapses the stat cards to give full screen height to the member cards.
11. **Live Database Syncing & Push Notifications**:
    * Supabase Realtime WebSocket push channel (`public_gym_realtime_$gymId`) has been enabled.
    * Whenever any data changes in Supabase (e.g. member added, membership expiring, new transaction logged, attendance recorded), Supabase instantly pushes an event to the app, updating the UI immediately (0ms delay).
    * Background 2-second sync acts as a continuous safety fallback, ensuring alerts and expiration badges populate automatically without requiring any manual refresh, tab switching, or logging out.
12. **Staff Profile Basic Info Editing**:
    * Tap the **Edit** pencil button in the **BASIC INFO** section of any staff profile.
    * A bottom sheet form opens allowing the owner to update full name, phone, email, date of birth, gender, address, salary, and salary type.
    * Saving updates the record directly in the Supabase `public.staff` database table and triggers live UI refresh.
    * Emergency Contact has been removed from the Basic Info section.
    * Top stat cards bind `Start Date`, `Salary Type`, `Salary`, and `Total Members` from the database, while setting `This Month Att.` to `0/0 Days` and `Leaves (Month)` to `0 Days`.

---

## 1. Summary of Changes

### 🗄️ Database Schema & Migrations
- Added columns to `gyms` in [supabase_schema.sql](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/supabase_schema.sql): `logo_url`, `gym_type`, `phone_number`, `email`, `address`, `city`, `state`, `country`, `pin_code`.
- Added columns to `profiles` in [supabase_schema.sql](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/supabase_schema.sql): `full_name`, `phone_number`, `photo_url`, `dob`, `experience`, `setup_completed`.

### 📦 User Profile Model Updates
- Updated [user_profile.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/core/models/user_profile.dart) to contain all owner onboarding fields.
- Modified serialization/deserialization logic (`fromJson` and `toJson`) to support these fields.

### 🔌 Service & ViewModel Integration
- Built `completeOwnerSetup()` in [auth_service.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/core/services/auth_service.dart) to create the gym record and owner profile record in Supabase (with offline/mock fallbacks).
- Updated [auth_viewmodel.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/authentication/auth_viewmodel.dart):
  - Exposed `completeOwnerOnboarding()` to wrap the setup database execution and store details in local storage.
  - Implemented boot-up fallback inside `loadCurrentProfile()`: if the DB is offline/mock mode but local storage shows the owner is logged in, the setup completion status is preserved.

### 🧭 Redirection & Login Safeguards
- Updated the splash screen routing in [splash_screen.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/authentication/splash_screen.dart) to inspect `profile.setupCompleted`. Completed setup opens the dashboard, whereas incomplete setup opens the setup wizard.
- Configured the same check inside [login_screen.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/authentication/login_screen.dart) after successful authentication.

### 🎨 Apple-Inspired 4-Step Setup Wizard UI
Replaced [first_time_setup_screen.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/authentication/first_time_setup_screen.dart) with a premium white-themed experience matching Material 3 specifications:
1. **Segmented Progress Indicator**: Top status bar displaying 4 capsule blocks representing the steps, aligned with step text counters.
2. **Step 1 (Gym Info)**: Form with validation inputs for Gym Name, Logo, Type dropdown, Phone number, Email, Address, City, State, Country, and PIN.
3. **Step 2 (Owner Info)**: Form with validation inputs for Profile Photo, Full Name, Phone, Email, DOB date picker, Experience dropdown, and a read-only "Owner" role dropdown.
4. **Step 3 (Review details)**: Beautiful structured review screen detailing all input values, complete with "Edit" trigger links routing the user back to the respective step form.
5. **Step 4 (Success Screen)**: Clean success animation with scale-up active tick icon, checklist advantages, and a final "Go to Dashboard" navigation trigger.
6. **Realistic Upload Mocking**: Choosing photo/logo inputs opens a bottom sheet offering beautiful presets. Clicking one runs a realistic, smooth 0-100% upload progress simulation before displaying the loaded image.

---

## 2. Verification Plan

1. **Step Validations**: If you try to advance steps without filling out required fields, standard form validations prevent proceeding and show inline error tips.
2. **Review Edit Routing**: Tapping the "Edit" button on Step 3 successfully routes the user back to Step 1 or Step 2.
3. **Subsequent Logins**: Completing the setup wizard caches `setup_completed` locally and on the server. Initiating a hot restart or logging in again successfully bypasses the wizard and launches the dashboard.
