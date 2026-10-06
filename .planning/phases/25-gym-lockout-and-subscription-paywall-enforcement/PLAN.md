# Phase 25: Cross-Platform Gym Lockout, Anti-Tamper Database Gate & Web Portal Subscription Paywall Enforcement

## Goal
Implement a complete end-to-end gym lockout and subscription enforcement system across Android, iOS, and Web Portal (`gymos.tech/portal`). When a gym's free trial expires, paid plan ends, or AutoPay payment fails, the gym is immediately locked. The locked mobile app provides an unbypassable paywall directing the user to `gymos.tech/portal`, with a built-in QR scanner to log into the web portal. The web portal restricts locked accounts strictly to the Subscription payment page. In PostgreSQL, enforce cryptographic database-level RLS gates (`is_gym_subscription_active`) so that even if client UI is tampered with, all sensitive gym data remains inaccessible from the server until payment is verified.

---

## Architectural Blueprint

```
+-------------------------------------------------------------------------------------------------+
|                                 TRIGGER CONDITIONS (BACKEND / CRON / WEBHOOK)                    |
|  1. Free Trial Ended (trial_end < NOW()) AND No Paid Plan                                       |
|  2. Plan Expired (end_date < NOW()) AND AutoPay OFF (user cancelled auto-renewal)               |
|  3. AutoPay Payment Failed (Razorpay payment.failed webhook or card/bank decline)              |
|  => Sets subscriptions.status = 'expired', gyms.status = 'expired', gyms.is_locked = true       |
+-------------------------------------------------+-----------------------------------------------+
                                                  |
                                                  v
+-------------------------------------------------------------------------------------------------+
|                             POSTGRESQL ANTI-TAMPER SECURITY GATE (RLS)                          |
|  Function: public.is_gym_subscription_active(gym_id UUID) RETURNS BOOLEAN                       |
|  - Checks is_locked, expiry_date, trial_end_date.                                               |
|  - Updated `fn_user_accessible_gym_ids`: Returns EMPTY for locked gyms.                         |
|  - Tables Gated: members, staff, attendance, member_payments, expenses, workouts, diet plans   |
|  - Result: Even with tampered client UI / reverse engineering, PostgREST returns 0 rows / 403.  |
|  - EXCEPTION: subscriptions, gyms (status read-only), and web_login_sessions remain accessible.  |
+-------------------------------------------------+-----------------------------------------------+
                                                  |
                         +------------------------+------------------------+
                         |                                                 |
                         v                                                 v
+--------------------------------------------------+ +--------------------------------------------------+
|            MOBILE APP (Android & iOS)            | |             WEB PORTAL (gymos_web)               |
|  - Full-screen Lockout Overlay (Non-dismissible)  | |  - On login with locked gym:                   |
|  - Notice: "All subscriptions managed at         | |    Redirected/Locked strictly to Subscription   |
|    gymos.tech/portal"                            | |    Page (`OwnerSubscriptionScreen`).            |
|  - ACTION: "Scan Web Portal QR Code"             | |  - Sidebar navigation to Members/Staff/Finance |
|    (Opens scanner -> approves desktop login)     | |    is completely disabled & blocked.           |
|  - ACTION: "Copy Portal Link" / "Open in Browser"| |  - Shows Starter (₹699), Pro (₹999), Business   |
|  - Realtime listener: Automatically unlocks app  | |    (₹1999) with active Razorpay checkout.       |
|    the instant payment succeeds on web portal.   | |  - AutoPay toggle synchronously updates DB.     |
+--------------------------------------------------+ +--------------------------------------------------+
                         |                                                 |
                         +------------------------+------------------------+
                                                  |
                                    Razorpay Payment Succeeds
                                                  |
                                                  v
+-------------------------------------------------------------------------------------------------+
|                                ATOMIC PAYMENT VERIFICATION & UNLOCK                             |
|  - Razorpay Webhook (`payment.captured` / `order.paid`) or Edge Function `verify-payment`        |
|  - Updates `subscriptions`: status = 'active', start_date = NOW(), end_date = NOW() + 30 days   |
|  - Updates `gyms`: status = 'active', expiry_date = NOW() + 30 days, is_locked = false           |
|  - Realtime broadcast unlocks both Web Portal and Mobile App instantly!                        |
+-------------------------------------------------------------------------------------------------+
```

---

## Detailed Task Breakdown

### Task 1: Supabase Database Security & Lockout Migration
- **Target File**: `supabase/migrations/20261006_gym_lockout_and_rls_gate.sql` (applied via Supabase MCP)
- **Database Functions & Policies**:
  1. `is_gym_subscription_active(p_gym_id uuid) RETURNS boolean`:
     - Checks `gyms.is_locked`, `gyms.status`, `gyms.expiry_date`, `gyms.trial_end_date`.
     - Returns `false` if `is_locked = true` or `status IN ('expired', 'suspended')` or `expiry_date < now()`.
     - Returns `true` only if gym has a valid active trial or active paid plan.
  2. Update `fn_user_accessible_gym_ids(p_user_id uuid)`:
     - For non-super-admins, filters gyms through `is_gym_subscription_active(gym_id) = true`.
     - When locked, user receives empty list, ensuring zero member/staff/attendance data leaks.
  3. Ensure RLS isolation on financial tables (`expenses`, `finance_transactions`, `salaries`, `membership_payments`):
     - Attach `is_gym_subscription_active(gym_id)` check to SELECT and INSERT/UPDATE/DELETE.
  4. Update `process_razorpay_webhook` & `verify_payment` functions:
     - Set `gyms.is_locked = false`, `gyms.status = 'active'`, `gyms.expiry_date = v_end_date`.
  5. Add `lock_expired_gyms()` routine:
     - Automatically flags gyms as `is_locked = true` and `status = 'expired'` if validity date has passed and auto-pay is not active or payment failed.
  6. Ensure `web_login_sessions` table and `approve_web_qr_session` RPC remain 100% accessible to locked users so QR login to web portal always succeeds.

