# GymOS Universal Face & Biometric Integration Guide

## 1. Multi-Tenant Architecture & Data Isolation (1,000+ Gyms Safe)
GymOS is engineered to support 1,000+ gyms and thousands of biometric & face terminals with **strict tenant isolation**:

- **Unique Hardware Binding**: Each physical terminal is bound to a single gym via its Serial Number (`device_serial_number`). A hardware unique constraint prevents any other gym from claiming or receiving logs from a machine already paired with your gym.
- **Gym Fence on Every Punch**: When a face punch arrives at the GymOS ADMS cloud gateway, the server immediately resolves the gym owner from the Serial Number. Even if two gyms use identical PIN numbers (e.g., Member #101), the punch is strictly recorded within the respective gym's ledger.
- **Zero Cross-Gym Leakage**: A machine from Gym A can never unlock or affect Gym B.

---

## 2. Offline-First & Zero Cloud Latency Guarantee

```
[ Member Steps Up to Turnstile ]
               │
               ▼
   [ Face Camera Scan (0.2s) ]
               │
               ▼
[ Checks Local Hardware Memory (Expiry & Access) ]
               │
     ┌─────────┴─────────┐
     ▼                   ▼
 [ Valid ]           [ Expired ]
  Door Unlocks        Access Denied ("Expired")
     │
     ▼ (Async Delta Push)
 [ GymOS Cloud Records Attendance ]
```

- **Hardware Gatekeeper**: Verification happens **100% locally on the eSSL machine's internal DSP / Flash memory**.
- **No Cloud Roundtrips**: When a member looks into the face camera, the door unlocks in 200 milliseconds without calling Supabase first.
- **Zero Gym Lockouts**: If your gym's internet or WiFi goes down, verified members can still enter seamlessly.
- **Cost Efficient**: You do not incur millions of database queries for turnstile checks. Only delta changes (new members, renewals, cancellations) are synced to the machine.

---

## 3. How to Connect Your eSSL Face Machine (2-Minute Setup)

### Step 1: Open GymOS App
1. Open the **GymOS App** on your phone.
2. Go to **Settings** → **Attendance & Automation** → **Biometric & Face Machines**.
3. Tap **"+ Add Terminal"**.
4. Select **eSSL Face Terminal (Cloud ADMS)**.
5. Enter a friendly name (e.g. *Main Entrance Gate*) and your machine's **Serial Number (SN)** found on the back of the device or in the system info menu.

### Step 2: Configure the eSSL / ZKTeco Machine Menu
On the physical eSSL Face machine:
1. Press the **M/OK** button to enter the main menu.
2. Go to **Comm. (Communication)** → **Cloud Server Server / ADMS / Web Server Settings**.
3. Configure the following fields:
   - **Enable Domain Name**: `ON` (or `Yes`)
   - **Server Address**: `gilxxyvwqucwwwqaxosx.supabase.co`
   - **Server Port**: `443` (Enable HTTPS / SSL if prompted, or port `80`)
   - **Enable Proxy Server**: `OFF`
4. Save and exit to the home screen.
5. Within 30 seconds, your device in the GymOS app will turn **Green (Online Pulse)**!

---

## 4. Member Enrollment & Linking Flows

### Option A: Pre-Provisioning Flow (Recommended)
1. In the GymOS app, tap **Add Member**.
2. Tap **"Auto-Assign PIN"** (e.g., `#105`).
3. Complete the member registration. GymOS automatically pushes PIN #105 and their membership expiry date to the terminal.
4. On the eSSL machine:
   - Press **M/OK** → **User Mgt** → **Add User** → Enter User ID **105**.
   - Select **Face** and ask the member to look into the camera for 3 seconds.
   - Save. Member is now permanently linked!

### Option B: Discovery Flow (For Existing Gyms with Pre-Enrolled Faces)
If your members are already enrolled in your machine:
1. When any member scans their face at the turnstile, GymOS captures the unmapped punch into **"Unlinked Punches"**.
2. In the GymOS app, an alert banner will appear:
   > *"Unlinked Face Punch Found: User #105 scanned on Main Gate"*
3. Tap **"Link Member"**, search for the member's name in GymOS, and tap **"Confirm Link"**.
4. The PIN and all past punches are immediately linked to the member profile!

---

## 5. Testing & Verification

You can simulate or test your machine anytime from the developer console:
```bash
# Test Handshake and Face Punch
node biometric/test_face_punch_simulator.js <YOUR_DEVICE_SERIAL_NUMBER> 101
```
