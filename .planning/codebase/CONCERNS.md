# Codebase Concerns

**Analysis Date:** 2026-09-16

## Tech Debt

**Monolithic Repository (`lib/core/repository/gym_repository.dart`):**
- Issue: `gym_repository.dart` is over 186 KB (4,000+ lines of code), containing logic for members, staff, attendance, finance, workouts, diets, settings, and subscriptions all in one class.
- Why: Rapid feature iteration during MVP development.
- Impact: High cognitive load when editing; high risk of merge conflicts; tightly couples independent domains.
- Fix approach: Refactor into domain-specific repositories (`MemberRepository`, `StaffRepository`, `AttendanceRepository`, `FinanceRepository`) unified behind a facade or injected independently into ViewModels.

**Duplicate Directory Structure:**
- Issue: `lib/core/repositories/` exists with only a `.gitkeep` file, while the active repository file is located in `lib/core/repository/`.
- Impact: Confusing for new contributors or automated tooling.
- Fix approach: Clean up `lib/core/repositories/` or migrate all modular repositories into it.

**Root SQL Migration Proliferation:**
- Issue: There are ~70 individual `.sql` migration files scattered in the project root directory (`c:\Users\jigar\OneDrive\Documents\GYMOS V1 UI\*.sql`).
- Impact: Clutters project root, makes it hard to identify the authoritative database schema version or replay sequence.
- Fix approach: Consolidate migrations into a version-controlled `supabase/migrations/` folder using timestamped prefixes (`YYYYMMDDHHMMSS_name.sql`).

## Known Bugs & Fragile Areas

**QR Attendance Edge Cases:**
- Fragile area: Night shifts and cross-midnight attendance logs (`lib/core/services/staff_shift_attendance_engine.dart`, `fix_attendance_auto_absent_both_shift.sql`).
- Risk: Check-out calculations for shifts crossing midnight (e.g. 10 PM to 6 AM) require careful IST timezone offset handling to avoid double-marking absent.
- Mitigation: Several SQL triggers were deployed to normalize date stamps to Indian Standard Time (`update_leave_half_day_and_ist.sql`).

**Google Sign-In SHA Fingerprints:**
- Fragile area: Google OAuth on Android devices (`google_sign_in: ^6.2.1`).
- Common failure: If the SHA-1 or SHA-256 fingerprint in Google Cloud Console / Firebase does not match the Google Play App Signing key (when Play App Signing is enabled), Google Sign-In throws error code 10 or 12500.
- Current status: Upload keystore and Google Play App Signing credentials have been synced as of release v1.0.0+5.

## Security Considerations

**Environment Secrets & Keystore:**
- Risk: Accidental exposure of Supabase service keys or Android release keystore.
- Current mitigation:
  - `.env` and `upload-keystore.jks` must remain strictly gitignored.
  - Supabase client uses the public `anonKey` with strict PostgreSQL Row-Level Security (RLS) enforcing tenant isolation.
- Recommendations: Ensure database service role keys (`service_role`) are never embedded in client binaries.

**Row-Level Security (RLS) Enforcement:**
- Risk: Multi-tenant data leakage if an RLS policy is missing on a new Supabase table.
- Recommendation: Maintain automated checks verifying that every new table has `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` and policies restricting access by `gym_id`.

## Performance Bottlenecks

**Large Member Directory Query:**
- Problem: `GymRepository.getMembers()` currently fetches all gym members into memory and caches them as a JSON blob in `SharedPreferences`.
- Impact: For gyms with >1,000 members, JSON serialization and memory consumption may cause jank or frame drops during list scrolling.
- Improvement path: Implement paginated queries (`.range(start, end)`) and virtualized lazy lists (`ListView.builder`) with SQLite/Isar local cache.

## Dependencies at Risk

- `razorpay_flutter: ^1.3.5`: Requires monitoring for Flutter 3.x and Android 14+ target SDK 34 compatibility updates.
- `flutter_launcher_icons: ^0.13.1`: Dev-dependency only, works reliably for current asset generation.

---

*Concerns analysis: 2026-09-16*
*Update as issues are resolved or new technical debt is introduced*
