# 🚀 GymOS Release v1.1.1 (Build 29)

### Release Name:
`1.1.1 (29) - Multi-Role Account Persistence & Profile Switcher Fix`

---

### 📝 What's New & Release Notes:

#### 1. 🛡️ Multi-Role Account Persistence (Zero Unwanted Role Switching):
- Resolved a critical bug where accounts with multiple roles on the same email (e.g. Gym Owner and Gym Member) automatically switched to the Member profile upon restarting the app or after periodic token refresh.
- Prevented background auth lifecycle listeners from overwriting active Owner/Staff role and gym info in persistent storage.
- Added deterministic `keyActiveAssociationId` storage in local preferences to restore the exact active session across cold boots.
- If multiple profiles exist and no prior active association is recorded, the app cleanly presents the Profile Selector rather than forcing a member profile.

#### 2. 🔄 Unified Cross-Role Profile Switcher ("My Profiles"):
- Unlocked all user associations across roles (Gym Owner, Gym Staff, Gym Member) in the "My Profiles" switcher bottom sheet.
- Added visual indicators and confirmation dialogs when transitioning between Owner, Staff, and Member interfaces.
- Seamless state clearing and reload across all viewmodels upon switching contexts.

#### 3. ⚡ General Improvements & Stability:
- Guaranteed persistent owner dashboard state across app restarts.
- Optimized association resolution order with fallback verification.
- Improved reliability of background session keep-alive.

---

### 📋 Play Store Console Release Summary (Paste this into Closed Testing):
```text
- Multi-Role Account Fix: Fixed automatic switching to member profile for users with both Owner and Member roles on the same email.
- Profile Switcher: Seamlessly switch between Owner, Staff, and Member profiles from "My Profiles".
- Deterministic session restoration across app restarts and token refreshes.
- General performance and stability enhancements.
```

---

### 📦 Target Build Numbers:
- **Version Name**: `1.1.1`
- **Version Code**: `29`
- **Output Artifact**: `gymos-release-v1.1.1-29.aab` / `GymOS_v1.1.1_b29.aab`
