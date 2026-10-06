class AttendanceAlert {
  final String id;
  final String gymId;
  final String alertType;
  final String message;
  final Map<String, dynamic> metadata;
  final bool isRead;
  final DateTime createdAt;

  AttendanceAlert({
    required this.id,
    required this.gymId,
    required this.alertType,
    required this.message,
    required this.metadata,
    required this.isRead,
    required this.createdAt,
  });

  factory AttendanceAlert.fromJson(Map<String, dynamic> json) {
    return AttendanceAlert(
      id: json['id'] as String? ?? '',
      gymId: json['gym_id'] as String? ?? '',
      alertType: json['alert_type'] as String? ?? '',
      message: json['message'] as String? ?? '',
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String).toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gym_id': gymId,
      'alert_type': alertType,
      'message': message,
      'metadata': metadata,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
