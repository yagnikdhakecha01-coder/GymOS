# Phase 31 — In-App Play Store Review with Role-Based Smart Suggestions

**Phase:** 31
**Milestone:** GymOS v1.2
**Status:** 🟡 Ready to Execute
**Mode:** tracer-first

---

## Goal

Implement a **premium in-app rate & review experience** inside GymOS that:

1. Is accessible from **Settings screen → bottom "Rate GymOS" tile** (no annoying auto-popup)
2. Shows a **beautiful, theme-consistent bottom sheet** with animated star rating
3. After stars are selected, **auto-suggests a role-based review** (Owner / Staff / Member) — pre-filled into a text field
4. User can edit the suggestion and tap **Submit → opens Play Store** to the GymOS listing
5. Stores a **"has_reviewed" flag** in `SharedPreferences` so the tile shows "Thank You ✓" afterwards
6. Logs the review event to **Supabase analytics** (anonymous, no PII)
7. Is keyword-optimized for **GymOS, GymOS, gym management** to boost Play Store ranking

---

## App Feature Context (Read Before Coding)

### Roles in the App
| Role     | authVm.selectedRole value | Login path |
|----------|---------------------------|------------|
| Owner    | "owner"                   | MainNavigationHolder → MoreScreen → SettingsScreen |
| Staff    | "staff" (or receptionist) | MainNavigationHolder → MoreScreen → SettingsScreen |
| Member   | "member"                  | MemberShell → Profile tab → SettingsScreen (shared) |

> Both Owner/Staff and Member flows route to the **same** SettingsScreen.
> authVm.selectedRole (via Provider<AuthViewModel>) is available in SettingsScreen.

### Member Features (for review suggestions)
- Attendance tracking — daily check-in QR scan, streak counter, achievements
- Diet plans — assigned by trainer; weight-loss, weight-gain, bodybuilding
- Goal tracker — fitness goals set at join; progress in body stats screen
- Workout plans — guided exercise library, sets/reps logging
- Achievements & gamification — badges, streaks, milestones
- Membership details — plan validity, renewal reminders

### Owner Features (for review suggestions)
- Full member management — add/edit/delete, filter, search, photos
- Staff salary & attendance — payroll, shift management, advances
- Finance dashboard — revenue tracking, payment history, collections
- Follow-ups & renewals — expiring member alerts, WhatsApp reminders
- Diet & workout assignment — assign plans to members
- Custom branding — gym logo, name, QR codes
- Reports & analytics — attendance, revenue, membership stats
- Subscription management — GymOS plan billing

### Staff Features (for review suggestions)
- Attendance marking — QR scanner, manual entry
- Member check-ins — reception portal activity log
- Client management — trainer's own assigned members
- Workout plan management — assign/edit for personal training clients

### Existing App Theme
- Primary: Color(0xFF6C3AED) (violet-700)
- Background: Color(0xFFF8F8FA)
- Card: white with AppTheme.border outline
- Font: GoogleFonts.inter
- Radius: AppTheme.radiusSheet = 24.0 for bottom sheets
- All patterns from lib/core/theme/theme.dart

---

## Architecture

```
lib/
  features/
    more/
      settings_screen.dart          <- MODIFY: add "Rate GymOS" tile (bottom of PREFERENCES section)
      app_review_bottom_sheet.dart  <- CREATE: premium review bottom sheet widget
  core/
    services/
      app_review_service.dart       <- CREATE: SharedPrefs flag + Supabase analytics logging
```

### No new packages needed
- Play Store link via url_launcher (already in pubspec)
- SharedPreferences (already in pubspec)
- Provider (already in pubspec)

---

## Supabase Analytics Table

```sql
-- Migration: add_app_review_analytics.sql
CREATE TABLE IF NOT EXISTS app_review_events (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  gym_id      uuid,
  role        text,        -- 'owner' | 'staff' | 'member'
  stars       int,
  submitted   boolean DEFAULT false,
  created_at  timestamptz DEFAULT now()
);
ALTER TABLE app_review_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth insert" ON app_review_events FOR INSERT TO authenticated WITH CHECK (true);
```

