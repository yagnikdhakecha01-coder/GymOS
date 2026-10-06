# Phase 26: Live Razorpay AutoPay Integration, Secure Secret Management & Web-Only Production Checkout

## Goal
Transition the GymOS payment infrastructure from Razorpay Test API to live production API using live credentials (`rzp_live_TkaAcBNqI1IitC`). Store all API secrets strictly in Supabase server-side environment secrets with zero leakage in edge functions or client code. Create and sync 4 recurring AutoPay plans (Starter ₹699/mo, Pro ₹999/mo, Business ₹1999/mo, and ₹1/mo Test Plan for 1-month AutoPay testing). Enforce strictly web-portal-only checkout (`gymos.tech/portal`) to maintain 100% compliance with Google Play and Apple App Store guidelines, compile production web bundle, and push to GitHub.

---

## Architectural Blueprint

```
+---------------------------------------------------------------------------------------------------+
|                                  LIVE CREDENTIAL SECURITY ARCHITECTURE                            |
|                                                                                                   |
|  Live Key ID:     rzp_live_TkaAcBNqI1IitC (Public checkout key, injected in gymos_web)             |
|  Live Key Secret: q64LYR5PXXqLyMVmlSzpriZc (STRICTLY SERVER-SIDE in Supabase Project Secrets)      |
|                                                                                                   |
|  [ Supabase Project Secrets ]  -->  Deno.env.get("RAZORPAY_KEY_SECRET") (Isolated in Edge Runtime)  |
|         |                                              |                                          |
|         v                                              v                                          |
|  [ Database / Vault ]                [ create-subscription / verify-payment / webhook ]           |
|                                     (NEVER logs secret, NEVER exposes secret in responses)        |
+---------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+---------------------------------------------------------------------------------------------------+
|                                  RECURRING AUTOPAY PLANS MATRIX                                   |
|  1. Starter Plan:  ₹699 / month  -->  plan_TLBEs2n479kKl6 (Live Razorpay)                         |
|  2. Pro Plan:      ₹999 / month  -->  plan_TLBAK4LFyPSGxf (Live Razorpay)                         |
|  3. Business Plan: ₹1999 / month -->  plan_TLBBMMUhI7sBd6 (Live Razorpay)                         |
|  4. Test Plan:     ₹1 / month    -->  plan_TkaKSZ86fTigEG (Live Razorpay, 1 Rs for 1 Month test)   |
|                                                                                                   |
|  Synchronized into: public.subscription_plans (with valid DB constraints on gyms & subscriptions) |
+---------------------------------------------------------------------------------------------------+
                                                 |
                                                 v
+---------------------------------------------------------------------------------------------------+
|                                 STRICT PLATFORM ISOLATION ENFORCEMENT                             |
|                                                                                                   |
|  [ Mobile App: Android & iOS ]                [ Web Portal: gymos.tech/portal ]                   |
|  - ZERO Razorpay SDKs or payment buttons      - Full Razorpay Web Modal Checkout                 |
|  - Strictly QR code & URL lock screen          - 4 Active Plans (Starter, Pro, Business, Test 1Rs) |
|  - Zero In-App Purchase compliance violation   - AutoPay Recurring Mandate Support                 |
|  - Realtime unlock listener                    - Atomic DB activation via process_razorpay_webhook |
+---------------------------------------------------------------------------------------------------+
```

---

## Detailed Task Breakdown

### Task 1: Supabase Server Secrets Configuration & Edge Function Security
- **Objective**: Store live Razorpay credentials securely in Supabase backend environment variables and ensure edge functions never leak sensitive credentials.
- **Actions**:
  1. Update Supabase project environment secrets via Supabase Management API:
     - `RAZORPAY_KEY_ID` = `rzp_live_TkaAcBNqI1IitC`
     - `RAZORPAY_KEY_SECRET` = `q64LYR5PXXqLyMVmlSzpriZc`
  2. Audit Edge Functions:
     - `supabase/functions/create-subscription/index.ts`:
       - Reads `Deno.env.get("RAZORPAY_KEY_ID")` and `Deno.env.get("RAZORPAY_KEY_SECRET")`.
       - Strips secret from any error responses or logs. Returns only public `key_id`, `order_id`, `amount`, `currency`.
     - `supabase/functions/verify-payment/index.ts`:
       - Performs HMAC-SHA256 signature verification using `Deno.env.get("RAZORPAY_KEY_SECRET")`.
     - `supabase/functions/razorpay-webhook/index.ts`:
       - Verifies webhook signatures using `RAZORPAY_WEBHOOK_SECRET` or fallback key secret.
  3. Deploy updated edge functions to Supabase via `deploy_edge_function`.
  4. Verify with curl/node test invocation to ensure live order generation succeeds and returns `rzp_live_TkaAcBNqI1IitC`.

