# Phase 22: Isolated Web Portal with WhatsApp-Style QR Login & Persistent Multi-Role Access

## Goal
Build an isolated, dedicated Web Portal (`gymos_web/`) separate from the Android/iOS mobile application codebase to guarantee zero mobile regressions. Enable instant WhatsApp Web-style QR code login where gym owners, staff, and members can scan a browser QR code from their mobile app to log in immediately with persistent lifetime sessions and device tracking.

---

## Architectural Blueprint

```
+-------------------------------------------------------------+
|                     BROWSER (Web Portal)                    |
|  1. Opens web portal -> generates unique session UUID       |
|  2. Displays dynamic SVG QR Code on login screen            |
|  3. Listens on Supabase Realtime channel for session token   |
+------------------------------+------------------------------+
                               |
                        Scans QR code
                               |
                               v
+-------------------------------------------------------------+
|                 MOBILE APP (Android / iOS)                  |
|  1. Scanner detects "gymos_web_login" QR payload            |
|  2. Displays prompt: "Allow login on [Chrome / Windows]?"   |
|  3. On Approve: Calls secure Supabase RPC with user session |
+------------------------------+------------------------------+
                               |
                        Updates session
                               |
                               v
+-------------------------------------------------------------+
|                     SUPABASE BACKEND                        |
|  Table: `web_login_sessions`                                |
|  - token (UUID, PK)                                         |
|  - status ('pending' | 'approved' | 'expired')              |
|  - user_id, gym_id, role, device_name, approved_at          |
|  - RPC: `approve_web_login(token, device_name)`             |
+------------------------------+------------------------------+
                               |
                     Realtime Broadcast
                               |
                               v
+-------------------------------------------------------------+
|                     BROWSER (Web Portal)                    |
|  4. Realtime trigger receives approval payload              |
|  5. Saves persistent auth in LocalStorage (Never expires)   |
|  6. Routes to Owner / Staff / Member Dashboard seamlessly   |
+-------------------------------------------------------------+
```

---

## Detailed Task Breakdown

### Task 1: Supabase Database Migration for Web QR Sessions
- **SQL Migration**: `setup_web_qr_login_system.sql`
- **Tables & RPCs**:
  1. `web_login_sessions`:
     - `id` (UUID PK)
     - `token` (TEXT UNIQUE NOT NULL)
     - `user_id` (UUID REFERENCES auth.users)
     - `gym_id` (UUID REFERENCES gyms)
     - `role` (TEXT - 'owner' | 'staff' | 'member')
     - `device_name` (TEXT - browser/OS info)
     - `ip_address` (TEXT)
     - `status` ('pending' | 'approved' | 'expired')
     - `auth_token_payload` (JSONB - secure session transfer)
     - `created_at` (TIMESTAMPTZ DEFAULT now())
     - `expires_at` (TIMESTAMPTZ DEFAULT now() + INTERVAL '10 minutes')
  2. RLS Policies:
     - Public can insert/read pending sessions by token.
     - Authenticated mobile users can update sessions with their own `auth.uid()`.
  3. RPC `create_web_qr_session(p_device_info)`: Returns fresh token & expiry.
  4. RPC `approve_web_qr_login(p_token, p_device_name)`: Validates mobile user, binds user/role/gym data, marks approved.
  5. Enable Supabase Realtime publication on `web_login_sessions`.

---

### Task 2: Create Isolated Web Portal Project (`gymos_web/`)
- **Isolation Guarantee**: Created in a standalone directory `gymos_web/` so Android & iOS files in the root repo are never touched or modified.
- **Porting**:
  - Clone/adapt Flutter web project structure into `gymos_web/`.
  - Maintain identical theme (`lib/core/theme/theme.dart`), models, and repositories.
  - Setup responsive layout supporting both mobile-container and desktop-responsive views.

---

### Task 3: Build Web QR Code Login Screen
- **Location**: `gymos_web/lib/features/auth/web_qr_login_screen.dart`
- **Features**:
  - Automatically fetches fresh session token from Supabase.
  - Renders high-contrast, clean QR code with GymOS logo in center.
  - Timer countdown (refresh button after 5 minutes).
  - Browser/OS detection (e.g., "Windows 11 · Chrome") sent to session record.
  - Subscribes to Supabase Realtime channel `web_login:{token}`.
  - On approval:
    - Writes persistent credentials into browser `LocalStorage`.
    - Disables auto-logout/timeout completely (`keep_alive: true`).
    - Redirects to Owner, Staff, or Member dashboard according to role.
  - Alternative email/password login link for flexibility.

---

### Task 4: Mobile Scanner Integration (Android & iOS)
- **Goal**: Allow users to scan the Web QR using the existing mobile scanner without breaking existing attendance features.
- **Files**:
  - `lib/features/attendance/screens/qr_scanner_screen.dart` or navigation settings menu.
- **Logic**:
  - When scanner detects payload starting with `gymos_web_login:{token}`:
    1. Intercepts attendance flow.
    2. Opens confirmation modal:
       - Displays: *"GymOS Web Login Request"*
       - Device: *[Detected Browser & OS]*
       - Gym: *[Current Gym Name]*
       - User: *[Active Profile Name & Role]*
    3. User clicks **"Approve & Log In"**:
       - Calls RPC `approve_web_qr_login(token, device_name)`.
       - Shows success checkmark and returns to previous screen.
    4. User clicks **"Reject"**:
       - Marks session rejected and closes.

---

### Task 5: Persistent Web Session Management & Dashboard Routing
- **Location**: `gymos_web/lib/core/services/web_session_manager.dart`
- **Rules**:
  - **No Session Timeout**: Web sessions remain valid indefinitely until user explicitly clicks "Log Out".
  - **Auto-Restore**: On page reload/new tab, checks stored token and loads active dashboard directly without showing QR code again.
  - **Manual Logout**: Clear LocalStorage and redirect back to QR Login screen.
  - **Role-based Navigation**:
    - Owner -> Full Management Dashboard (Members, Staff, Finance, Subscriptions).
    - Staff -> Staff Portal (Attendance, Requests, Tasks).
    - Member -> Member Portal (Attendance, Workouts, Diets, Fees).

---

### Task 6: Verification & Cross-Platform Testing
- Verify mobile app builds cleanly on Android (`flutter build apk --debug`).
- Verify web portal compiles cleanly in `gymos_web/`.
- Test end-to-end QR scan flow:
  1. Open Web Portal on PC -> QR code renders.
  2. Scan from Mobile App -> Modal appears with device name.
  3. Tap Approve -> Web Portal immediately unlocks dashboard.
  4. Reload browser -> Session persists without asking to login again.