> Only stars + role + gym_id logged. No review text, no names, no PII.

---

## Role-Based Review Suggestion Corpus

> Short 1-2 line, natural-sounding, SEO-friendly. Keywords: GymOS, gym management, attendance, diet, workout.
> These are **pre-filled suggestions only** — user can freely edit before submitting to Play Store.

| Key | Suggested Text |
|-----|----------------|
| `owner_5` | `"Best gym management app! GymOS handles members, attendance, salary, and finance all in one place. A must-have for every gym owner."` |
| `owner_4` | `"GymOS is a solid gym management tool. Member renewals, staff attendance, and revenue tracking work great."` |
| `owner_3` | `"Good gym management app. GymOS covers member and attendance basics well. Would love more features."` |
| `staff_5` | `"GymOS makes gym staff work easy. QR check-in, client tracking, and attendance — all smooth. Love it!"` |
| `staff_4` | `"Great app for gym trainers. GymOS client management and attendance tracking works really well."` |
| `staff_3` | `"GymOS is useful for gym staff. Attendance and member check-ins work fine."` |
| `member_5` | `"Love GymOS! My attendance streak, diet plan, workout, and fitness goals — everything in one app. So motivating!"` |
| `member_4` | `"GymOS is great for gym members. Diet plan, workout tracker, and QR check-in are super convenient."` |
| `member_3` | `"Useful gym app. GymOS attendance and diet tracking works well. More features would be nice."` |

---

## Play Store Launch — Option A (Confirmed)

**Strategy:** User writes review in-app (for comfort/guidance), then taps Submit → Play Store opens directly where they paste and post.

```dart
const _playStoreUrl = 'https://play.google.com/store/apps/details?id=com.gymos.app';
const _playStoreFallback = 'https://play.google.com/store/apps/developer?id=GymOS';
```

**Launch code:**
```dart
final launched = await launchUrl(
  Uri.parse(_playStoreUrl),
  mode: LaunchMode.externalApplication,
);
if (!launched) {
  await launchUrl(Uri.parse(_playStoreFallback), mode: LaunchMode.externalApplication);
}
```

> Verify actual package ID from android/app/build.gradle before executing.
> Play Store opens → user sees their pre-filled suggestion (copied to clipboard optional enhancement).

---

## UI Design Specification

### Settings Screen Entry Point
Location: Bottom of the "PREFERENCES" section card, after "Online Database", with Divider before it.

Tile — Not yet reviewed:
- Leading icon container: color(0xFFFEF3C7) bg, Icons.star_rounded amber
- Title: "Rate GymOS"
- Subtitle: "Love the app? Leave a review on Play Store"
- Trailing: chevron_right

Tile — Already reviewed:
- Leading icon container: AppTheme.successLight bg, Icons.star_rounded green
- Title: "Thank You for Rating! ✓"
- Subtitle: "Your review helps other gyms discover GymOS"
- Trailing: chevron_right (allow re-review tap)

### Review Bottom Sheet (app_review_bottom_sheet.dart)

Layout (top to bottom):
1. Drag handle bar (centered, 4x40 rounded rect)
2. Large star/logo icon (80px, amber gradient)
3. Title: "Enjoying GymOS?" (fontSize 22, bold)
4. Subtitle: "Your review helps other gym owners discover us on Play Store." (muted, centered)
5. 5 star row (48px each, spaced 8px, tap-to-fill amber, bounce animation)
6. [ANIMATED SLIDE-IN after star tap]:
   - Label: "Your Review (edit freely)"
   - Multiline TextField (5 lines, pre-filled with corpus text)
   - Full-width "Submit Review on Play Store →" button (AppTheme.primary)
   - "Maybe Later" TextButton (muted, centered)