---

### Task 2: Database Schema & Live Plans Synchronization
- **Objective**: Synchronize all 4 live Razorpay plan IDs into the Supabase database and update constraints.
- **Actions**:
  1. Update `gyms_plan_check` constraint on `gyms` table:
     - Alter check constraint to allow `test` alongside `free_trial`, `starter`, `pro`, `business`.
  2. Insert / Update rows in `public.subscription_plans`:
     - `starter`: `name: 'Starter'`, `price: 699.00`, `razorpay_plan_id: 'plan_TLBEs2n479kKl6'`, `badge: 'Popular'`
     - `pro`: `name: 'Pro'`, `price: 999.00`, `razorpay_plan_id: 'plan_TLBAK4LFyPSGxf'`, `badge: 'Best Value'`
     - `business`: `name: 'Business'`, `price: 1999.00`, `razorpay_plan_id: 'plan_TLBBMMUhI7sBd6'`, `badge: 'Ultimate'`
     - `test`: `name: 'Test Plan (1 Rs)'`, `price: 1.00`, `razorpay_plan_id: 'plan_TkaKSZ86fTigEG'`, `badge: 'Test AutoPay'`
  3. Verify `subscriptions_plan_id_fkey` and `gyms_plan_check` foreign keys allow seamless purchasing and activation of all 4 plans.

---

### Task 3: Web Portal Configuration & UI Plan Integration (`gymos_web`)
- **Objective**: Configure live Razorpay Key ID and render the ₹1 Test Plan alongside Starter, Pro, and Business in the web portal.
- **Actions**:
  1. Update `gymos_web/lib/core/config/env.dart`:
     - Set default `razorpayKeyId` to `rzp_live_TkaAcBNqI1IitC`.
  2. Update `gymos_web/lib/core/config/app_config.dart`:
     - Update `razorpayKeyId` to `rzp_live_TkaAcBNqI1IitC`.
     - Update plan IDs to live constants:
       - `razorpayStarterPlanId = 'plan_TLBEs2n479kKl6'`
       - `razorpayProPlanId = 'plan_TLBAK4LFyPSGxf'`
       - `razorpayBusinessPlanId = 'plan_TLBBMMUhI7sBd6'`
       - `razorpayTestPlanId = 'plan_TkaKSZ86fTigEG'`
  3. Update `gymos_web/lib/core/services/subscription_plans_service.dart`:
     - Add `test` (₹1) plan to `getDefaultPlans()` and fallback resolution.
  4. Update `gymos_web/lib/features/subscription/owner_subscription_screen.dart`:
     - Render the ₹1 Test Plan card with clear distinction ("AutoPay Test Plan - ₹1 / 1 Month").
     - Ensure checkout and AutoPay toggles work identically across all 4 plans.
  5. Verify that mobile app directories (`lib/`, `android/`, `ios/`) remain 100% free of payment triggers.

---

### Task 4: Web Portal Compilation, Verification & GitHub Deployment
- **Objective**: Build release web assets, test end-to-end checkout readiness, and push to production repository.
- **Actions**:
  1. Build Flutter web release:
     - `flutter build web --release --base-href "/portal/"` in `gymos_web/`.
  2. Copy built assets into `website/portal/`.
  3. Verify git status and clean diffs in `website/` and root project.
  4. Commit and push changes to GitHub `origin main` (`JigarGamer0/gym-os-info-website`).
  5. Provide detailed completion report with plan IDs, credentials status, and testing verification.

---

## Verification & Acceptance Criteria
- [ ] Supabase project environment variables contain live Key ID and Secret.
- [ ] Edge functions (`create-subscription`, `verify-payment`) deployed and functioning with live credentials.
- [ ] No secrets exposed in client-side code, edge function logs, or response payloads.
- [ ] `subscription_plans` table updated with all 4 live plans including the ₹1 test plan.
- [ ] `gyms_plan_check` constraint supports all 4 plans.
- [ ] `gymos_web` renders all 4 plans and opens live Razorpay modal with `rzp_live_TkaAcBNqI1IitC`.
- [ ] Production web portal built and pushed to GitHub `main` branch.
