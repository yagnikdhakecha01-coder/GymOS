# 🚀 GymOS Release v1.1.6 (Build 43)

### Release Name:
`1.1.6 (43) - Member Workout Plan Engine, 7-Day Offline Schedule & Biometric Attendance Persistence`

---

### 📝 What's New & Detailed Changes:

#### 1. 🏋️ Member Workout Routine Sync (Owner-Assigned Plans):
- Member Home Dashboard now accurately displays the exact workout assigned by the gym owner for today's routine.
- Fixed the issue where assigned members saw an incorrect "Rest Day".
- Added multi-split muscle support: Combinations like **"Chest & Biceps"** or **"Back & Triceps"** now display cleanly with compound muscle tags instead of defaulting to rest day.

#### 2. ⚡ 7-Day Smart Offline Schedule Engine (Zero Redundant Server Requests):
- The complete 7-day weekly workout schedule is fetched and cached locally in device storage (`SharedPreferences`) on login/initial sync.
- Members can view their daily workout plan and exercise list completely offline without calling backend APIs repeatedly.
- Includes automatic pull-to-refresh cache invalidation when the member desires to fetch updated routines.

#### 3. 📋 Interactive "My Plan" Day-Wise Overhaul:
- Completely redesigned the "My Plan" screen under Member Training.
- Displays comprehensive day-by-day workout schedules matching the owner's assigned routine, including exercise name, target muscle group, sets, reps, and custom trainer notes.

#### 4. 🛡️ Biometric & Face PIN Registration Fix:
- Resolved the issue where Biometric PIN / Face ID PIN was not saving to Supabase during new member registration or old member profile updates.
- PIN persistence is now universally active across all gym configurations (Apex, Classic, or biometric-enabled gyms).

#### 5. 📱 Performance & Stability Polish:
- Android 15 compatibility with 16 KB page alignment and R8 shrinking enabled.
- Hardened Supabase real-time sync with local cache validation.

---

### 📋 Play Store Console Release Summary (Copy & Paste this into Google Play Console):
```text
- Member Workout Plan Sync: Today's training now accurately displays gym owner's assigned workout routines.
- Multi-Split Display: Seamlessly supports dual-muscle splits (e.g. Chest & Biceps) without false rest day alerts.
- Offline Schedule Engine: Complete 7-day workout routine cached locally for lightning-fast offline access.
- Interactive "My Plan": Day-wise breakdown of exercises, target muscles, sets, reps, and trainer instructions.
- Biometric Persistence Fix: Reliable synchronization for Member Biometric & Face PINs.
- Performance and stability optimizations for Android 15.
```

---

### 📦 Build Information:
- **Version Name**: `1.1.6`
- **Version Code**: `43`
- **Bundle File**: `gymos-release-v1.1.6-43.aab` / `build/app/outputs/bundle/release/app-release.aab`
