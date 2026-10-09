# Phase 32: Universal Face & Biometric Terminal Integration (Offline-First, Zero-Server-Cost & Real-Life Linking)

**Phase:** 32  
**Milestone:** GymOS v1.3  
**Status:** 🟡 Ready to Execute  
**Mode:** tracer-first  

---

## 1. Real-World Problem Statement & Core Principles

### The Real-World Scale Challenge:
* **Target Scale:** 1,000+ gyms, with ~950 gyms running physical Face Recognition / Biometric turnstiles and door locks.
* **Why Cloud Verification Fails in Real Life:**
  1. **Latency & Door Stalls:** If every member standing at the gate requires a Supabase cloud roundtrip to verify, door opening takes 1–3 seconds instead of 200ms. Long queues form at reception.
  2. **Broadband Dropouts:** Gym internet cuts out frequently in India. If access control depends on cloud requests, **the entire gym gets locked out** and members cannot enter.
  3. **Astronomical Server Cost:** 1,000 gyms × 200 members × 2 punches/day = **400,000 cloud requests/day (12 Million/month)**. Database CPU, edge compute, and egress costs would skyrocket.

### The GymOS Solution (Offline-First Hardware Gatekeeper):
1. **Hardware-Local Decision Making (Zero Latency, Zero Server Cost):**
   - The physical machine (eSSL/ZKTeco) stores all face biometric templates, names, and **validity expiration dates directly in its internal memory / RTC**.
   - When a member looks at the camera, the machine verifies the face locally in **< 0.2 seconds** and checks the expiration date offline.
   - If active: door unlocks instantly with "Thank You".
   - If expired: door stays locked with "Access Denied / Expired" alert.
   - **Zero Supabase calls at punch time! Zero cloud cost! 100% offline-proof!**

2. **Event-Driven Delta / Diff Synchronization (Ultra-Low Bandwidth):**
   - Supabase NEVER sends full member lists repeatedly.
   - Only when an event occurs in GymOS:
     - New member created → Delta pushed: `SET_USER (PIN, Name, Expiry)`
     - Membership renewed → Delta pushed: `UPDATE_EXPIRY (PIN, NewEndDate)`
     - Member expired / blocked → Delta pushed: `DISABLE_USER (PIN)`
     - Member deleted → Delta pushed: `DELETE_USER (PIN)`
   - 1,000 gyms × ~3 membership events/day = **only ~3,000 tiny delta updates platform-wide per day** (~few kilobytes of data).

3. **Real-Life Face-to-Member Linking Workflow:**
   - **Flow 1 (App-to-Device Pre-provisioning - Preferred):**
     - Receptionist creates member "Rahul Sharma" in GymOS.
     - App auto-allocates next available PIN: `#105`.
     - GymOS pushes user `105 ("Rahul S")` to the machine with validity date.
     - Member stands at the machine; receptionist selects User `105` on device screen → "Enroll Face" (camera scans face in 3 seconds). Done!
   - **Flow 2 (Unlinked Punch Discovery - Fail-Safe for Pre-enrolled Gyms):**
     - If the gym already enrolled 80 members on the eSSL machine before using GymOS, or receptionist enrolls face directly on device:
     - When that user punches, GymOS receives punch with `PIN #82`.
     - GymOS detects: `PIN #82 is not linked to any member in this gym`.
     - App shows notification: *"Unlinked Face Detected (PIN #82 punched at 8:30 AM) — Tap to Link"*.
     - Owner selects member name with 1 tap → Linked permanently!

---

