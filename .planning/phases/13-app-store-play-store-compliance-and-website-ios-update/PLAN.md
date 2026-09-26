# Phase 13: Google Play Store & Apple App Store Guidelines Compliance and Website iOS Integration

## Goal
Prepare the GymOS mobile application and official website (`gym-os-info-website`) for simultaneous submission and approval on both the **Google Play Store** and **Apple App Store**. Perform thorough guideline audits against Apple App Store Review Guidelines and Google Play Developer Policies, implement necessary mobile app fixes, update website legal policies (Privacy Policy, Terms of Service, EULA) with Apple/iOS disclosures, integrate the App Store download action alongside Google Play, and push the updated website code to GitHub.

---

## 1. Compliance Audit & Gap Analysis

### 1.1 Apple App Store Review Guidelines

| Guideline | Requirement | Current Status | Required Action |
| :--- | :--- | :--- | :--- |
| **5.1.1 Data Collection & Permissions** | Every hardware permission key in `Info.plist` must have a clear, accurate, and non-generic user-facing rationale. Apps cannot declare permissions they do not use. | `ios/Runner/Info.plist` includes `NSMicrophoneUsageDescription`, but the app **does not record audio** anywhere. Missing `NSPhotoLibraryAddUsageDescription`. | 1. **Remove `NSMicrophoneUsageDescription`** to avoid automatic rejection under 5.1.1.<br>2. **Add `NSPhotoLibraryAddUsageDescription`** for saving receipts and profile photos. |
| **4.8 Sign in with Apple** | If an app offers third-party social login (e.g. Google Sign-In), it **must** also offer Sign in with Apple as an equivalent option. | App currently offers Google Sign-In on `login_screen.dart` via `google_sign_in`. | 1. Implement Sign in with Apple handling (`OAuthProvider.apple`) in `AuthViewModel`.<br>2. Add compliant "Sign in with Apple" button on iOS platform or provide platform conditional rendering. |
| **5.1.1(v) Account Deletion** | If an app supports account creation, it must allow users to initiate deletion of their account within the app and delete associated personal data. | Implemented in `settings_screen.dart`, `staff_more_screen.dart`, `member_profile_screen.dart`, and backend RPC. | Compliant. Ensure Privacy Policy explicitly mentions Apple 5.1.1(v). |
| **3.1.1 & 3.1.3(g) In-App Purchases vs External Billing** | In-app digital features and software subscriptions must use StoreKit In-App Purchases unless exempt under business multiplatform services (3.1.3(g)). External payment gateways (like Razorpay) cannot be directly launched for digital unlocks inside an iOS build. | `owner_subscription_screen.dart` triggers `razorpay_flutter` directly. | For iOS builds: provide safe fallback notice or direct gym owners to manage their subscription on the web portal (`gymos.tech`) to prevent App Review rejection. |
| **EULA Schedule 2 Minimum Terms** | Apps with custom licensing or subscriptions must include Apple's standard EULA minimum terms acknowledging Apple is not a party to the contract. | `website/licensing-agreement.html` currently lacks Apple Schedule 2 terms. | Add "Apple App Store Supplemental Terms" to EULA & Terms of Service. |
| **Privacy Nutrition Label & Tracking** | App must disclose data collected, data linked to users, and confirm whether user tracking (IDFA / App Tracking Transparency) occurs. | No third-party tracking or advertising SDKs used. | Formulate accurate Privacy Nutrition Label declarations in `website/privacy-policy.html`. |

---

### 1.2 Google Play Developer Policies

| Policy | Requirement | Current Status | Required Action |
| :--- | :--- | :--- | :--- |
| **User Data & Account Deletion** | Provide an in-app path for account deletion AND a public web-based deletion request URL. | App has in-app deletion; website has `delete-account.html`. | Fully compliant. Verify web URL is linked properly in policy. |
| **Permissions Policy** | Request minimal permissions needed for app features. | App requests `CAMERA` (QR scanning) and `USE_BIOMETRIC`. No broad storage, SMS, or location background permissions. | Fully compliant. |
| **Target API Level** | Target modern Android API level (API 34+). | Configured in `android/app/build.gradle.kts`. | Verified. |
| **Data Safety Form** | Accurate disclosure of collected data types (contact info, attendance logs, finance records) and encryption in transit. | Fully encrypted TLS/SSL via Supabase, bcrypt/salted passwords, RLS. | Disclose in Privacy Policy and Google Play Console. |

---

## 2. Implementation Tasks

