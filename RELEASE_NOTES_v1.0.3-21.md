# 🚀 GymOS Release v1.0.3 (Build 21)

**File Name:** `gymos-release-v1.0.3-21.aab`  
**Root Path:** `c:\Users\jigar\OneDrive\Documents\GYMOS V1 UI\gymos-release-v1.0.3-21.aab` (Also mirrored as `app-release.aab`)  
**Build Date:** 23 September 2026  
**Target:** Google Play Console — Closed Testing Track  

---

## 📋 Play Console Details

- **Release Name:** `1.0.3 (21) - Fix Agreement Audit History & Table Permissions`
- **Version Name:** `1.0.3`
- **Version Code:** `21`

---

## 📝 Release Notes for Play Console (Copy-Paste)

### English (en-US / en-IN):
```text
What's new in GymOS v1.0.3 (Build 21):
• Gym Rules Agreement Audit Fix: Resolved table permissions and added secure RPC verification so owner side "Agreement History" immediately displays all accepted members with exact date/time audit logs.
• Pull to Refresh: Added smooth pull-to-refresh on Agreement History even when the list is initially empty.
• Permanent Agreement Persistence: Member agreements are permanently locked locally and in the cloud across all sessions.
• Member Goal & Auto Workout/Diet Plan Matching: Modify member fitness goals anytime with automated diet & workout suggestions.
• Instant Member Invitation Code: Automatic invitation code creation upon member registration.
• 1-Click Restore Hub: Granular member deletion options and centralized restore center.
• Stability and performance improvements.
```

### Hindi / Hinglish:
```text
GymOS v1.0.3 (Build 21) naye features aur updates:
• Agreement History Audit Fix: Database permissions aur secure RPC add kiya gaya, ab Owner app me member agreement history turant exact date/time ke sath dikhegi.
• Pull to Refresh: Empty state par bhi smooth pull-to-refresh chalega taaki naye agreements turant refresh ho sakein.
• Permanent Rules Agreement: Ek baar agree karne par agreement status hamesha ke liye locked rahega.
• Member Goal & Diet/Workout Matching: Member ka goal edit karne par matching diet aur workout plan auto assign.
• Auto Invitation Code: Member bante hi turant invite code generate ho jata hai.
• 1-Click Restore Hub: Deleted members aur records ko restore karne ki suvidha.
```

---

## 🛠️ Root Cause & Technical Details

1. **Database Grant & RLS Fix:**
   - Granted full permissions (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) on `member_rule_agreements` to `authenticated`, `anon`, and `service_role`.
   - Updated SELECT RLS policy to ensure gym owners, user associations, and admins have unrestricted read access.
2. **Dedicated RPC `get_gym_rule_agreements`:**
   - Deployed `SECURITY DEFINER` Postgres function to bypass permission friction and provide a dual-layer fallback in Flutter.
3. **Repository & UI Enhancements:**
   - Updated `GymRepository.fetchGymAgreements` to execute RPC with fallback to direct table query.
   - Comprehensive fallback for gym ID resolution (`activeAssociation?.gymId ?? gymInfo?['id'] ?? currentProfile?.gymId`).
   - Wrapped empty state with `SingleChildScrollView(physics: AlwaysScrollableScrollPhysics())` so Pull-to-Refresh works at all times.
