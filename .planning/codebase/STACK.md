# Technology Stack

**Analysis Date:** 2026-09-16

## Languages

**Primary:**
- Dart 3.12+ - All core application code, UI widgets, ViewModels, repository layer, and business logic (`lib/`)

**Secondary:**
- SQL (PL/pgSQL) - Supabase PostgreSQL database schemas, triggers, RLS policies, and stored procedures (`*.sql`)
- HTML5 / CSS3 / Vanilla JavaScript (ES6+) - Marketing landing page, legal compliance documents, and attendance web display (`website/`, `attendance_display_website/`)
- Kotlin / Groovy / Gradle - Android native build configuration and platform integration (`android/app/build.gradle.kts`)

## Runtime

**Environment:**
- Flutter 3.x / Dart VM with Ahead-Of-Time (AOT) compilation for production builds
- Target Platforms: Android (minSdkVersion: 21, targetSdkVersion: 34), iOS, Web companion apps

**Package Manager:**
- Flutter Pub (`pubspec.yaml`, `pubspec.lock`)

## Frameworks

**Core:**
- Flutter Material Design (`flutter/material.dart`, `cupertino_icons: ^1.0.8`) - Reactive UI rendering engine
- Provider (`provider: ^6.1.5+1`) - State management via `ChangeNotifier` and `MultiProvider`

**Testing:**
- Flutter Test (`flutter_test` from Flutter SDK) - Unit and widget test runner

**Build & Tooling:**
- Flutter CLI (`flutter build appbundle`, `flutter build apk`)
- Gradle 8.x with Kotlin DSL (`android/app/build.gradle.kts`)
- Flutter Launcher Icons (`flutter_launcher_icons: ^0.13.1`) - Adaptive app icon generation

## Key Dependencies

**Critical:**
- `supabase_flutter: ^2.8.0` - Cloud database, authentication, storage, and realtime communication
- `shared_preferences: ^2.5.5` - Offline-first local persistent caching for app state
- `razorpay_flutter: ^1.3.5` - In-app subscription billing and digital payment gateway
- `mobile_scanner: ^5.1.1` - Fast camera-based QR code scanning for member and staff attendance
- `google_sign_in: ^6.2.1` - Google OAuth 2.0 authentication integration
- `flutter_local_notifications: ^22.2.0` - System tray notifications for shift alerts and member reminders
- `local_auth: ^2.3.0` - Biometric authentication (fingerprint / Face Unlock) for app security
- `permission_handler: ^12.0.3` - Runtime Android/iOS OS permission management
- `image_picker: ^1.1.2` - Profile photo and gym logo camera/gallery capture

**Infrastructure & Utilities:**
- `intl: ^0.20.3` - Date/time parsing, currency formatting (INR ₹), and calendar localization
- `google_fonts: ^8.2.0` - Inter typography across all app themes
- `url_launcher: ^6.2.5` - Launching dialer, email clients, and external store links

## Configuration

**Environment:**
- `.env` & `.env.example` - Holds runtime credentials (`SUPABASE_URL`, `SUPABASE_ANON_KEY`)
- `lib/core/config/supabase_config.dart` - Centralized config service with dynamic fallback loading

**Build:**
- `pubspec.yaml` - Asset paths, fonts, dependency declarations, and version code (`1.0.0+5`)
- `analysis_options.yaml` - Lint rules extending `package:flutter_lints/flutter.yaml`
- `android/app/build.gradle.kts` - Application ID (`com.gymos.app`), signingConfigs, and JVM target 17

## Platform Requirements

**Development:**
- Flutter SDK ^3.12
- Android Studio / VS Code with Dart & Flutter extensions
- Java JDK 17
- Windows 10/11, macOS, or Linux

**Production:**
- Android Play Store: Android 5.0 (API 21) or higher
- Web Hosting: Cloudflare Pages for the static info website (`gymos.tech`)

---

*Stack analysis: 2026-09-16*
*Update after major dependency changes*
