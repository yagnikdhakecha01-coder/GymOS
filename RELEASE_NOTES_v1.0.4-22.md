# 🚀 GymOS Release v1.0.4 (Build 22)

**File Name:** `gymos-release-v1.0.4-22.aab`  
**Root Path:** `c:\Users\jigar\OneDrive\Documents\GYMOS V1 UI\gymos-release-v1.0.4-22.aab` (Also mirrored as `build\app\outputs\bundle\release\app-release.aab`)  
**Build Date:** 24 September 2026  
**Target:** Google Play Console — Closed Testing Track (Alpha)  

---

## 📋 Play Console Details (Paste in "Release Name" field)

- **Release Name:** `1.0.4 (22) - Member Profile Responsive UI, Attendance Logs & Notes Sync Fix`
- **Version Name:** `1.0.4`
- **Version Code:** `22`

---

## 📝 Release Notes for Play Console (Copy-Paste into "Release notes" box)

### English (en-US / en-IN):
```text
What's new in GymOS v1.0.4 (Build 22):
• Member Profile Responsive Layout: Resolved card badge overflow on compact mobile screens so the Gym Rules & Legal Agreement badge stays neatly contained across all phone display sizes.
• Member Attendance History: Activated member attendance directly from the profile's More Actions tab with total visits count, monthly metrics, daily logs, and 1-tap present logging.
• Member Notes Persistence: Real note saving with automated sync. Notes added during member creation are immediately visible in the member profile, with strict member isolation.
• Authentication & Google Sign-In: Optimized Android Google Sign-In with seamless credential flows and store compliance.
• Transaction Ledger Recency: Exact 12-hour entry time and real-time recency sync for all payment transactions.
• General UI, performance, and stability enhancements across all screens.
```

### Hindi / Hinglish:
```text
GymOS v1.0.4 (Build 22) naye features aur fixes:
• Member Profile Responsive UI: Chote aur sabhi screens par Gym Rules Agreement badge card ke bahar jaane ki problem solve ho gayi hai.
• Member Attendance History: More Actions me Attendance ab poori tarah active hai, jisme member ki complete attendance history, check-in time aur direct mark present option milta hai.
• Member Notes Save & Sync: Naya member add karte waqt dala gaya note ab member profile me dikhega aur owner ke save kiye huye notes permanently database me save rahenge.
• Google Sign-In: Android devices ke liye Google Sign-in fast aur smooth.
• Transaction Ledger Updates: Har payment transaction ke sath exact time aur recency badge.
• Performance aur stability me improvements.
```

---

## 🛠️ Summary of Technical Changes

1. **Member Profile Agreement Card Responsive Fix (`member_profile_screen.dart`):**
   - Replaced unconstrained inner row with `Expanded` text container and `TextOverflow.ellipsis`.
   - Guaranteed badge containment for screen widths from 320px to tablet sizes.

2. **Member Attendance Logs Bottom Sheet (`member_profile_screen.dart`):**
   - Removed "Coming Soon" placeholder from Attendance under More Actions.
   - Built bottom sheet displaying total visits, this month visits, today status, and complete chronological log history.
   - Added instant "Mark Present Today" quick action utilizing `GymRepository.saveMemberAttendanceLog`.

3. **Member Notes Database Integration (`member_profile_screen.dart`):**
   - Removed static dummy strings ("Prefers morning sessions...", "VIP Client...").
   - Integrated `_saveMemberNotes(member)` using `MembersViewModel.updateMemberProfile()`.
   - Seamlessly loads member note captured during Add Member Wizard (`member.notes`).
   - Scoped strictly per-member to guarantee privacy and isolation.

4. **Authentication Clean Guard (`login_screen.dart`):**
   - Kept "Continue with Google" active and front-and-center for Android and Web (`if (kIsWeb || !Platform.isIOS)`).
   - Hid Apple Sign-In on iOS until Apple Developer account setup is finalized.
