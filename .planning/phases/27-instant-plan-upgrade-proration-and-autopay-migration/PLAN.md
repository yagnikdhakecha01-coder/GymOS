# Phase 27: Instant Subscription Plan Upgrades, Prorated Unused Credit Calculation & Seamless AutoPay Mandate Migration

## Goal
Implement a complete on-the-spot subscription plan upgrade/downgrade system on the GymOS Web Portal (`gymos.tech/portal`). When a gym owner upgrades their plan (e.g., from Starter ₹699 to Pro ₹999 or Business ₹1999), the system calculates unused days from their active plan and credits it towards the new plan, prompts the owner to authorize the new AutoPay mandate for the new plan price, instantly switches features and limits on the spot, and securely cancels the old recurring AutoPay mandate on Razorpay to prevent double-billing.

---

## Technical & Regulatory Context (RBI & Razorpay)

```
+----------------------------------------------------------------------------------------------------+
|                                    RBI / RAZORPAY MANDATE REALITY                                   |
|                                                                                                    |
|  1. UPI AutoPay & eMandates are legally locked to the specific approved mandate limit (e.g., ₹699).|
|  2. An existing ₹699 mandate CANNOT be silently auto-debited for ₹999 without customer consent.   |
|  3. Therefore, upgrading a plan requires the customer to approve a NEW AutoPay mandate for ₹999.   |
|  4. CRITICAL: The OLD ₹699 mandate MUST be cancelled via Razorpay API so the customer's bank      |
|     does NOT auto-debit both the old ₹699 and new ₹999 next month!                                 |
+----------------------------------------------------------------------------------------------------+
```

---

## Architectural Blueprint

```
+----------------------------------------------------------------------------------------------------+
|                                 STEP 1: PRORATION CALCULATION ENGINE                               |
|                                                                                                    |
|  Inputs:                                                                                           |
|    - Current Plan: Starter (₹699/month, 30 days total)                                             |
|    - Days Used: 10 days  -->  Remaining Days: 20 days                                             |
|    - Unused Credit: (₹699 / 30) * 20 days = ₹466.00                                                |
|    - New Plan Selected: Pro (₹999/month)                                                           |
|                                                                                                    |
|  Output:                                                                                           |
|    - Immediate Upgrade Amount to Pay: ₹999 - ₹466 = ₹533.00                                        |
|    - Next Recurring AutoPay Amount: ₹999.00 / month (starts 30 days from upgrade)                  |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
|                                  STEP 2: PLAN UPGRADE PREVIEW MODAL                                |
|                                                                                                    |
|  - Web Portal UI shows transparent breakdown to the Gym Owner:                                     |
|    * Current Plan: Starter (₹699/mo) with 20 days remaining                                        |
|    * Unused Balance Credited: -₹466.00                                                             |
|    * Today's Prorated Payment: ₹533.00                                                             |
|    * Next Monthly AutoPay: ₹999.00 on [Date 30 days from now]                                      |
|  - Owner clicks "Confirm Upgrade & Set up AutoPay"                                                 |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
|                            STEP 3: SERVER-SIDE EDGE FUNCTION (upgrade-subscription)                 |
|                                                                                                    |
|  1. Creates new Razorpay AutoPay subscription (`sub_NEW`) for the Pro plan.                        |
|  2. Returns new `subscription_id` to web checkout.                                                 |
|  3. Opens Razorpay Web Modal: Owner authorizes the ₹999 AutoPay mandate (UPI / Cards).             |
+-------------------------------------------------+--------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
|                         STEP 4: ATOMIC ACTIVATION & MANDATE MIGRATION                              |
|                                                                                                    |
|  1. Verify signature (`verify-payment` / webhook).                                                 |
|  2. Cancel old Razorpay Subscription via API (`POST /v1/subscriptions/{old_sub_id}/cancel`).       |
|  3. Database RPC `process_plan_upgrade`:                                                            |
|     - Updates `gyms.plan = 'pro'`, `gyms.expiry_date = NOW() + 30 days`.                         |
|     - Updates `subscriptions.plan_id = 'pro'`, `subscriptions.razorpay_subscription_id = sub_NEW`. |
|     - Records invoice with prorated credit breakdown.                                              |
|     - Inserts record into `subscription_history` with full audit log.                              |
|  4. Realtime broadcast unlocks all Pro features (members limit, staff limit) instantly!           |
+----------------------------------------------------------------------------------------------------+
```

