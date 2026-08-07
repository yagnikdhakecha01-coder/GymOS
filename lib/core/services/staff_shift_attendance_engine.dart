import 'package:intl/intl.dart';

class StaffShiftAttendanceEngine {
  /// Parses standard 12-hour formatted time strings (e.g., '06:00 AM', '02:00 PM') into a DateTime object on a target date.
  static DateTime? parseTimeToDateTime(String timeStr, {DateTime? targetDate}) {
    try {
      final date = targetDate ?? DateTime.now();
      final cleanStr = timeStr.trim();
      final parsed = DateFormat('hh:mm a').parse(cleanStr);
      return DateTime(date.year, date.month, date.day, parsed.hour, parsed.minute);
    } catch (_) {
      try {
        final cleanStr = timeStr.trim();
        final parsed = DateFormat('HH:mm').parse(cleanStr);
        final date = targetDate ?? DateTime.now();
        return DateTime(date.year, date.month, date.day, parsed.hour, parsed.minute);
      } catch (_) {
        return null;
      }
    }
  }

  /// Calculates staff attendance status based on shift timings and check-in time (+1 hour late/absent rule).
  /// 
  /// - Check-in within [Shift Start] to [Shift Start + 60 mins] => 'Present' (On Time)
  /// - Check-in after [Shift Start + 60 mins] => 'Late'
  /// - If [Shift End + 60 mins] has passed with no check-in => 'Absent'
  static Map<String, dynamic> evaluateAttendanceStatus({
    required String shiftStartStr,
    required String shiftEndStr,
    DateTime? checkInDateTime,
    DateTime? nowDateTime,
  }) {
    final now = nowDateTime ?? DateTime.now();
    final shiftStart = parseTimeToDateTime(shiftStartStr, targetDate: now);
    final shiftEnd = parseTimeToDateTime(shiftEndStr, targetDate: now);

    if (shiftStart == null || shiftEnd == null) {
      return {
        'status': checkInDateTime != null ? 'Present' : 'Not Checked In',
        'is_late': false,
        'late_minutes': 0,
        'is_absent': false,
      };
    }

    // 1-hour thresholds
    final lateThreshold = shiftStart.add(const Duration(hours: 1));
    final absentThreshold = shiftEnd.add(const Duration(hours: 1));

    if (checkInDateTime != null) {
      if (checkInDateTime.isAfter(lateThreshold)) {
        final lateMins = checkInDateTime.difference(shiftStart).inMinutes;
        return {
          'status': 'Late',
          'is_late': true,
          'late_minutes': lateMins > 0 ? lateMins : 0,
          'is_absent': false,
        };
      } else {
        return {
          'status': 'Present',
          'is_late': false,
          'late_minutes': 0,
          'is_absent': false,
        };
      }
    } else {
      // No check-in recorded yet
      if (now.isAfter(absentThreshold)) {
        return {
          'status': 'Absent',
          'is_late': false,
          'late_minutes': 0,
          'is_absent': true,
        };
      } else {
        return {
          'status': 'Pending',
          'is_late': false,
          'late_minutes': 0,
          'is_absent': false,
        };
      }
    }
  }
}
