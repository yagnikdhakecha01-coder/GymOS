# GymOS Biometric Access Control & Attendance Bridge Architecture

## 1. Executive Summary & Problem Statement
* **Objective:** Enable biometric/face-recognition gate access control devices (turnstiles/EM door locks) to integrate with GymOS.
* **Core Requirements:**
  1. **Gym-Specific Isolation (Multi-tenant):** Machine will strictly bind to a specific `gym_id`.
  2. **Offline-First Expiry Gatekeeper:** If gym internet drops, expired members **must be blocked at the door** (door stays locked, screen says "Expired"), while active members are granted entry.
  3. **Auto Attendance Sync:** Member punches must be recorded in GymOS Supabase `attendance_logs` table automatically when internet is available.
  4. **Low-End PC & Legacy OS Support:** Must run seamlessly on **Windows 7, 8, 10, and 11** with as low as **2 GB RAM and Dual-Core / Celeron processors**.
  5. **Zero Database Leak Security:** Physical device / bridge never receives direct database passwords or Supabase Service Role Keys.

---

## 2. Technology Stack Decision for Windows Bridge

### Selected Tech: **C# .NET Framework 4.8 (WinForms / Windows Service + System Tray App)**

| Framework / Tech | Windows 7 Support? | RAM Usage | Startup Speed | Native ZK/eSSL SDK Support | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **C# .NET Framework 4.8** | ✅ **100% Yes** (Win 7 SP1 - 11) | **~15 - 25 MB** | **< 0.5s** | ✅ **Direct (`zkemkeeper.dll`)** | ⭐ **WINNER (Selected)** |
| **Flutter for Windows** | ❌ **No** (Win 10+ required) | ~80 - 120 MB | ~2s | ⚠️ Requires C++ FFI | ❌ Rejected (No Win 7) |
| **Electron.js / Node** | ⚠️ Win 7 dropped in v23+ | ~200 - 350 MB | ~3 - 5s | ⚠️ Via node-zklib addon | ❌ Rejected (Heavy for low PC) |
| **Python (PyInstaller)** | ⚠️ Python 3.9+ drops Win 7 | ~60 - 90 MB | ~2s | ✅ PyZK | ⚠️ Needs older Python 3.8 |

### Why C# .NET 4.8 + WinForms?
1. **Pre-installed in Windows:** .NET 4.x is already built into modern Windows, and easily runs on Windows 7 SP1.
2. **Minimal Footprint:** Uses less than 25 MB of RAM, leaving 99% of the receptionist's computer free.
3. **Hardware Driver:** All ZKTeco, eSSL, Realtime biometric devices provide native COM DLLs (`zkemkeeper.dll`) specifically compiled for C#/.NET.
4. **Installer:** Packaged using **Inno Setup** into a tiny **~5 MB single `.exe`** with 1-click install.

---

## 3. System Architecture & Data Flow

```
[ Gate Biometric Machine ] (ZKTeco / eSSL / Hikvision)
      │
      │  Local LAN (TCP Port 4370)
      ▼
[ GymOS Windows Bridge Agent ] (Runs on Reception PC, Tray Icon)
      │  - Listens to Punch Events
      │  - Caches offline in SQLite (if broadband drops)
      │  - Syncs validity dates to machine memory
      │
      │  HTTPS TLS 1.3 (Signed with Gym Secret API Key)
      ▼
[ GymOS Cloud API / Supabase Edge Function ]
      │  - Authenticates Gym Token + Device Serial
      │  - Isolated to `gym_id`
      ▼
[ Supabase Database ]
      - `attendance_logs`
      - `members`
```

---

## 4. How the Core Features Function

### A. Offline Expiry Protection (Without Internet)
1. When online, the Bridge syncs active members and their `expiry_date` directly into the biometric machine's local user memory (`ValidUntil` field).
2. If internet cuts out:
   * The machine uses its internal hardware clock (RTC).
   * If `Today > ExpiryDate`: Machine triggers "Access Denied / Expired" alert. Relay stays deactivated (Door locked).
   * If `Today <= ExpiryDate`: Machine unlocks door and saves punch in internal memory buffer.

### B. Accurate Member Mapping (Enrollment Flow)
1. **GymOS Member ID:** Member is created in GymOS with a clean numeric Biometric PIN (e.g. `1024`).
2. **Device Enrollment:** Member's face/fingerprint is enrolled on the gate machine under User ID `1024`.
3. **Punch Event:** Machine reports `User ID 1024 punched at 08:30:00`.
4. **GymOS Resolution:** Database matches `gym_id` + `biometric_pin: 1024` -> `Member: Rahul Sharma`. Attendance marked!

### C. Zero Database Leak Security
* Neither the biometric machine nor the Windows PC ever receives the Supabase database password, DB URL, or Service Role Key.
* Communication happens via an encrypted API endpoint with a unique **Gym Secret Token** (`GYMOS-SEC-XXXX`).
* Even if someone tampers with the reception PC or inspects the Wi-Fi traffic, they only see hashed punch payloads, never database credentials.

---

## 5. Implementation Roadmap (For Future Execution)
When ready to build:
1. **Phase 1: Backend Setup:**
   * Create `gym_biometric_devices` table in Supabase.
   * Add `biometric_pin` column to `members` table.
   * Create `POST /api/biometric/sync-punches` Edge Function with rate limiting and secret key validation.
2. **Phase 2: Windows Bridge Software:**
   * Build C# .NET 4.8 System Tray application.
   * Integrate ZKTeco/eSSL SDK (`zkemkeeper.dll`) for LAN connection.
   * Add local SQLite queue for offline buffering.
   * Create Inno Setup 1-click `.exe` installer.
3. **Phase 3: GymOS Owner App UI:**
   * Add "Biometric Devices" section in Gym Settings.
   * Show device connection status (Online/Offline, Last Synced).
   * Provide download button for `GymOS-Bridge-Setup.exe`.