## 2. End-to-End System Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              REAL-LIFE GYMOS ARCHITECTURE                              │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│  [ GYMOS MOBILE APP ]                                                                  │
│    │                                                                                   │
│    │── Member Added / Renewed ─────────────────────────────────────────────────────────┐│
│    │                                                                                   ││
│    ▼                                                                                   ││
│  [ SUPABASE DATABASE ]                                                                 ││
│    • `biometric_sync_queue` (Only stores tiny DELTA events: PIN, Action, Expiry)       ││
│    • `attendance_logs` (Records historical attendance when synced)                     ││
│    • Triggers fire ONLY on membership change, NOT on polling                           ││
│    │                                                                                   ││
│    │ (Delta Events Only - No Heavy Polling)                                            ││
│    ▼                                                                                   ││
│  [ DISPATCH LAYER: Cloud ADMS Edge Fn OR Local Windows Bridge ]                        ││
│    │                                                                                   ││
│    │── Pushes Delta (e.g. "PIN 105: Valid until 2026-12-31, Access: ALLOWED") ─────────││
│    ▼                                                                                   ││
│  [ eSSL FACE RECOGNITION TERMINAL ]                                                    ││
│    ┌──────────────────────────────────────────────────────────────────────────────┐    ││
│    │  INTERNAL FLASH & RTC MEMORY:                                                │    ││
│    │  • User 105 (Rahul S) -> Face Vector Data -> ValidUntil: 2026-12-31          │    ││
│    │  • User 106 (Pooja M) -> Face Vector Data -> ValidUntil: 2026-10-01 (EXPIRED)│    ││
│    └──────────────────────────────────────────────────────────────────────────────┘    ││
│         │                                                                              ││
│         │ Member looks at camera:                                                      ││
│         ├─ If Today <= 2026-12-31: LOCAL RELAY UNLOCKS DOOR (0.2s, 0 HTTP Calls)       ││
│         └─ If Today > 2026-10-01: LOCAL RELAY STAYS LOCKED ("ACCESS DENIED")           ││
│                                                                                        ││
│         │ (Later, punches batched to GymOS attendance_logs for owner reports)          ││
│         └──────────────────────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Database & Backend Layer (Wave 1)

### 3.1. Tables & Schema

1. **`gym_biometric_devices` Table:**
   - Multi-tenant device registry.
   - `id`: UUID PRIMARY KEY
   - `gym_id`: UUID REFERENCES gyms(id) ON DELETE CASCADE
   - `device_name`: TEXT (e.g. "Main Gate Face Terminal")
   - `device_brand`: TEXT (e.g. "eSSL", "ZKTeco", "Realtime", "Hikvision")
   - `device_category`: TEXT ("face", "fingerprint", "turnstile", "hybrid")
   - `device_serial_number`: TEXT (Unique hardware SN, e.g. "CK99812401")
   - `connection_mode`: TEXT ("cloud_adms" or "lan_bridge")
   - `status`: TEXT ("online", "offline")
   - `last_heartbeat`: TIMESTAMPTZ
   - `last_punch_at`: TIMESTAMPTZ
   - `total_punches_synced`: BIGINT DEFAULT 0

2. **`biometric_sync_queue` (Delta Command Queue):**
   - Stores pending commands waiting for device sync:
     - `gym_id`, `member_id`, `biometric_pin`, `user_name`, `command_type` (`SET_USER`, `UPDATE_EXPIRY`, `DISABLE_USER`, `DELETE_USER`), `expiry_date`, `is_access_allowed`, `sync_status` (`pending`, `synced`, `failed`).
   - Cleaned up or indexed with `WHERE sync_status = 'pending'` for sub-millisecond query time.

3. **`unlinked_biometric_punches` (Discovery Table for Existing Gym Machines):**
   - When a punch arrives with a PIN not found in `members` or `staff`, it is saved here with device info and timestamp.
   - Allows owner to map existing members without having to re-enroll everyone!

### 3.2. Automated Triggers (Zero Manual Effort):
- **`trg_member_membership_biometric_sync`**:
  - When membership is created, renewed, or extended: automatically calculates latest `MAX(end_date)`.
  - Enqueues `UPDATE_EXPIRY` or `SET_USER` delta into `biometric_sync_queue`.
- **`trg_member_status_biometric_sync`**:
  - When member status changes to `inactive` / `cancelled`: enqueues `DISABLE_USER`.
  - When restored to `active`: enqueues `SET_USER` with current expiry date.

