import 'dart:convert';

/// Represents a manual attendance entry stored locally (offline-first).
/// Used for Emergency Manual Attendance when Supabase is unavailable.
class ManualAttendanceEntry {
  final String operationUuid;
  final String gymId;
  final String? memberId;
  final String? staffId;
  final String? userId;
  final String userType; // 'Member' or 'Staff'
  final String userName;
  final String? userAvatar;
  final String status; // 'Present', 'Late'
  final String date; // 'dd-MM-yyyy'
  final String checkInIso;
  final String? checkOutIso;
  final String? shiftId;
  final String? shiftName;
  final String reason;
  final String addedBy;
  final String addedByRole; // 'Owner' or 'Staff'
  String syncStatus; // 'pending', 'syncing', 'synced', 'failed'
  int retryCount;
  String? errorMessage;
  final DateTime createdAt;
  DateTime updatedAt;

  ManualAttendanceEntry({
    required this.operationUuid,
    required this.gymId,
    this.memberId,
    this.staffId,
    this.userId,
    required this.userType,
    required this.userName,
    this.userAvatar,
    required this.status,
    required this.date,
    required this.checkInIso,
    this.checkOutIso,
    this.shiftId,
    this.shiftName,
    required this.reason,
    required this.addedBy,
    required this.addedByRole,
    this.syncStatus = 'pending',
    this.retryCount = 0,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ManualAttendanceEntry.fromJson(Map<String, dynamic> json) {
    return ManualAttendanceEntry(
      operationUuid: json['operation_uuid'] as String,
      gymId: json['gym_id'] as String,
      memberId: json['member_id'] as String?,
      staffId: json['staff_id'] as String?,
      userId: json['user_id'] as String?,
      userType: json['user_type'] as String? ?? 'Member',
      userName: json['user_name'] as String? ?? '',
      userAvatar: json['user_avatar'] as String?,
      status: json['status'] as String? ?? 'Present',
      date: json['date'] as String? ?? '',
      checkInIso: json['check_in_iso'] as String? ?? '',
      checkOutIso: json['check_out_iso'] as String?,
      shiftId: json['shift_id'] as String?,
      shiftName: json['shift_name'] as String?,
      reason: json['reason'] as String? ?? '',
      addedBy: json['added_by'] as String? ?? '',
      addedByRole: json['added_by_role'] as String? ?? 'Owner',
      syncStatus: json['sync_status'] as String? ?? 'pending',
      retryCount: json['retry_count'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'operation_uuid': operationUuid,
      'gym_id': gymId,
      'member_id': memberId,
      'staff_id': staffId,
      'user_id': userId,
      'user_type': userType,
      'user_name': userName,
      'user_avatar': userAvatar,
      'status': status,
      'date': date,
      'check_in_iso': checkInIso,
      'check_out_iso': checkOutIso,
      'shift_id': shiftId,
      'shift_name': shiftName,
      'reason': reason,
      'added_by': addedBy,
      'added_by_role': addedByRole,
      'sync_status': syncStatus,
      'retry_count': retryCount,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  ManualAttendanceEntry copyWith({
    String? syncStatus,
    int? retryCount,
    String? errorMessage,
    DateTime? updatedAt,
  }) {
    return ManualAttendanceEntry(
      operationUuid: operationUuid,
      gymId: gymId,
      memberId: memberId,
      staffId: staffId,
      userId: userId,
      userType: userType,
      userName: userName,
      userAvatar: userAvatar,
      status: status,
      date: date,
      checkInIso: checkInIso,
      checkOutIso: checkOutIso,
      shiftId: shiftId,
      shiftName: shiftName,
      reason: reason,
      addedBy: addedBy,
      addedByRole: addedByRole,
      syncStatus: syncStatus ?? this.syncStatus,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
