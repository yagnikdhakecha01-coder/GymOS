# Coding Conventions

**Analysis Date:** 2026-09-16

## Naming Patterns

**Files:**
- Screens: `*_screen.dart` (e.g., `member_profile_screen.dart`, `splash_screen.dart`)
- ViewModels: `*_viewmodel.dart` (e.g., `members_viewmodel.dart`, `attendance_viewmodel.dart`)
- Models: `[entity].dart` (e.g., `member.dart`, `diet_plan.dart`, `workout_plan.dart`)
- Services: `*_service.dart` (e.g., `auth_service.dart`, `notification_service.dart`)
- Widgets: `*_card.dart`, `*_tile.dart`, `*_sheet.dart` (e.g., `stat_card.dart`)

**Functions & Methods:**
- `camelCase` for all methods: `loadMembers()`, `recordAttendance()`, `calculateSalary()`
- Asynchronous functions return `Future<void>` or `Future<T>`: `Future<void> fetchDashboardStats()`
- Boolean getters start with `is`, `has`, or `can`: `isLoading`, `hasActiveSubscription`, `canScanQR`

**Variables:**
- `camelCase` for variables: `selectedDate`, `totalRevenue`, `memberList`
- Private class members prefixed with underscore: `_isLoading`, `_errorMessage`, `_members`

**Types & Classes:**
- `PascalCase` for all classes, enums, and typedefs: `GymRepository`, `AttendanceStatus`, `MemberRole`

## Code Style

**Formatting & Linting:**
- Linter: `package:flutter_lints/flutter.yaml` configured in `analysis_options.yaml`
- Line length: Standard Dart 80-100 characters
- Trailing commas: Encouraged on all multi-line widget trees for clean Flutter auto-formatting
- `const` constructors: Required wherever possible to optimize Flutter widget rebuild performance

**Theme & Visual Design Tokens:**
- Primary Color: `#6C3AED` (Royal Purple / Violet)
- Backgrounds: Dark slate `#0F172A` / `#030712`, card background `#1E293B`
- Typography: Inter from `google_fonts` (`google_fonts: ^8.2.0`)
- Borders: Subtle translucent borders (`border: Border.all(color: Colors.white.withOpacity(0.08))`)

## Import Organization

**Standard Ordering:**
1. Dart SDK imports (`dart:async`, `dart:convert`, `dart:io`)
2. Flutter framework imports (`package:flutter/material.dart`, `package:flutter/services.dart`)
3. Third-party package imports (`package:provider/provider.dart`, `package:supabase_flutter/...`)
4. Core internal imports (`import '../../core/models/...';`, `import '../../core/theme/...';`)
5. Feature-level relative imports (`import 'widgets/...';`)

## Error Handling

**Repository & Service Level:**
- Wrap remote calls in `try ... catch (e, stack)` blocks
- Never let unhandled network exceptions crash the app; log using `debugPrint` and set clean user-friendly fallback state

```dart
try {
  final response = await _client.from('members').select();
  return response.map((data) => Member.fromJson(data)).toList();
} catch (e, stack) {
  debugPrint('Error loading members: $e');
  // Fall back to local storage cache
  return _localStorage.getCachedMembers();
}
```

**UI Level:**
- Use `ScaffoldMessenger.of(context).showSnackBar` with clear colored backgrounds:
  - Green for success (`Colors.green`)
  - Red for errors (`Colors.redAccent`)
  - Violet/Blue for information (`const Color(0xFF6C3AED)`)

## State Management Pattern

**ViewModel Lifecycle:**
```dart
class MembersViewModel extends ChangeNotifier {
  final GymRepository _repository;
  bool _isLoading = false;
  List<Member> _members = [];

  bool get isLoading => _isLoading;
  List<Member> get members => List.unmodifiable(_members);

  Future<void> fetchMembers() async {
    _isLoading = true;
    notifyListeners();
    try {
      _members = await _repository.getMembers();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

---

*Conventions analysis: 2026-09-16*
*Update when team conventions or linter rules change*