Design specs:
- showModalBottomSheet with isScrollControlled: true
- Rounded top: BorderRadius.vertical(top: Radius.circular(24))
- Star tap animation: TweenAnimationBuilder scale 1.0 → 1.3 → 1.0 (150ms)
- Selected stars: Color(0xFFF59E0B), unselected: AppTheme.textMuted
- Text field: AppTheme style, violet focus border, 5 maxLines
- Keyboard handling: Padding(padding: MediaQuery.of(context).viewInsets) or resizeToAvoidBottomInset

---

## Task Breakdown

### Task 1 — AppReviewService (tracer foundation)
File: lib/core/services/app_review_service.dart
Type: tracer | Complexity: Low | Dependencies: None

Implement:
- static Future<bool> hasReviewed() → reads 'gymos_has_reviewed' from SharedPrefs
- static Future<void> markReviewed() → sets 'gymos_has_reviewed': true in SharedPrefs
- static Future<void> logReviewEvent({required String role, required int stars, required bool submitted, String? gymId}) → fire-and-forget INSERT to app_review_events. Catch all errors silently.
- static String getSuggestedReview(String role, int stars) → returns corpus text via '${role}_${stars}' key map. Default to owner_5 if not found.

Corpus key format: 'owner_5', 'owner_4', 'owner_3', 'staff_5', 'staff_4', 'staff_3', 'member_5', 'member_4', 'member_3'

---

### Task 2 — AppReviewBottomSheet (main UI tracer)
File: lib/features/more/app_review_bottom_sheet.dart
Type: tracer | Complexity: Medium-High | Dependencies: Task 1

```dart
class AppReviewBottomSheet extends StatefulWidget {
  final String role; // 'owner' | 'staff' | 'member'
  final String? gymId;
  static Future<void> show(BuildContext context, {required String role, String? gymId});
}
```

State machine:
- Phase 1: Star selection only (review text hidden, submit hidden)
- Phase 2: After star tap → AnimatedOpacity/AnimatedSize slide-in for text field + buttons

Submit flow:
1. AppReviewService.logReviewEvent(role, stars, submitted: true, gymId: gymId)
2. AppReviewService.markReviewed()
3. Navigator.pop(context)
4. launchUrl(Uri.parse(_playStoreUrl), mode: LaunchMode.externalApplication)
5. ScaffoldMessenger success SnackBar: "🎉 Thank you for your review! It helps GymOS grow 🚀"

Maybe Later flow:
1. If stars > 0: AppReviewService.logReviewEvent(role, stars, submitted: false, gymId: gymId)
2. Navigator.pop(context) — no markReviewed()

---

### Task 3 — Settings Screen Integration
File: lib/features/more/settings_screen.dart
Type: integration | Complexity: Low | Dependencies: Task 1, Task 2

Changes:
1. Add imports for AppReviewService and AppReviewBottomSheet
2. Add bool _hasReviewed = false; to _SettingsScreenState
3. In _loadSettings(): add _hasReviewed = await AppReviewService.hasReviewed(); then setState
4. Add Divider + Rate tile at bottom of PREFERENCES CustomCard children list
5. After sheet completes (use async/await on show()), call setState to refresh _hasReviewed

Role extraction in onTap:
```dart
final authVm = Provider.of<AuthViewModel>(context, listen: false);
final role = (authVm.selectedRole ?? 'owner').toLowerCase();
final gymId = authVm.gymInfo?['id']?.toString();
await AppReviewBottomSheet.show(context, role: role, gymId: gymId);
setState(() {}); // refresh _hasReviewed after returning
```

---

### Task 4 — Supabase Migration SQL
File: add_app_review_analytics.sql (project root)
Type: database | Complexity: Very Low | Dependencies: None

Create the SQL file with table + RLS policy from architecture section above.
Apply via: Supabase MCP apply_migration OR Dashboard → SQL Editor.

---

### Task 5 — Member Profile Rate Tile (bonus)
File: lib/features/member_app/screens/member_profile_screen.dart
Type: enhancement | Complexity: Low | Dependencies: Task 1, Task 2

