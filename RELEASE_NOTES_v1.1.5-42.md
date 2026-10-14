# 🚀 GymOS Release v1.1.5 (Build 42)

### Release Name:
`1.1.5 (42) - Profile Persistence Hardening, Reception Broadcast Hub & CDN Cloud Avatars`

---

### 📝 What's New & Release Notes:

#### 1. 🛡️ Database Persistence Hardening across Owner & Staff Portals:
- Resolved missing database sync for critical member and staff fields: Date of Birth (DOB), Gender, Aadhaar Number, Biometric PIN / ID, Emergency Contact Name & Phone, Qualifications / Certifications, and Notes / Remarks.
- Ensured bi-directional real-time data persistence between Gym Owner portal, Receptionist portal, and Member profile sheets.
- Fixed Date of Birth & Gender visibility across Admin Website, Gym Dashboard, and Mobile App.

#### 2. 📢 Receptionist Broadcast Announcement Hub:
- Front-desk receptionists can now broadcast live announcements directly from the Receptionist Portal.
- Announcements are instantly synced into Supabase and distributed in real-time to all Gym Members and Staff.

#### 3. 🖼️ Permanent Cloud Avatar Preservation (High Definition):
- Profile pictures uploaded by gym owners or members are now permanently linked via high-speed Supabase Public CDN URLs.
- Eliminated token expiration and vanishing avatar links, guaranteeing persistent display across all devices and dashboards.

#### 4. ⚡ Biometric & Universal Face Attendance Sync:
- Real-time multi-terminal attendance integration logging exact entry timestamps for both members and staff.
- Automatic shift detection and dual-shift conflict resolution.

#### 5. 📱 Performance & Stability Polish:
- Android 15 ready with 16 KB page alignment, R8 code/resource shrinking, and edge-to-edge support.
- Streamlined member list caching and instantaneous search query response.

---

### 📋 Play Store Console Release Summary (Paste this into Google Play Production Release):
```text
- Profile Data Hardening: Fully audited cloud persistence for Date of Birth, Gender, Aadhaar, Emergency Contact, and Biometric PIN.
- Reception Broadcast Hub: Instant real-time announcement dispatch to all gym members and staff from reception portal.
- Permanent Cloud Avatars: High-definition profile pictures now permanently preserved via CDN without expiration.
- Real-Time Attendance Engine: Sub-second QR & face biometric check-in with exact timestamp logging.
- General performance improvements, Android 15 compatibility, and stability enhancements.
```

---

### 📦 Target Build Numbers:
- **Version Name**: `1.1.5`
- **Version Code**: `42`
- **Output Artifacts**: 
  - `GymOS_v1.1.5_b42.aab` (Root workspace)
  - `gymos-release-v1.1.5-42.aab` (Root workspace)
  - `build/app/outputs/bundle/release/app-release.aab`
