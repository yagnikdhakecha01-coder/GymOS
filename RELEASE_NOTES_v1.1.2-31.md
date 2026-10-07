# 🚀 GymOS Release v1.1.2 (Build 31)

### Release Name:
`1.1.2 (31) - 16 KB Page Alignment, R8 Optimization & Live Attendance Web Display`

---

### 📝 What's New & Release Notes:

#### 1. ⚙️ Full Android 15 16 KB Memory Page Size Alignment:
- Resolved Google Play error: *"Your app does not support 16 KB memory page sizes"*.
- Enabled unbundled Google Play Services Barcode Scanning model, completely eliminating legacy 4 KB unaligned native binaries (`libbarhopper_v3.so`).
- Upgraded CameraX native pipeline to 1.4.1 for 16 KB ELF segment alignment across 64-bit architectures (`arm64-v8a`, `x86_64`).

#### 2. ⚡ R8 Code & Resource Shrinking (Lean & Fast):
- Enabled R8 ProGuard minification and resource shrinking for faster startup times and lower RAM consumption.
- Hardened ProGuard rules preserving MLKit, CameraX, and Razorpay SDK classes.

#### 3. 📱 Immersive Edge-to-Edge Experience:
- Resolved Google Play recommendation: *"Edge-to-edge may not display for all users"*.
- Implemented `WindowCompat.setDecorFitsSystemWindows(window, false)` with transparent system bars and cutout display handling.

#### 4. 🖥️ Official Live Attendance Display (`gymos.tech/attendance`):
- Launched dedicated Front-Desk Reception Smart TV / Tablet attendance display on `gymos.tech/attendance`.
- One-tap copy & browser launch for display device links in Owner Settings.
- Dynamic security QR rotation with sub-second check-in speed.

---

### 📋 Play Store Console Release Summary (Paste this into Google Play Production Release):
```text
- Android 15 Ready: Full 16 KB memory page size alignment and modern edge-to-edge layout support.
- Performance Boost: Full R8 optimization and resource shrinking for faster load times and lower memory usage.
- Official Live Attendance Display: Launch front-desk TV/tablet check-in screens from gymos.tech/attendance.
- Easy Display Link Sharing: One-tap copy & browser launch for display device links in Owner Settings.
- General stability and security improvements.
```

---

### 📦 Target Build Numbers:
- **Version Name**: `1.1.2`
- **Version Code**: `31`
- **Output Artifact**: `GymOS_v1.1.2_b31.aab` / `app-release.aab`
