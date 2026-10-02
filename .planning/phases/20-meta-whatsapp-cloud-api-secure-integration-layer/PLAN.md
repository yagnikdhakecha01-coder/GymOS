# Phase 20: Meta WhatsApp Cloud API Secure Integration Layer

## Goal
Establish a clean, isolated, production-grade integration layer for Meta WhatsApp Cloud API using a dedicated Supabase Edge Function (`whatsapp-webhook`). This phase is strictly limited to webhook verification (GET) and event reception (POST) with duplicate idempotency safety. Zero modification to existing production tables, zero business triggers, and zero message sending.

---

## 🔒 Production Safety Invariants
1. **Zero modifications to existing production tables**: `gyms`, `members`, `staff`, `attendance`, `finance_transactions`, etc. remain 100% immutable.
2. **Zero modifications to existing RLS policies, authentication, or business logic**: The Flutter app code and existing database triggers remain completely untouched.
3. **No message sending / no automated triggers**: This phase strictly implements the incoming webhook handshake and payload intake infrastructure. Reminders, attendance triggers, and payment notifications will be built in future phases.
4. **Credential Isolation**: All Meta secrets (`WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET`, `WHATSAPP_ACCESS_TOKEN`) live exclusively in Supabase Edge Function environment secrets. No tokens in client code or Git repository.

---

## Inspection Findings (Step 1 Baseline)
- **Supabase Project ID / Reference**: `gilxxyvwqucwwwqaxosx`
- **Region**: `ap-south-1`
- **Database Engine**: PostgreSQL 17 (`db.gilxxyvwqucwwwqaxosx.supabase.co`)
- **Supabase Project URL**: `https://gilxxyvwqucwwwqaxosx.supabase.co`
- **Existing Public Tables**: 74 tables (all with RLS enabled; existing webhook log table `razorpay_webhook_logs` is isolated to Razorpay). No WhatsApp tables currently exist.
- **Existing Edge Functions**: 0 functions currently deployed on remote project.
- **Existing Secrets**: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`.

---

## Architecture & Integration Flow

```
Meta WhatsApp Cloud API
         │
         │ (GET Verification / POST Event Delivery)
         ▼
[https://gilxxyvwqucwwwqaxosx.supabase.co/functions/v1/whatsapp-webhook]
         │
         │ (Edge Runtime - Deno / TypeScript, verify_jwt: false)
         ├─────────────────────────────────────────┐
         ▼                                         ▼
   [GET Verification]                      [POST Webhook Intake]
   - Check hub.mode === 'subscribe'        - Optional HMAC-SHA256 signature check
   - Validate hub.verify_token             - Parse Meta event envelope
   - Return hub.challenge (HTTP 200)       - Idempotency key extraction (wamid / hash)
   - Or HTTP 403 Forbidden                 - Log to isolated whatsapp_webhook_events
                                           - Return HTTP 200 OK immediately
```

---

## Implementation Plan

### Wave 1: Isolated Database Infrastructure (Optional Logging & Idempotency)
- **Target**: Create completely isolated `whatsapp_webhook_events` table in PostgreSQL.
- **Columns**:
  - `id`: `uuid PRIMARY KEY DEFAULT gen_random_uuid()`
  - `provider`: `text NOT NULL DEFAULT 'meta'`
  - `event_type`: `text` (e.g., `'messages'`, `'statuses'`, `'unknown'`)
  - `received_at`: `timestamptz NOT NULL DEFAULT now()`
  - `processing_status`: `text NOT NULL DEFAULT 'received'`
  - `payload_hash`: `text` (SHA-256 hash of payload body for deduplication)
  - `meta_message_id`: `text UNIQUE` (wamid or event ID for idempotency key)
  - `error_message`: `text`
- **Security**:
  - Enable Row Level Security (RLS).
  - Explicitly restrict access so that only `service_role` (Edge Function) can insert/read. Zero access granted to `anon` or `authenticated` roles.
- **Verification**: Ensure no other tables, functions, or triggers are touched.

### Wave 2: Secret Generation & Management API Injection
- Generate a cryptographically secure random verify token (48-character hex/URL-safe string).
- Inject `WHATSAPP_VERIFY_TOKEN` into Supabase Edge Function Secrets for project `gilxxyvwqucwwwqaxosx` using the Supabase Management API.
- Ensure the token is stored securely and never printed to public logs.

### Wave 3: Develop Isolated Supabase Edge Function (`whatsapp-webhook`)
- **Directory**: `supabase/functions/whatsapp-webhook/index.ts`
- **Configuration**:
  - Configured for Deno runtime with `verify_jwt: false` (public webhook entry point).
  - Security headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Strict-Transport-Security: max-age=31536000; includeSubDomains`.
  - CORS handling for OPTIONS preflight.
- **GET Handler (Meta Handshake Verification)**:
  - Query parameters: `hub.mode`, `hub.verify_token`, `hub.challenge`.
  - If `hub.mode === 'subscribe'` and constant-time / safe string equality check against `WHATSAPP_VERIFY_TOKEN`:
    - Return `hub.challenge` as plain text with HTTP 200.
  - Otherwise, return HTTP 403 Forbidden.
- **POST Handler (Meta Webhook Intake)**:
  - Preserves raw request text.
  - Optional `x-hub-signature-256` HMAC validation if `WHATSAPP_APP_SECRET` is configured in secrets.
  - Parses JSON payload.
  - Extracts message ID (`wamid...`) or generates SHA-256 hash of body for idempotency.
  - Checks if event was already recorded; if duplicate, gracefully returns HTTP 200 without duplicate processing.
  - Inserts minimal record to `whatsapp_webhook_events` via Supabase Service Client.
  - Returns HTTP 200 `{ "status": "success", "received": true }` immediately within < 500ms (Meta requirement).
  - Absolutely zero message triggers, reminders, or outbound calls.

### Wave 4: Deploy & Verify Function
- Deploy `whatsapp-webhook` to `gilxxyvwqucwwwqaxosx` via Supabase Edge Function deployment API with `verify_jwt: false`.
- Execute automated end-to-end tests:
  1. GET test with valid token -> Expect HTTP 200 + challenge echo.
  2. GET test with invalid token -> Expect HTTP 403 Forbidden.
  3. POST test with valid mock WhatsApp message payload -> Expect HTTP 200.
  4. POST duplicate test -> Expect HTTP 200 (idempotent deduplication).
  5. Verify no existing production tables were modified.
  6. Verify no Flutter or client-side files were changed.

---

## Verification & Acceptance Criteria
- [ ] Production Edge Function URL is reachable: `https://gilxxyvwqucwwwqaxosx.supabase.co/functions/v1/whatsapp-webhook`
- [ ] Meta GET challenge handshake returns HTTP 200 and exact challenge string.
- [ ] Invalid verify token returns HTTP 403 Forbidden.
- [ ] POST webhook accepts events, deduplicates idempotently, and returns HTTP 200.
- [ ] Zero existing tables, RLS policies, or data rows modified.
- [ ] Zero messages sent, zero business triggers activated.
- [ ] Final report delivered with Callback URL, Verify Token, and testing instructions.