Add "Rate GymOS" ListTile to member profile screen settings list.
Role hardcoded to 'member', gymId from MemberAppViewModel.gymId.

---

## Acceptance Criteria / UAT

| # | Scenario | Expected Result |
|---|----------|----------------|
| 1 | Owner opens Settings → scrolls to bottom of PREFERENCES card | Sees "Rate GymOS ⭐" tile with amber star icon |
| 2 | Owner taps "Rate GymOS" | Premium bottom sheet opens with 5 empty stars |
| 3 | Owner taps 5 stars | Stars fill amber with bounce animation; review text field slides in with owner 5-star suggestion pre-filled |
| 4 | Owner taps 4 stars | Owner 4-star text suggestion appears |
| 5 | Member taps 5 stars | Member 5-star suggestion appears (attendance/diet/goals focused text) |
| 6 | Staff taps 5 stars | Staff 5-star suggestion appears (trainer/client/attendance focused text) |
| 7 | User edits suggestion text | Free text editing works, no length limit enforced |
| 8 | User taps "Submit Review on Play Store" | Play Store opens to GymOS app page; success snackbar shows |
| 9 | After submit, Settings tile | Shows green "Thank You for Rating! ✓" |
| 10 | User taps "Maybe Later" | Sheet dismisses, no reviewed flag set, tile still shows amber star |
| 11 | User taps "Rate GymOS" after reviewing | Sheet opens again (allows re-review) |
| 12 | Supabase app_review_events | Row inserted with correct role, stars, submitted=true after Step 8 |
| 13 | No internet connection | Review sheet still works; Supabase log silently fails, no crash |
| 14 | Keyboard opens on text field | Bottom sheet scrolls up, content not hidden behind keyboard |

---

## Verification Checklist

- [ ] AppReviewService unit-testable (pure dart, no widget deps)
- [ ] AppReviewBottomSheet.show() works from both SettingsScreen and MemberProfileScreen
- [ ] All 3 roles produce different review suggestions
- [ ] Stars 3, 4, 5 each produce different texts per role (9 total corpus entries)
- [ ] url_launcher opens correct Play Store URL on physical Android device
- [ ] SharedPrefs flag persists across app restarts
- [ ] No setState called after dispose (mounted guards in async callbacks)
- [ ] Keyboard does not hide submit button (test on 5.5" screen)
- [ ] Supabase table created and INSERT succeeds (verify in Dashboard)
- [ ] No new package added (uses only existing deps)
- [ ] flutter analyze passes with zero new warnings

---

## File Change Summary

| File | Action | Notes |
|------|--------|-------|
| lib/core/services/app_review_service.dart | CREATE | Service class |
| lib/features/more/app_review_bottom_sheet.dart | CREATE | Bottom sheet UI |
| lib/features/more/settings_screen.dart | MODIFY | Add Rate tile + imports |
| lib/features/member_app/screens/member_profile_screen.dart | MODIFY | Add Rate tile (bonus) |
| add_app_review_analytics.sql | CREATE | Supabase migration |

Total new lines (est.): ~450 LOC
Risk: LOW — isolated, no existing feature modified dangerously, no new packages

---

## Executor Notes

1. Star animation: TweenAnimationBuilder<double> per star. On tap → animate scale 1.0→1.3→1.0 (150ms).
2. Role detection: Read authVm in onTap callback, not in build(). Use listen: false.
3. Corpus map key: '${role}_${stars}' e.g. 'owner_5', 'member_4'. Default to 'owner_5' if key missing.
4. Play Store URL: Verify actual package ID from android/app/build.gradle before using.
5. Divider: Add const Divider(height: 1), before Rate tile to match existing pattern.
6. Never auto-popup on launch: Only Settings entry point. No timer, no session counter trigger.
7. After sheet pop: Call setState(() {}) in SettingsScreen to refresh _hasReviewed tile state.