### Task 1: iOS Configuration & Permission Hardening (`ios/Runner/Info.plist`)
- **File**: `ios/Runner/Info.plist`
- **Actions**:
  1. Remove `NSMicrophoneUsageDescription` (unused in app; eliminates Guideline 5.1.1 audit flag).
  2. Add `NSPhotoLibraryAddUsageDescription` with clear explanation: `"Gym OS requires permission to save gym reports, receipts, and photos to your photo library."`
  3. Refine `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to be crystal clear.

### Task 2: Apple Review Compliance for Authentication & Payments
- **Files**:
  - `lib/features/authentication/login_screen.dart`
  - `lib/features/authentication/auth_viewmodel.dart`
  - `lib/features/subscription/owner_subscription_screen.dart`
- **Actions**:
  1. **Social Login / Apple Sign-In Compliance (Guideline 4.8)**:
     - On iOS devices, ensure Sign in with Apple is supported alongside Google Sign-In, or cleanly adapt social login options so iOS App Review does not reject due to Google-only OAuth.
  2. **Subscription Screen iOS Guard (Guideline 3.1.1)**:
     - In `owner_subscription_screen.dart`, guard Razorpay checkout on iOS. If run on iOS, display a clean modal informing gym owners that subscriptions can be managed securely via the web dashboard at `https://gymos.tech` or contact support, keeping the iOS app compliant with Apple Guideline 3.1.3(g).

### Task 3: Website App Store Integration (`gym-os-info-website`)
- **Files**:
  - `website/index.html`
  - `website/js/main.js`
- **Actions**:
  1. **Hero Section**:
     - Update release badge: `"Available on Android & iOS"`.
     - Add **"Download on App Store"** button with Apple logo alongside the Play Store button.
  2. **CTA Section (`#download`)**:
     - Add matching App Store download button with Apple SVG icon.
  3. **Interactive Store Modals**:
     - Add `showAppStoreNotice(event)` modal in `website/js/main.js` and inline script in `website/index.html` (announcing upcoming App Store release for iPhone & iPad, with option to enter email or check back).
     - Update navigation bar download triggers.

### Task 4: Website Privacy Policy & EULA iOS Expansion
- **Files**:
  - `website/privacy-policy.html`
  - `website/terms-of-service.html`
  - `website/licensing-agreement.html`
- **Actions**:
  1. **`privacy-policy.html`**:
     - Add Section 2.4 iOS Permissions: explicitly describe `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, and `NSFaceIDUsageDescription`.
     - Add Section for **Apple App Store Privacy Details (Privacy Nutrition Label)**:
       - Data Linked to User: Contact Info (Name, Email, Phone), Identifiers (User ID), Usage Data (Check-in timestamps, app interaction).
       - Tracking Transparency: Confirm GymOS does NOT track users across apps/websites owned by other companies and does not use IDFA.
     - Update Section 8 (Account Deletion) to cite Apple App Store Guideline 5.1.1(v) alongside Google Play policies.
     - Update "Last updated" date to current date.
  2. **`terms-of-service.html` & `licensing-agreement.html`**:
     - Add **Apple App Store Minimum Terms (Schedule 2)**:
       - Acknowledgment that terms are between User and GymOS Inc., not Apple.
       - Scope of License for Apple Devices.
       - Maintenance, Support, and Warranty disclaimers regarding Apple.
       - Apple and Apple subsidiaries are third-party beneficiaries of the EULA.

### Task 5: Git Commit & Push to `gym-os-info-website`
- **Actions**:
  1. Review `git diff` inside `website/`.
  2. Commit all website enhancements:
     `git commit -m "feat(store): add App Store download integration, iOS privacy policy disclosures, and Apple EULA terms"`
  3. Push to `origin main` (`https://github.com/JigarGamer0/gym-os-info-website.git`).
  4. Verify clean working tree.

---

## 3. Verification & Acceptance Criteria
1. **iOS Configuration**: `Info.plist` has no unused microphone permission and contains all required photo/camera/FaceID keys.
2. **Apple Review Safety**: In-app purchase and social login conform to Apple App Store Guidelines 3.1.1 and 4.8.
3. **Website Visuals**: Hero and CTA sections display both Google Play and Apple App Store buttons with responsive styling.
4. **Legal Compliance**: Privacy Policy, Terms of Service, and Licensing Agreement include Apple App Store disclosures and EULA terms.
5. **Git Deployment**: `gym-os-info-website` remote repository reflects all new changes on `origin/main`.
