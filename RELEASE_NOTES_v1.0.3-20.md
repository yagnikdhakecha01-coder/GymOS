# 🚀 GymOS Release v1.0.3 (Build 20)

**File Name:** `gymos-release-v1.0.3-20.aab`  
**Root Path:** `c:\Users\jigar\OneDrive\Documents\GYMOS V1 UI\gymos-release-v1.0.3-20.aab` (Also mirrored as `app-release.aab`)  
**Build Date:** 23 September 2026  
**Target:** Google Play Console — Closed Testing Track  

---

## 📋 Play Console Details

- **Release Name:** `1.0.3 (20) - Member Goal Matching, Restore Hub & Rules Fix`
- **Version Name:** `1.0.3`
- **Version Code:** `20`

---

## 📝 Release Notes for Play Console (Copy-Paste)

### English (en-US / en-IN):
```text
What's new in GymOS v1.0.3 (Build 20):
• Member Goals & Auto Plan Matching: Edit member fitness goals anytime with automatic workout & diet plan recommendations.
• Instant Member Invitation: Invitation codes are now generated immediately upon member creation.
• Dedicated Restore Hub: 1-click restore for deleted members, records, and associations with granular deletion options.
• Gym Rules & Agreements: Fixed rule agreement history loading, resolved UI display on compact screens, and made agreements permanent across sessions.
• Financial Ledger & Salary Enhancements: Improved pending dues calculation and automated membership transaction syncing.
• Performance enhancements and stability fixes across all screen sizes.
```

### Hindi / Hinglish:
```text
GymOS v1.0.3 (Build 20) naye features aur updates:
• Member Goal aur Workout/Diet Matching: Member ka goal edit karein aur automatically uske hisaab se diet & workout plan assign karein.
• Auto Invitation Code: Member create hote hi turant invitation code generate ho jata hai.
• 1-Click Restore Hub: Delete kiye gaye records aur members ko aasani se single click me restore karein.
• Gym Rules & Agreement Fix: Agreement history ab turant dikhai degi, chote phone screen par UI text fix ho gaya hai aur agreement permanent ho chuka hai.
• Ledger & Pending Dues: Member finance transaction auto-sync aur pending balance calculation me improvements.
• Performance aur stability me improvements.
```

---

## 🛠️ Key Improvements in this Build

### 1. Gym Rules & Agreement Engine
- **History View Fixed:** Resolved Gym ID UUID resolution so owner side "Agreements History" displays all agreed members accurately.
- **Small Screen Layout:** Fixed vertical text overflow on compact mobile devices in the Rules Preview tab with proper truncation and flexible wrapping.
- **Permanent Agreement:** Once agreed, agreement status is permanently locked into local storage and database, preventing accidental resets on logout or re-login.

### 2. Member Goal & Automatic Workout/Diet Matching
- Owners can now modify member goals at any time from member details.
- System automatically detects goal changes and assigns/suggests the appropriate diet and workout routine.
- Instant invitation code generation upon member registration without manual refresh.

### 3. Granular Deletion & Dedicated Restore Hub
- Granular deletion options when deleting a member (delete profile info only vs cascade finance/associations).
- Dedicated Restore Tab to view and restore deleted records with 1-click restore or batch restore.

### 4. Financial Ledger & Pending Balance Sync
- Fixed pending dues balance calculation and automated finance ledger sync whenever member plans or dues change.
- Staff salary payment management optimizations.