---

### Task 2: Mobile App Lockout Screen & QR Scan Workflow (`lib/`)
- **Target Files**:
  - `lib/features/dashboard/main_navigation_holder.dart`
  - `lib/features/attendance/owner_scanner_screen.dart`
  - `lib/features/subscription/owner_subscription_screen.dart`
  - `lib/features/authentication/auth_viewmodel.dart`
- **Implementation**:
  1. **Redesign Lockout Overlay / Screen**:
     - Remove obsolete generic "Unlock Gym" in-app modal.
     - Display premium, secure Lockout UI with:
       - Clear header: "Gym Access Locked".
       - Explanation: "Your free trial or active subscription plan has expired. All subscriptions are managed exclusively through the GymOS Web Portal: gymos.tech/portal".
       - Prominent Primary Button: **"Scan Web Portal QR Code"** (`Icons.qr_code_scanner_rounded`).
         - Immediately pushes `OwnerQRScannerScreen(isCheckIn: false)`.
         - Camera scans the login QR code displayed on `https://gymos.tech/portal`.
         - Seamlessly triggers `WebQrApprovalHelper.handleScan(context, code)` to authorize web session on desktop.
       - Secondary Action: **"Copy Portal Link"** (`https://gymos.tech/portal`) with quick toast and browser launch option.
       - Tertiary Action: **"Check Payment Status"** (calls `fetchSubscriptionStatus()` with subtle loading spinner).
  2. **Realtime Subscription Unlocking**:
     - Set up Supabase Realtime channel in `AuthViewModel` listening to `subscriptions` and `gyms` row updates for the active `gym_id`.
     - When payment is made on web portal, state automatically switches to unlocked without app restart.
  3. **AutoPay Toggle Sync**:
     - In `lib/features/subscription/owner_subscription_screen.dart`, when AutoPay is toggled off, call `cancel_autopay_subscription` RPC to persist `auto_pay = false`, `cancel_at_period_end = true`.
     - Display clear notice: "AutoPay is OFF. Your plan will expire on [Date] and will not be automatically renewed."

---

### Task 3: Web Portal Subscription Gate & AutoPay Enforcement (`gymos_web/`)
- **Target Files**:
  - `gymos_web/lib/features/dashboard/main_navigation_holder.dart`
  - `gymos_web/lib/core/widgets/desktop_web_sidebar.dart`
  - `gymos_web/lib/features/subscription/owner_subscription_screen.dart`
  - `gymos_web/lib/features/authentication/auth_viewmodel.dart`
- **Implementation**:
  1. **Locked Web Portal Gating**:
     - When logged in, if `authVm.isSubscriptionExpired || authVm.gymInfo?['is_locked'] == true`:
       - Do NOT render main dashboard tabs or sidebar navigation to Members, Staff, Finance, Attendance.
       - Render a dedicated full-screen layout containing `OwnerSubscriptionScreen()` with a prominent banner: "Your Gym Subscription is Expired / Locked. Please select a plan to restore full access."
       - Sidebar menu items (Members, Staff, Finance, More) are disabled or hidden so no other view can be opened.
  2. **Active Razorpay Plan Purchase**:
     - Starter (₹699), Pro (₹999), Business (₹1999) plans integrate directly with Razorpay using server-generated `order_id` and test key `rzp_test_TcCka8j9yi9xnH`.
     - On successful payment, Edge Function `verify-payment` sets `status = 'active'`, `is_locked = false`.
     - Web portal detects status change and immediately unlocks full navigation.
  3. **AutoPay Management & Sync**:
     - Ensure AutoPay toggle in `gymos_web/lib/features/subscription/owner_subscription_screen.dart` calls `cancel_autopay_subscription`.
     - Synchronously reflect AutoPay OFF state.
     - When AutoPay is OFF, no recurring charges occur; expiration triggers lock.

---

### Task 4: Edge Functions & Webhook Failure Handling
- **Target Files**:
  - `supabase/functions/razorpay-webhook/index.ts`
  - `supabase/functions/verify-payment/index.ts`
- **Implementation**:
  1. In `razorpay-webhook`:
     - Handle `payment.failed`, `subscription.halted`, `subscription.pending`:
       - Call database RPC to set `subscriptions.status = 'expired'`, `gyms.status = 'expired'`, `gyms.is_locked = true`.
     - In `payment.captured` / `order.paid`:
       - Ensure `gyms.is_locked = false`, `gyms.status = 'active'`, `gyms.expiry_date` extended by 30 days.
  2. In `verify-payment`:
     - Ensure HMAC-SHA256 signature verification atomically sets `is_locked = false` in both `subscriptions` and `gyms`.

---

### Task 5: Testing, Build & Deployment
1. **Flutter Analysis**:
   - Run `flutter analyze` on both mobile app (`lib/`) and web portal (`gymos_web/`).
2. **Build Web Portal**:
   - `flutter build web --release --base-href "/portal/"` in `gymos_web/`.
   - Copy output to `website/portal/`.
   - Commit & push to `gym-os-info-website` repository on `main`.
3. **End-to-End Verification**:
   - Test expired gym state: verify mobile app displays lockout screen with Web Portal notice and functional QR scanner button.
   - Test QR scanner from locked screen: scan `gymos.tech/portal` QR code -> approve login.
   - Verify web portal opens directly into Subscription page with locked navigation.
   - Test AutoPay toggle off: verify `auto_pay = false` in database.
   - Test database RLS: verify direct queries to `members`/`staff` return 0 rows for locked gym.
