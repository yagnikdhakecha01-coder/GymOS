class AttendanceCorrectionRequest {
  final String id;
  final String gymId;
  final String staffId;
  final String? staffName;
  final String? attendanceLogId;
  final String requestDate;
  final DateTime requestedCheckIn;
  final DateTime? requestedCheckOut;
  final String? reason;
  final String status; // Pending, Approved, Rejected
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  AttendanceCorrectionRequest({
    required this.id,
    required this.gymId,
    required this.staffId,
    this.staffName,
    this.attendanceLogId,
    required this.requestDate,
    required this.requestedCheckIn,
    this.requestedCheckOut,
    this.reason,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
  });

  factory AttendanceCorrectionRequest.fromJson(Map<String, dynamic> json) {
    String? staffName;
    if (json['staff'] != null && json['staff']['name'] != null) {
      staffName = json['staff']['name'] as String;
    }

    return AttendanceCorrectionRequest(
      id: json['id'] as String? ?? '',
      gymId: json['gym_id'] as String? ?? '',
      staffId: json['staff_id'] as String? ?? '',
      staffName: staffName,
      attendanceLogId: json['attendance_log_id'] as String?,
      requestDate: json['request_date'] as String? ?? '',
      requestedCheckIn: DateTime.parse(json['requested_check_in'] as String).toLocal(),
      requestedCheckOut: json['requested_check_out'] != null
          ? DateTime.parse(json['requested_check_out'] as String).toLocal()
          : null,
      reason: json['reason'] as String?,
      status: json['status'] as String? ?? 'Pending',
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String).toLocal()
          : null,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gym_id': gymId,
      'staff_id': staffId,
      'attendance_log_id': attendanceLogId,
      'request_date': requestDate,
      'requested_check_in': requestedCheckIn.toIso8601String(),
      'requested_check_out': requestedCheckOut?.toIso8601String(),
      'reason': reason,
      'status': status,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
