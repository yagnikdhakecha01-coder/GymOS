# 🚀 GymOS Release v1.1.2 (Build 30)

### Release Name:
`1.1.2 (30) - Live Attendance Web Display, 16 KB Page Alignment & R8 Optimization`

---

### 📝 What's New & Release Notes:

#### 1. 🖥️ Official Live Attendance Display (`gymos.tech/attendance`):
- Launched the dedicated Reception / Front-Desk Smart TV & Tablet attendance display directly on `https://gymos.tech/attendance`.
- **Instant Device Pairing**: In the Gym Owner & Admin settings (Mobile & Web Portal), owners can now tap to copy their direct device link (`https://gymos.tech/attendance?display_id=...`) or launch it in browser with one tap.
- **Smart Setup Launcher**: Direct browser visitors without a link parameter can now easily input or paste their Display ID with automatic session persistence across TV/tablet reboots.
- **Dynamic Security QR**: Self-refreshing QR rotation prevents proxy attendance while keeping check-in instant (under 1 second).

#### 2. 📱 Edge-to-Edge Display Support (Android 15 Ready):
- Resolved Google Play recommendation: *"Edge-to-edge may not display for all users"*.
- Implemented `WindowCompat.setDecorFitsSystemWindows(window, false)` with transparent system navigation & status bars for immersive, modern edge-to-edge layouts on all Android devices.

#### 3. ⚡ R8 Code & Resource Shrinking (High Performance & Low Memory):
- Resolved Google Play recommendation: *"Improve your app's memory and performance with R8 optimization"*.
- Enabled R8 ProGuard minification and resource shrinking for leaner APK/AAB size, faster cold boot times, and hardened obfuscation.
- Preserved critical CameraX, MLKit barcode scanner, and Razorpay payment SDK classes to guarantee flawless runtime execution.

#### 4. ⚙️ 16 KB Native Library Page Alignment:
- Resolved Google Play recommendation: *"Recompile your app with 16 KB native library alignment"*.
- Fully aligned native libraries for Android 15 (targetSdk 35) 16 KB page-size hardware architecture.

---

### 📋 Play Store Console Release Summary (Paste this into Google Play Production Release):
```text
- Official Live Attendance Display: Launch front-desk TV/tablet check-in screens from gymos.tech/attendance.
- Easy Display Link Sharing: One-tap copy & browser launch for display device links in Owner Settings.
- Android 15 Compliance: Modern edge-to-edge layout support and 16 KB native page alignment.
- Enhanced Performance: Full R8 optimization and resource shrinking for faster load times and lower memory usage.
- General stability and security improvements.
```

---

### 📦 Target Build Numbers:
- **Version Name**: `1.1.2`
- **Version Code**: `30`
- **Output Artifact**: `GymOS_v1.1.2_b30.aab` / `gymos-release-v1.1.2-30.aab`
