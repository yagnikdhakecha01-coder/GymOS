import '../models/attendance.dart';

/// Day-level attendance status for staff (calendar dots, summary counts).
class StaffDayAttendanceStatus {
  static bool isBothShiftStaff({String? shiftType, String? shift}) {
    if (shiftType == 'both') return true;
    final s = (shift ?? '').toLowerCase();
    return s.contains('both') || s.contains('double') || s.contains('two');
  }

  static bool _isPresentLike(String status) {
    return status == 'Present' ||
        status == 'Late' ||
        status == 'Early Exit' ||
        status == 'Overtime';
  }

  static bool _isLeaveLike(String status) {
    return status == 'Leave' || status == 'On Leave' || status == 'Holiday';
  }

  /// Returns: present | absent | half day | holiday | pending
  static String deriveDayStatus({
    required List<AttendanceRecord> dayLogs,
    required DateTime targetDate,
    required bool isBothShift,
    required DateTime now,
    bool isBeforeJoinDate = false,
  }) {
    if (isBeforeJoinDate) return 'holiday';

    final todayOnly = DateTime(now.year, now.month, now.day);
    final targetOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);

    if (dayLogs.isEmpty) {
      if (targetDate.weekday == DateTime.sunday) return 'holiday';
      if (!targetOnly.isBefore(todayOnly)) return 'pending';
      return 'absent';
    }

    if (!isBothShift) {
      final log = dayLogs.first;
      if (_isPresentLike(log.status)) return 'present';
      if (log.status == 'Half Day' || log.status == 'Half Leave') return 'half day';
      if (log.status == 'Absent') return 'absent';
      if (_isLeaveLike(log.status)) return 'holiday';
      return 'holiday';
    }

    final absentCount = dayLogs.where((r) => r.status == 'Absent').length;
    final presentCount = dayLogs.where((r) => _isPresentLike(r.status)).length;
    final halfCount = dayLogs.where((r) => r.status == 'Half Day' || r.status == 'Half Leave').length;
    final leaveCount = dayLogs.where((r) => _isLeaveLike(r.status)).length;

    if (leaveCount > 0) return 'holiday';
    if (halfCount > 0) return 'half day';

    // Zero present shifts worked = staff has NOT attended any shift at all!
    if (presentCount == 0) {
      if (absentCount >= 1) return 'absent';
      if (!targetOnly.isBefore(todayOnly)) return 'pending';
      return 'absent';
    }

    // At least 1 present shift worked:
    if (absentCount >= 1 && presentCount >= 1) return 'half day';
    if (presentCount >= 1 && absentCount == 0) return 'present';

    if (!targetOnly.isBefore(todayOnly)) return 'pending';
    return 'absent';
  }

  static double absentWeight(String dayStatus) {
    if (dayStatus == 'absent') return 1.0;
    if (dayStatus == 'half day') return 0.5;
    return 0.0;
  }

  static double presentWeight(String dayStatus) {
    if (dayStatus == 'present') return 1.0;
    if (dayStatus == 'half day') return 0.5;
    return 0.0;
  }
}
