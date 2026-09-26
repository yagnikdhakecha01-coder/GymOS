# 🚀 GymOS Release v1.0.8 (Build 26)

### Release Name:
`1.0.8 (26) - Offline-First Sync Hardening & Zero-Error Member Onboarding`

---

### 📝 What's New & Release Notes:

#### 1. 🛡️ Offline-First Member & Data Safety (Zero Local Data Loss):
- **Local Persistence Guaranteed**: Fixed member, staff, and finance transaction merge handling so that any record created offline remains permanently visible in the Members and Finance tabs on device storage, even during network dropouts or extended offline retries.
- **Smart Queue Auto-Heal**: Added automatic reset for retry counters when tapping "Sync Now", allowing previously failed or pending operations to instantly re-attempt synchronization without manual intervention.

#### 2. ⚡ Biometric Sync Reliability & Safe Onboarding:
- **Zero-Crash Trigger Optimization**: Database synchronization triggers now intelligently verify PIN assignment before queueing machine commands. Members and staff added without physical biometric PINs now save and sync immediately with 100% reliability.
- **Foreign Key Transaction Integrity**: Resolved dependent finance ledger synchronization dependencies, ensuring member profile and membership ledger entries synchronize in strict atomic sequence.

#### 3. 🔑 Seamless Member & Staff Invitation Flow:
- **Instant Code Verification**: Fixed invitation redemption logic allowing gym members and staff using gym codes (e.g., from WhatsApp or SMS) to activate their profiles and log in smoothly without false "Unable to verify" errors.
- **Automatic Status Activation**: Streamlined transition from Pending Activation to Active with immediate association linking.

#### 4. 🔒 Compliance & Platform Hardening:
- Full adherence to Google Play Store & Apple App Store developer safety guidelines.
- Hardened privilege boundaries and optimized network retry policies.

---

### 📋 Play Store Console Release Summary (English):
```text
- Enhanced offline-first data retention: Added members, staff, and payments remain preserved locally even with slow or disconnected network.
- Optimized member and staff registration flow with instant cloud synchronization.
- Seamless invitation code verification for members and staff during first-time login.
- Performance enhancements, faster sync recovery, and general stability improvements.
```

---

### 📦 Target Build Numbers:
- **Version Name**: `1.0.8`
- **Version Code**: `26`
