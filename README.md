# GymOS — Gym Management System

GymOS is a multi-tenant SaaS gym management platform built with Flutter (Mobile & Tablet) and Supabase.

---

## 🔒 Security & Environment Setup

All sensitive secrets, keys, and credentials must strictly be loaded through environment variables. **No hardcoded secrets or service role keys should ever exist in frontend source code.**

### 1. Environment Configuration

Copy `.env.example` to `.env` in the project root:

```bash
cp .env.example .env
```

Fill in your configuration values:
- `SUPABASE_URL`: Your Supabase project URL (e.g., `https://xyz.supabase.co`)
- `SUPABASE_ANON_KEY`: Supabase anon/public key (**ONLY** anon key; never `service_role_key` on the client!)
- `RAZORPAY_KEY_ID`: Razorpay publishable Key ID
- `RAZORPAY_STARTER_PLAN_ID`: Starter plan ID
- `RAZORPAY_PRO_PLAN_ID`: Pro plan ID
- `RAZORPAY_BUSINESS_PLAN_ID`: Business plan ID

> [!CAUTION]
> **Git History Notice & Key Rotation:**
> If any secrets or keys were previously committed in earlier git commits, their values persist in Git history.
> If this repository has ever been public or shared with untrusted parties, rotate the Supabase anon key and any external API tokens immediately from your dashboard.

---

## 🚀 Building & Running the Application

### Running with Dart Environment Flags

You can run or build the application by passing variables via `--dart-define`:

```bash
flutter run \
  --dart-define=SUPABASE_URL="https://your-project.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="your-anon-key" \
  --dart-define=RAZORPAY_KEY_ID="rzp_live_..."
```

### Production Release Build (Android APK / AAB)

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL="https://your-project.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="your-anon-key" \
  --dart-define=RAZORPAY_KEY_ID="rzp_live_..." \
  --dart-define=RAZORPAY_STARTER_PLAN_ID="plan_..." \
  --dart-define=RAZORPAY_PRO_PLAN_ID="plan_..." \
  --dart-define=RAZORPAY_BUSINESS_PLAN_ID="plan_..."
```

---

## ⚡ Supabase Edge Functions Secrets

The backend Edge Functions (`verify-payment`, `create-subscription`, `daily-backup`, `razorpay-webhook`) run on Supabase serverless infrastructure and access secrets via `Deno.env.get()`:

Set the server-side secrets using the Supabase CLI:

```bash
supabase secrets set \
  RAZORPAY_KEY_ID="rzp_live_..." \
  RAZORPAY_KEY_SECRET="your_razorpay_secret" \
  RAZORPAY_WEBHOOK_SECRET="your_webhook_secret" \
  ALLOWED_ORIGIN="https://your-admin-domain.com"
```

> [!IMPORTANT]
> The `SUPABASE_SERVICE_ROLE_KEY` is automatically injected into Supabase Edge Functions by the Supabase platform runtime. Never expose it to the mobile or web frontend.
