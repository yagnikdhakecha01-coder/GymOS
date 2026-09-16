# Testing Patterns

**Analysis Date:** 2026-09-16

## Test Framework

**Runner:**
- `flutter_test` (Built into the Flutter SDK)
- Test directory: `test/`

**Run Commands:**
```bash
flutter test                       # Run all test suites
flutter test test/widget_test.dart # Run specific test file
flutter analyze                    # Static analysis check
```

## Existing Test Files & Utilities

**Diagnostic & Integration Scripts (`test/`):**
- `test/widget_test.dart` - Basic smoke test for app widget initialization
- `test/test_db.dart` - Database connectivity verification script for Supabase tables
- `test/debug_db.dart` - Database query validation and schema verification
- `test/debug_staff_attendance.dart` - Attendance engine logic and staff shift verification

## Test File Organization

**Standard Flutter Pattern:**
```
test/
├── core/
│   ├── models/                  # Model serialization/deserialization unit tests
│   └── services/                # LocalStorage and utility tests
├── features/
│   ├── attendance/              # Attendance logic & shift calculation tests
│   └── finance/                 # Salary calculations & commission tests
└── widget_test.dart             # Root widget smoke test
```

## Testing Guidelines

**Unit Tests (Models & Services):**
- Verify JSON `fromJson` and `toJson` integrity across all 21 models in `lib/core/models/`
- Test calculation logic in `GymRepository` and finance utilities (e.g., pending salary, attendance rate, gross salary)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gymos/core/models/member.dart';

void main() {
  group('Member Model Serialization', () {
    test('correctly parses JSON to Member instance', () {
      final json = {
        'id': 'm123',
        'name': 'John Doe',
        'phone': '9876543210',
        'status': 'active',
      };
      final member = Member.fromJson(json);
      expect(member.id, 'm123');
      expect(member.name, 'John Doe');
      expect(member.status, 'active');
    });
  });
}
```

**Widget Tests:**
- Test key dialogs and reusable components in isolation using `WidgetTester`
- Provide mock ViewModels via `MultiProvider` to test UI responses without network dependencies

---

*Testing analysis: 2026-09-16*
*Update as test coverage and automated test suites expand*
