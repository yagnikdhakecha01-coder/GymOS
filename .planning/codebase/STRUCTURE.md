# Codebase Structure

**Analysis Date:** 2026-09-16

## Directory Layout

```
GYMOS V1 UI/
├── .planning/                  # GSD planning artifacts & codebase mapping
│   └── codebase/               # 7 structural codebase reference documents
├── android/                    # Android native Gradle project, keystore, and manifests
├── assets/                     # App media assets (logos, role badges, illustrations)
│   ├── data/                   # Default offline seed data (sample plans)
│   └── images/                 # App icon master assets, background graphics
├── lib/                        # Main Flutter Dart codebase
│   ├── core/                   # Shared architectural building blocks
│   │   ├── config/             # Supabase & app configuration
│   │   ├── models/             # 21 strongly-typed data entities
│   │   ├── navigation/         # Route definitions and transitions
│   │   ├── repository/         # GymRepository implementation
│   │   ├── services/           # Platform & 3rd-party services (Auth, Storage, Biometrics)
│   │   ├── theme/              # Design tokens, colors, typography, styles
│   │   ├── utils/              # Helper functions, formatters, validators
│   │   └── widgets/            # Reusable UI widgets (cards, buttons, dialogs)
│   ├── features/               # 15 Modular feature domains
│   │   ├── attendance/         # QR scanning, check-in logs, shifts, corrections
│   │   ├── authentication/     # Login, register, Google Auth, splash, reset password
│   │   ├── dashboard/          # Owner home stats, revenue cards, quick actions
│   │   ├── diet/               # Diet plans library, creator, member assignment
│   │   ├── error/              # Fallback error screens
│   │   ├── finance/            # Incomes, expenses, fee ledger, salary drafts
│   │   ├── gym_settings/       # Gym profile, branding, auto-absent rules
│   │   ├── member_app/         # Member portal: workouts, diets, QR card
│   │   ├── members/            # Member lists, profile details, registration form
│   │   ├── membership/         # Membership plan management (monthly, annual)
│   │   ├── more/               # Settings, backups, about screen, logout
│   │   ├── receptionist/       # Front-desk quick check-in terminal
│   │   ├── staff/              # Staff directory, salary adjustments, trainer portal
│   │   ├── subscription/       # GymOS SaaS plan tier subscription & Razorpay checkout
│   │   └── workout/            # Workout routines, exercise database, logs
│   └── main.dart               # Application entry point & Provider hierarchy
├── test/                       # Unit, widget, and database testing scripts
├── website/                    # Production marketing landing page & Google Play legal pages
│   ├── css/                    # Pure CSS stylesheets (dark premium aesthetic)
│   ├── js/                     # Vanilla JavaScript (accordion, modal, animations)
│   ├── delete-account.html     # Google Play User Data account deletion portal
│   ├── privacy-policy.html     # Privacy Policy with camera & QR disclosures
│   ├── terms-of-service.html   # Terms of Service
│   └── index.html              # Main landing page
└── *.sql                       # Backend Supabase migrations, triggers, and RPC procedures
```

## Key File Locations

**Entry Points & Core Bootstrapping:**
- `lib/main.dart` - Initializes services and sets up MultiProvider
- `lib/features/authentication/splash_screen.dart` - Role-based navigation dispatcher

**Configuration:**
- `pubspec.yaml` - Dependencies, assets, and app version
- `analysis_options.yaml` - Dart analyzer lint configuration
- `android/app/build.gradle.kts` - Android build settings, signing, minSdk/targetSdk
- `lib/core/config/supabase_config.dart` - Supabase endpoints and API keys

**Core Data Management:**
- `lib/core/repository/gym_repository.dart` - Master data repository
- `lib/core/services/local_storage.dart` - SharedPreferences local persistence
- `lib/core/services/supabase_service.dart` - Supabase client wrapper

**Feature Modules (`lib/features/`):**
- `lib/features/members/members_viewmodel.dart` - Member management state
- `lib/features/attendance/attendance_viewmodel.dart` - Check-in and QR logic
- `lib/features/finance/finance_viewmodel.dart` - Accounting, salary, and fees
- `lib/features/staff/staff_viewmodel.dart` - Staff directory and shifts
- `lib/features/member_app/member_app_viewmodel.dart` - Dedicated member experience
- `lib/features/subscription/owner_subscription_screen.dart` - In-app Razorpay billing

**Legal & Public Web:**
- `website/privacy-policy.html` - Camera/QR & personal data disclosures
- `website/delete-account.html` - Google Play compliance account deletion form
- `website/index.html` - Public product showcase

## Naming Conventions

**Files:**
- Dart files: `snake_case.dart` (e.g., `member_profile_screen.dart`)
- Screens: `*_screen.dart`
- ViewModels: `*_viewmodel.dart`
- Models: `*.dart` (e.g., `member.dart`, `diet_plan.dart`)
- Custom Widgets: `*_card.dart`, `*_dialog.dart`, `*_sheet.dart`

**Classes:**
- Widgets & ViewModels: `PascalCase` (e.g., `MemberProfileScreen`, `MembersViewModel`)
- Models: `PascalCase` (e.g., `Member`, `FinanceTransaction`)

**Variables & Methods:**
- Functions and local variables: `camelCase` (e.g., `fetchMembers()`, `activeGymId`)
- Constants: `lowerCamelCase` or `UPPER_SNAKE_CASE`

## Where to Add New Code

**New Feature Flow:**
- Presentation: Create a new folder under `lib/features/<feature_name>/` containing `*_screen.dart` and sub-widgets
- State: Create `lib/features/<feature_name>/<feature_name>_viewmodel.dart` extending `ChangeNotifier`
- Register: Register the ViewModel in `lib/main.dart` inside `MultiProvider`

**New Model Entity:**
- Implementation: Create `lib/core/models/<entity_name>.dart` with `toJson()` and `fromJson()`

**New Database Stored Procedure or Table:**
- Create an idempotent `.sql` migration file in root or `supabase/` with clear comments and RLS policies

---

*Structure analysis: 2026-09-16*
*Update when directories are rearranged or new feature domains are added*