### 3.3. Database RPCs:
1. `get_gym_biometric_devices(p_gym_id UUID)`
2. `upsert_gym_biometric_device(...)`
3. `delete_gym_biometric_device(p_device_id UUID)`
4. `get_next_available_biometric_pin(p_gym_id UUID)`:
   - Returns lowest available integer PIN (e.g. 101, 102...) so receptionist doesn't have to guess.
5. `enqueue_full_gym_member_biometric_sync(p_gym_id UUID)`:
   - One-tap button if owner gets a new machine and wants to dump all members at once.
6. `get_unlinked_biometric_punches(p_gym_id UUID)`:
   - Returns list of unrecognized PIN punches for 1-tap linking in the app.
7. `link_biometric_pin_to_member(p_gym_id UUID, p_member_id UUID, p_pin INT)`:
   - Links PIN to member, resolves raw punches, and enqueues expiry sync.

---

## 4. Hardware Communication & Edge Function (Wave 2)

### 4.1. Edge Function: `supabase/functions/biometric-adms/index.ts`
Designed specifically for eSSL / ZKTeco Cloud Server / ADMS push:
1. **Device Handshake (`GET /cdata?SN=<device_sn>&options=all`)**:
   - Matches device SN to `gym_biometric_devices`.
   - Returns config header instructing device to push real-time face logs.
2. **Attendance Log Push (`POST /cdata?SN=<device_sn>&table=ATTLOG`)**:
   - Ingests tab-delimited punch lines: `PIN`, `DateTime`, `Status`, `VerifyType` (15 = Face).
   - Records attendance into `attendance_logs` and `biometric_punches_raw`.
   - If PIN is unknown, records to `unlinked_biometric_punches`.
   - Responds: `OK: <count>`.
3. **Delta Command Polling (`GET /getrequest?SN=<device_sn>`)**:
   - Queries `biometric_sync_queue WHERE gym_id = ... AND sync_status = 'pending'`.
   - Returns eSSL commands:
     - New/Update: `C:1:DATA USER PIN=105\tName=Rahul S\tExpires=2026-12-31\tDisable=0\n`
     - Expired/Disabled: `C:2:DATA USER PIN=106\tDisable=1\n`
   - Returns `OK` if no commands pending (consumes near-zero CPU).
4. **Command Acknowledgment (`POST /devicecmd?SN=<device_sn>`)**:
   - Marks commands as `synced` in Supabase.

### 4.2. Local LAN Bridge Updates (`biometric/gymos_biometric_bridge.js` & `.py`):
For gyms using Reception PC to connect over local Wi-Fi (Port 4370):
- Connects to eSSL/ZKTeco machine via TCP socket.
- Translates `biometric_sync_queue` delta updates to machine memory via ZK protocol `SSR_SetUserInfo`.
- Automatically sets User Expiration Date in machine memory.
- Captures punches with verify mode `15` as `FACE_SCAN`.

---

## 5. Owner App Mobile UI & Member Linking (Wave 3)

### 5.1. Attendance Settings Upgrade:
- File: `lib/features/attendance/owner_settings_screen.dart`
- Upgraded Biometric & Face Card:
  - Header: "Biometric & Face Access Terminals"
  - Active device summary badge (e.g. `1 Face Machine Connected • Online`)
  - "Manage Devices & Live Sync →" button opening `BiometricDevicesScreen`.

### 5.2. New Screen: `lib/features/attendance/biometric_devices_screen.dart`:
1. **Hardware List & Connection Status:**
   - Card for each device:
     - Device Name: "Main Turnstile Face Terminal"
     - Brand: `eSSL AiFace` | Category: `Face Recognition`
     - Connection Mode: `Direct Cloud ADMS` or `Local PC Bridge`
     - Status: Live pulse indicator (`Online • 2 mins ago` or `Offline`)
     - Total Punches synced today / all time.
2. **Device Setup Wizard (Modal):**
   - Simple 3 steps designed for gym owners:
     - **Step 1:** Select Brand (`eSSL`, `ZKTeco`, `Realtime`, etc.) & Category (`Face Recognition`).
     - **Step 2:** Choose Connection:
       - **Cloud ADMS (Direct)**: Enter Device Serial Number (SN). Shows exact Server Address and Port 443 with copy button and screenshot guide of eSSL menu.
       - **PC Bridge (Local LAN)**: Shows PC Bridge download link and Gym Secret Key.
     - **Step 3:** Test Connection & Save.