---

## Detailed Task Breakdown

### Task 1: Server-Side Proration & Upgrade Edge Function (`upgrade-subscription`)
- **Target File**: `supabase/functions/upgrade-subscription/index.ts`
- **Actions**:
  1. Calculate server-side proration:
     - Verify active subscription and gym details.
     - Compute remaining days: `Math.max(0, Math.ceil((new Date(sub.end_date).getTime() - Date.now()) / (1000 * 60 * 60 * 24)))`.
     - Compute unused balance: `Math.round((Number(currentPlan.price) / 30) * remainingDays)`.
     - Compute payable amount: `Math.max(1, Math.round(Number(newPlan.price) - unusedCredit))`.
  2. Create new Razorpay Subscription (`POST https://api.razorpay.com/v1/subscriptions`):
     - `plan_id: newPlan.razorpay_plan_id`
     - `notes: { gym_id, old_plan_id, new_plan_id, old_sub_id, unused_credit, upgrade_amount }`
  3. Return preview details + new `subscription_id` + public `key_id`.

---

### Task 2: Old Mandate Cancellation & Database Upgrade RPC (`process_plan_upgrade`)
- **Target Files**:
  - `supabase/functions/verify-payment/index.ts`
  - `supabase/migrations/20261006_plan_upgrade_and_proration.sql`
- **Actions**:
  1. Create PostgreSQL function `process_plan_upgrade(...)`:
     - Updates `gyms.plan`, `gyms.expiry_date = NOW() + INTERVAL '30 days'`.
     - Updates `subscriptions.plan_id`, `subscriptions.razorpay_subscription_id`, `start_date`, `end_date`.
     - Inserts invoice with line items:
       - Line 1: `New Plan (30 days)` = +₹999.00
       - Line 2: `Prorated Credit for Unused Days` = -₹466.00
       - Total Paid = ₹533.00
     - Inserts detailed entry in `subscription_history`.
  2. In `verify-payment` / `razorpay-webhook`:
     - If `old_sub_id` is passed in notes, call Razorpay API:
       `POST https://api.razorpay.com/v1/subscriptions/{old_sub_id}/cancel`
       with `{"cancel_at_cycle_end": 0}` (immediate cancellation).
     - This guarantees the user's previous bank mandate is cleanly terminated.

---

### Task 3: Web Portal Plan Upgrade UI & Transparent Preview Dialog (`gymos_web`)
- **Target Files**:
  - `gymos_web/lib/features/subscription/owner_subscription_screen.dart`
  - `gymos_web/lib/features/subscription/widgets/plan_upgrade_dialog.dart`
- **Actions**:
  1. Detect if current gym already has an active purchased plan (`currentPurchasedPlanId != null`).
  2. If the user clicks a higher plan (or different plan):
     - Show **"Upgrade Plan"** or **"Switch Plan"** instead of generic "Buy Now".
  3. Open a dedicated **Plan Upgrade Preview Dialog**:
     - Visual breakdown of:
       - Current Plan & Days remaining in current billing cycle.
       - Prorated credit refund calculated to the exact rupee.
       - Amount due today to switch immediately.
       - Monthly AutoPay amount that will apply going forward.
  4. On confirmation, invoke `upgrade-subscription`, open Razorpay checkout modal with new `subscription_id`, and handle immediate on-the-spot activation.

---

### Task 4: Compilation, Deployment & GitHub Push
- **Actions**:
  1. Compile Flutter web bundle: `flutter build web --release --base-href "/portal/"`.
  2. Deploy to `website/portal/`.
  3. Deploy Edge Functions to Supabase.
  4. Push both `gymos-v1-ui` and `gym-os-info-website` to GitHub.

---

## Verification & Acceptance Criteria
- [ ] Proration math is mathematically exact (unused days credited to the rupee).
- [ ] New plan activates on the spot immediately after payment.
- [ ] New AutoPay mandate is established for the new plan price.
- [ ] Old Razorpay subscription mandate is automatically cancelled via API (preventing double debit).
- [ ] Web Portal UI displays a clear, transparent upgrade preview dialog before payment.
- [ ] Changes deployed to production and pushed to GitHub.
