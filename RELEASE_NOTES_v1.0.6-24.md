# 🚀 GymOS Release v1.0.6 (Build 24)

### Release Name:
`v1.0.6-24 - Biometric Attendance & Gate Access Integration (PC Bridge + Direct Cloud)`

---

### 📝 What's New & Release Notes:

#### 1. 🎛️ Biometric Attendance in Verification Methods:
- **New Verification Options**: Owner Attendance Settings me **Attendance Verification Method** dropdown ke andar ab:
  - `Static QR Code`
  - `Dynamic QR (Auto Refresh)`
  - `Biometric (Fingerprint & Face)`
  - `QR + Biometric (Both)`
- **Prominent Card Placement**: `Biometric` ya `QR + Biometric` select karte hi Biometric Configuration Card seedhe Verification Method ke niche screen par display ho jata hai.

#### 2. ⚡ Flexible Integration Modes:
- **PC Sync Bridge (Recommended - Offline Safe)**:
  - Physical machines (eSSL, ZKTeco, Realtime) gym reception PC ke local network se judti hain.
  - Internet chala jaye ya PC power cut/shutdown ho jaye, to bhi local SQLite WAL buffer me attendance surakshit rehti hai aur internet aane par auto-sync hoti hai.
- **Direct Cloud / Webhook (eSSL ADMS / Realtime Cloud)**:
  - Smart devices jisme direct SIM card ya WiFi Cloud ADMS push support hai, wo direct Cloud Webhook URL par punches push kar sakte hain.

#### 3. 🔄 2-Way Member Expiry & Gate Lock Sync:
- Owner mobile app me jab bhi kisi member ka membership renew, add, ya edit karta hai, database trigger machine ke hardware memory me automatic nayi validity date feed kar deta hai.
- Membership expire hone par machine turnstile/gate access deny kar deti hai (bina internet ke bhi!).

#### 4. 👤 Member Biometric PIN Linking:
- Add Member Wizard (Step 1) aur Member Profile Screen me Biometric PIN input aur live status badge display add kiya gaya hai.
- Scoped strictly by `(gym_id, biometric_pin)` composite key ensuring **zero cross-gym leakage**.

---

### 📦 Release Artifacts:
- **Play Store Bundle (Closed Testing)**: `build/app/outputs/bundle/release/app-release.aab`
- **Standalone APK**: `build/app/outputs/flutter-apk/app-release.apk`
- **PC Reception Bridge Package**: `GymOS_PC_Biometric_Bridge.zip`
