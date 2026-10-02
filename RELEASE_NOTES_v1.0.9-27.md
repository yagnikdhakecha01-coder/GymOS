# 🚀 GymOS Release v1.0.9 (Build 27)

### Release Name:
`1.0.9 (27) - AutoPay Cancel, Dynamic Initials Avatar & Member Search`

---

### 📝 What's New & Release Notes:

#### 1. 💳 Seamless AutoPay Subscription Cancellation:
- Fixed subscription cancellation permissions and audit history logging in Supabase.
- Gym owners can now easily cancel AutoPay subscriptions directly from the app with instant confirmation and without encountering permission errors.

#### 2. 👤 Personalized Initials Avatars (No Dummy Photos):
- Completely eliminated generic placeholder photos across the platform.
- When a member or staff has not uploaded a photo, the app dynamically renders a clean, modern avatar displaying their uppercase initial with a personalized color palette based on their name.

#### 3. 🔍 Interactive Member & Trial Search:
- Introduced quick search in the Members tab. Gym owners and staff can now effortlessly search and filter members and trial leads by Name or Mobile Number in real-time.

#### 4. ⚡ 120 FPS Buttery-Smooth Staff Screen Scrolling:
- Optimized render tree and eliminated frame-drop bottlenecks on the Staff tab, ensuring fluid 60/120 FPS scrolling even with large staff rosters.

#### 5. 🔔 Instant Support Notifications & Deep-Linking:
- Real-time notification dispatch when admin responds to support tickets.
- Tapping on support notifications navigates directly into the specific ticket chat.

#### 6. 📅 Join-Date Announcement & Alert Filtering:
- Filtered historical announcements and notifications so new members and staff only view announcements published on or after their joining date.

---

### 📋 Play Store Console Release Summary (Paste this into Closed Testing):
```text
- Added easy AutoPay subscription cancellation with instant confirmation.
- Modernized profile avatars with personalized initials when no photo is uploaded.
- Added quick search by name and mobile number in the Members tab.
- Performance optimizations for ultra-smooth scrolling on staff and member lists.
- Real-time support ticket notification and instant chat navigation.
- General stability improvements and bug fixes.
```

---

### 📦 Target Build Numbers:
- **Version Name**: `1.0.9`
- **Version Code**: `27`