3. **Unlinked Face Punches Discovery Sheet:**
   - If an unmapped face punches on the device:
     - Shows alert: `"Found 2 faces enrolled on machine not linked to GymOS members"`.
     - Tap to open sheet -> Lists `PIN #82 (Punched at 8:30 AM)` -> Tap "Link to Member" -> Dropdown of gym members -> Linked in 1 tap!
4. **"Sync All Members" 1-Tap Action:**
   - Pushes all active gym members with current plan end dates to the queue.

### 5.3. Member Form Integration (`add_member_wizard_screen.dart` & `member_profile_screen.dart`):
1. **Add Member Wizard:**
   - "Biometric / Face User ID" field.
   - Includes **"Auto-Assign Free PIN"** button: instantly fetches next free number (e.g. `105`) so receptionist doesn't have to check.
   - Explanatory note: *"User 105 will be sent to the face machine with membership expiry. Simply enroll face for User 105 on the device."*
2. **Member Profile Screen:**
   - Displays Face Access Status:
     - Active: `Face Access: Active (Valid till 30 Dec 2026)` (Green badge)
     - Expired: `Face Access: Gate Locked (Plan Expired)` (Amber badge)
   - Owner can tap to re-sync or change PIN.

---

## 6. Testing & Simulator Utilities (Wave 4)

1. **Hardware Test Simulator (`biometric/test_face_punch_simulator.js`):**
   - Command-line tool that simulates:
     - eSSL Cloud ADMS handshake (`GET /cdata`)
     - Face punch push (`POST /cdata` with PIN and Face Verify mode `15`)
     - Delta command reception (`GET /getrequest` verifying expired members receive `Disable=1`)
   - Allows verifying end-to-end flow without requiring physical turnstile hardware on developer machine.
2. **Static Analysis & Flutter Quality Gates:**
   - Run `flutter analyze` ensuring zero warnings or compilation errors.

---

## 7. Implementation Waves Checklist

### Wave 1: Database Schema & RPCs
- [ ] Create `setup_universal_face_biometric_system.sql`.
- [ ] Upgrade `gym_biometric_devices` table with brand, category, serial number, connection mode.
- [ ] Create `unlinked_biometric_punches` table for smart member discovery.
- [ ] Add triggers for membership creation/renewal/status change to populate `biometric_sync_queue`.
- [ ] Implement RPCs: `get_gym_biometric_devices`, `upsert_gym_biometric_device`, `delete_gym_biometric_device`, `get_next_available_biometric_pin`, `enqueue_full_gym_member_biometric_sync`, `get_unlinked_biometric_punches`, `link_biometric_pin_to_member`.

### Wave 2: Cloud ADMS Edge Function & Bridge Updates
- [ ] Create `supabase/functions/biometric-adms/index.ts` handling eSSL ADMS protocol (`/cdata`, `/getrequest`, `/devicecmd`).
- [ ] Update `biometric/gymos_biometric_bridge.js` and `gymos_biometric_bridge.py` for face verify mode (15) and offline expiry write.
- [ ] Create `biometric/test_face_punch_simulator.js` testing tool.

### Wave 3: Mobile UI & Face Linking Experience
- [ ] Create `lib/features/attendance/biometric_devices_screen.dart` with device cards, status badges, and unlinked punch mapper.
- [ ] Implement `DevicePairingWizardSheet` supporting eSSL Cloud ADMS and PC Bridge modes.
- [ ] Update `owner_settings_screen.dart` with upgraded biometric card and navigation.
- [ ] Add `Auto-Assign Free PIN` in `add_member_wizard_screen.dart` and `member_profile_screen.dart`.
- [ ] Add Face access validity indicator badge on member profile.

### Wave 4: Release Verification & Quality Gates
- [ ] Run `flutter analyze` ensuring 0 errors.
- [ ] Verify unit & simulator tests.
- [ ] Document owner pairing guide for eSSL Face terminals.
