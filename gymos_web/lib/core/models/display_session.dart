class AttendanceDisplaySession {
  final String id;
  final String gymId;
  final String displayPublicId;
  final String? deviceName;
  final String? browserFingerprint;
  final bool isVerified;
  final bool isEnabled;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final DateTime lastSeen;
  final DateTime createdAt;

  AttendanceDisplaySession({
    required this.id,
    required this.gymId,
    required this.displayPublicId,
    this.deviceName,
    this.browserFingerprint,
    required this.isVerified,
    required this.isEnabled,
    this.verifiedBy,
    this.verifiedAt,
    required this.lastSeen,
    required this.createdAt,
  });

  factory AttendanceDisplaySession.fromJson(Map<String, dynamic> json) {
    return AttendanceDisplaySession(
      id: json['id'] as String,
      gymId: json['gym_id'] as String,
      displayPublicId: (json['display_public_id'] ?? json['displayPublicId']) as String? ?? '',
      deviceName: json['device_name'] as String?,
      browserFingerprint: json['browser_fingerprint'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      isEnabled: json['is_enabled'] as bool? ?? true,
      verifiedBy: json['verified_by'] as String?,
      verifiedAt: json['verified_at'] != null ? DateTime.parse(json['verified_at'] as String) : null,
      lastSeen: DateTime.parse(json['last_seen'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gym_id': gymId,
      'display_public_id': displayPublicId,
      'device_name': deviceName,
      'browser_fingerprint': browserFingerprint,
      'is_verified': isVerified,
      'is_enabled': isEnabled,
      'verified_by': verifiedBy,
      'verified_at': verifiedAt?.toIso8601String(),
      'last_seen': lastSeen.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
