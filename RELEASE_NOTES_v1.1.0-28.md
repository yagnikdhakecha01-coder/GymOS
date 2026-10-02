# 🚀 GymOS Release v1.1.0 (Build 28)

### Release Name:
`1.1.0 (28) - Smart Member Filters, Dynamic Card Views & Lag Elimination`

---

### 📝 What's New & Release Notes:

#### 1. 🎯 Smart Member Filters & Dynamic View Modes:
- Introduced a dynamic Sort & Filter bottom sheet in the Members overview.
- **Pending Fees View (Default)**: Highlights members with outstanding fees at the top with clear dues badges and next due dates.
- **Expiring Soon & Expired View**: Brings expired and soon-to-expire (0–7 days) members to the top with prominent expiry countdown badges for immediate renewal.
- **Recently Joined View**: Displays newly enrolled members with relative join date badges (`Joined Today`, `Joined 2d ago`).
- **Alphabetical View (A–Z)**: Sorts members alphabetically by name for quick lookup.
- Added visual active indicator dot on the filter icon when custom filters are applied.

#### 2. ⚡ 60/120 FPS Buttery-Smooth Performance (Zero Lag for 200+ Members):
- Eliminated per-pixel `setState()` scroll thrashing and off-screen GPU opacity layers on the Members tab.
- Added intelligent memoization in `MembersViewModel` to compute filtered and sorted lists only when data or filters change (O(1) frame delivery).
- Wrapped list cards in `RepaintBoundary` to prevent redundant rasterization during rapid flick and scroll.
- Deferred non-essential background fetches in `MemberProfileScreen` to post-frame callbacks, eliminating card-tap stutter and ensuring instant 60/120 FPS push transitions.

#### 3. 🛡️ Store-Compliant Center-Modal Update Dialog with Daily Snooze:
- Replaced the legacy full-screen blocking force update with a Google Play and App Store compliant center modal dialog.
- Added quick `[X]` close button and `Later` button with intelligent 24-hour daily snooze to prevent repetitive prompts on the same day.
- App startup remains completely functional and never locks users or reviewers out.

---

### 📋 Play Store Console Release Summary (Paste this into Closed Testing):
```text
- Smart Member Filters: Sort by Pending Fees, Expiring Soon, Recently Joined, or A-Z with dynamic card badges.
- Major Performance Boost: 60/120 FPS ultra-smooth scrolling and zero lag for gyms with 200+ members.
- Instant Member Profile open: Seamless and responsive transitions without stutter.
- Non-blocking center update modal with daily snooze option.
- General stability improvements and bug fixes.
```

---

### 📦 Target Build Numbers:
- **Version Name**: `1.1.0`
- **Version Code**: `28`
- **Output Artifact**: `gymos-release-v1.1.0-28.aab`
