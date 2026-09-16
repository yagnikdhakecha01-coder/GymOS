# External Integrations

**Analysis Date:** 2026-09-16

## APIs & External Services

**Payment Processing:**
- Razorpay (`razorpay_flutter: ^1.3.5`)
  - Purpose: Owner SaaS subscription plan billing (Starter ₹699, Pro ₹999, Business ₹1,999) and member fee collections
  - Implementation: Event-driven payment listener in `owner_subscription_screen.dart`
  - Backend sync: `razorpay_webhook_security_setup.sql`, `gymos_subscription_system.sql`

**QR Code & Camera Scanning:**
- Mobile Scanner (`mobile_scanner: ^5.1.1`)
  - Purpose: High-speed barcode/QR attendance verification at gym gates
  - Dynamic QR display support: Web display station (`attendance_display_website/`) and dynamic rotating QR tokens
  - Stored procedures: `SQL_STEP2_attendance_rpc.sql`, `add_qr_attendance_engine_v4.sql`

**Identity & Sign-In:**
- Google OAuth 2.0 (`google_sign_in: ^6.2.1`)
  - Client ID integration across Google Cloud Console & Supabase Auth
  - Fingerprint verification: Configured for Google Play App Signing SHA-1 & SHA-256
- Supabase Auth Native Provider: Email/password authentication with encrypted session tokens

## Data Storage

**Databases:**
- PostgreSQL on Supabase Cloud
  - Connection: `SupabaseClient` via HTTPS REST/PostgREST and WebSockets (Realtime)
  - Security: Strict Row-Level Security (RLS) policies scoped by `gym_id` and authenticated `auth.uid()`
  - Core Schema Entities:
    - `gyms`: Core tenant profile, branding, and subscription limits
    - `members`: Member profiles, active plans, biometric IDs, payment status
    - `staff`: Staff records, trainer profiles, shifts, salary rates, commission tiers
    - `attendance_logs` & `attendance_corrections`: Check-in/out records, shift logs, leave records
    - `finance_transactions`: Incomes, expenses, fee collections, salary disbursements
    - `workout_plans` & `diet_plans`: Master library and custom assigned workout/nutrition plans
    - `support_tickets`: Customer assistance requests and bug reports

**File & Media Storage:**
- Supabase Storage Buckets:
  - `avatars`: Member and staff profile photos
  - `gym-logos`: Custom white-label gym logos for pro/business branding
  - `receipts`: Digital transaction proof and bill attachments

**Local Persistence & Cache:**
- SharedPreferences (`LocalStorageService`):
  - Purpose: Offline-first data access and optimistic UI updates
  - Stored state: Current user profile, active gym ID, cached member lists, offline attendance queue

## Authentication & Identity

**Auth Provider:**
- Supabase Auth (`supabase_flutter`)
  - Session tokens: Automatically refreshed JWTs stored securely on device
  - Role management: Custom metadata and user profiles mapping to `owner`, `staff`, or `member`
  - Biometric App Lock: `local_auth` prompt on app resume to prevent unauthorized access

**Google Play Policy Compliance:**
- Account & Data Deletion:
  - In-app: Dedicated Delete Account flow in profile screens calling `delete_user_account` RPC
  - Web: Public web form at `https://gymos.tech/delete-account.html` satisfying Google Play User Data safety guidelines

## CI/CD, Deployment & Hosting

**Mobile Application:**
- Google Play Console (Closed Testing & Production):
  - Application ID: `com.gymos.app`
  - Format: Android App Bundle (`.aab`) signed with custom release keystore (`upload-keystore.jks`)

**Static Website & Compliance:**
- Cloudflare Pages:
  - Repository: `https://github.com/JigarGamer0/gym-os-info-website`
  - Domain: `https://gymos.tech`
  - Pages: Landing page, Privacy Policy, Terms of Service, Account Deletion, Licensing Agreement

---

*Integrations analysis: 2026-09-16*
*Update when external dependencies or cloud services change*
