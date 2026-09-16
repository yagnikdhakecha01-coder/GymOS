# Architecture

**Analysis Date:** 2026-09-16

## Pattern Overview

**Overall:** Multi-Tenant Mobile SaaS with MVVM (Model-View-ViewModel) and Repository Pattern with Offline-First Local Cache.

**Key Characteristics:**
- **Tri-Portal Architecture:** A single unified codebase powers 3 distinct roles:
  1. *Owner Portal* (Comprehensive gym administration, billing, staff payroll, analytics)
  2. *Staff/Trainer Portal* (Client allocation, shift check-ins, attendance tracking, request submissions)
  3. *Member App* (QR check-in, assigned workouts, personalized diet charts, fee payment history)
- **Centralized Data Coordination:** A single primary repository (`GymRepository`) synchronizes cloud state (Supabase) with local storage (`LocalStorageService`).
- **Reactive State Management:** Feature-based ViewModels inherit from `ChangeNotifier` and expose immutable state updates through Flutter's `Provider`.

## Layers

**Presentation Layer (`lib/features/`):**
- Purpose: Render user interfaces, handle gestures, and react to ViewModel notifications
- Contains: Flutter `StatelessWidget` and `StatefulWidget` classes grouped by feature domain
- Depends on: Corresponding ViewModels provided via context
- Used by: End users (Owners, Trainers, Members)

**ViewModel / State Layer (`lib/features/*/*_viewmodel.dart`):**
- Purpose: Mediate between UI events and data operations, hold transient UI state, format data
- Contains: `ChangeNotifier` subclasses (e.g., `MembersViewModel`, `AttendanceViewModel`, `FinanceViewModel`)
- Depends on: `GymRepository` and specialized core services
- Used by: UI Screens and Widgets

**Domain / Model Layer (`lib/core/models/`):**
- Purpose: Define strongly typed business entities with JSON serialization
- Contains: 21 core data models (`Member`, `Staff`, `Attendance`, `FinanceTransaction`, `DietPlan`, `WorkoutPlan`, etc.)
- Depends on: Pure Dart standard library (`dart:convert`)

**Repository Layer (`lib/core/repository/gym_repository.dart`):**
- Purpose: Orchestrate data persistence, offline fallbacks, and remote Supabase synchronization
- Contains: `GymRepository` class exposing CRUD operations and cache invalidation routines
- Depends on: `LocalStorageService`, `SupabaseClient`
- Used by: All ViewModels

**Service Layer (`lib/core/services/`):**
- Purpose: Encapsulate low-level platform APIs and 3rd party SDK interactions
- Contains: `SupabaseService`, `AuthService`, `LocalStorageService`, `NotificationService`, `BiometricService`, `VersionCheckService`
- Depends on: Native platform plugins and external packages

## Data Flow

**Typical Execution Flow (Read/Write Mutation):**

1. **User Interaction:** User initiates an action (e.g., adds new member or checks in via QR).
2. **ViewModel Dispatch:** The Screen invokes the corresponding ViewModel method (`membersViewModel.addMember(...)`).
3. **Repository Execution:** The ViewModel calls `GymRepository.addMember(...)`.
4. **Optimistic Local Update:** `GymRepository` immediately saves the record to local `LocalStorageService` and updates memory lists.
5. **UI Notification:** The ViewModel calls `notifyListeners()`, causing widgets to immediately render the new state with zero perceived latency.
6. **Background Remote Sync:** `GymRepository` asynchronously executes the insert/update query or RPC against Supabase PostgreSQL.
7. **Confirmation or Rollback:** On remote success, the local cache is synced with the server ID; on failure, the error is caught and reported to the user.

**State Management:**
- Application state is registered at the root in `lib/main.dart` using `MultiProvider`.
- Cross-screen persistent state resides in `GymRepository` and `LocalStorageService`.

## Key Abstractions

**GymRepository (`lib/core/repository/gym_repository.dart`):**
- Purpose: Central data access object and offline caching coordinator
- Pattern: Repository Pattern

**LocalStorageService (`lib/core/services/local_storage.dart`):**
- Purpose: Abstract wrapper around `SharedPreferences` handling JSON encode/decode
- Pattern: Data Access Object (DAO) / Cache Gateway

**Notification Engines (`lib/core/services/alerts_notification_engine.dart`):**
- Purpose: Evaluate business rules (e.g., shift absence, trial expiry) and schedule heads-up alerts
- Pattern: Strategy / Observer Pattern

## Entry Points

**Mobile Application:**
- Location: `lib/main.dart` -> `main()`
- Triggers: App launch on Android / iOS
- Responsibilities:
  1. `WidgetsFlutterBinding.ensureInitialized()`
  2. Initialize `SupabaseService` with environment credentials
  3. Initialize `NotificationService` and request notification permissions
  4. Initialize `SharedPreferences` and instantiate `GymRepository`
  5. Mount `GymOSApp` with `MultiProvider` tree

**Splash & Routing Router:**
- Location: `lib/features/authentication/splash_screen.dart`
- Responsibilities: Checks active auth session and user role, then redirects to Owner Dashboard, Trainer Portal, or Member App

## Error Handling

**Strategy:**
- Fail-safe initialization: If Supabase initialization fails (e.g., device is offline), the app falls back to offline cached mode rather than crashing.
- User feedback: User-facing operations present contextual SnackBar banners with clear action prompts.
- Database RPC guards: Complex business rules (salary calculations, auto-absent triggers) are encapsulated in PostgreSQL stored procedures with transaction rollback safety.

---

*Architecture analysis: 2026-09-16*
*Update after major structural or architectural changes*
