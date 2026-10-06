/// Represents an audit log entry for manual attendance operations.
/// Every manual attendance and correction generates an audit record.
class AttendanceAuditLog {
  final String id;
  final String gymId;
  final String actionType; // 'manual_attendance', 'attendance_correction'
  final String performedBy;
  final String performedByRole; // 'Owner', 'Staff'
  final String targetUserName;
  final String targetUserType; // 'Member', 'Staff'
  final String targetUserId;
  final String date;
  final String? oldStatus;
  final String? newStatus;
  final String? oldCheckIn;
  final String? newCheckIn;
  final String? oldCheckOut;
  final String? newCheckOut;
  final String? oldShift;
  final String? newShift;
  final String reason;
  final DateTime createdAt;

  AttendanceAuditLog({
    required this.id,
    required this.gymId,
    required this.actionType,
    required this.performedBy,
    required this.performedByRole,
    required this.targetUserName,
    required this.targetUserType,
    required this.targetUserId,
    required this.date,
    this.oldStatus,
    this.newStatus,
    this.oldCheckIn,
    this.newCheckIn,
    this.oldCheckOut,
    this.newCheckOut,
    this.oldShift,
    this.newShift,
    required this.reason,
    required this.createdAt,
  });

  factory AttendanceAuditLog.fromJson(Map<String, dynamic> json) {
    return AttendanceAuditLog(
      id: json['id'] as String? ?? '',
      gymId: json['gym_id'] as String? ?? '',
      actionType: json['action_type'] as String? ?? 'manual_attendance',
      performedBy: json['performed_by'] as String? ?? '',
      performedByRole: json['performed_by_role'] as String? ?? 'Owner',
      targetUserName: json['target_user_name'] as String? ?? '',
      targetUserType: json['target_user_type'] as String? ?? 'Member',
      targetUserId: json['target_user_id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      oldStatus: json['old_status'] as String?,
      newStatus: json['new_status'] as String?,
      oldCheckIn: json['old_check_in'] as String?,
      newCheckIn: json['new_check_in'] as String?,
      oldCheckOut: json['old_check_out'] as String?,
      newCheckOut: json['new_check_out'] as String?,
      oldShift: json['old_shift'] as String?,
      newShift: json['new_shift'] as String?,
      reason: json['reason'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gym_id': gymId,
      'action_type': actionType,
      'performed_by': performedBy,
      'performed_by_role': performedByRole,
      'target_user_name': targetUserName,
      'target_user_type': targetUserType,
      'target_user_id': targetUserId,
      'date': date,
      'old_status': oldStatus,
      'new_status': newStatus,
      'old_check_in': oldCheckIn,
      'new_check_in': newCheckIn,
      'old_check_out': oldCheckOut,
      'new_check_out': newCheckOut,
      'old_shift': oldShift,
      'new_shift': newShift,
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
