import 'user_profile.dart';

class UserGymAssociation {
  final String id;
  final String userId;
  final String gymId;
  final UserRole role;
  final bool setupCompleted;
  final String? gymName;
  final String? gymCode;
  final String? createdAt;

  UserGymAssociation({
    required this.id,
    required this.userId,
    required this.gymId,
    required this.role,
    required this.setupCompleted,
    this.gymName,
    this.gymCode,
    this.createdAt,
  });

  factory UserGymAssociation.fromJson(Map<String, dynamic> json) {
    return UserGymAssociation(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      gymId: json['gym_id'] as String,
      role: _parseRole(json['role'] as String),
      setupCompleted: json['setup_completed'] as bool? ?? false,
      gymName: json['gyms']?['name'] as String?,
      gymCode: json['gyms']?['gym_code'] as String?,
      createdAt: (json['created_at'] ?? json['createdAt']) as String?,
    );
  }

  static UserRole _parseRole(String roleStr) {
    switch (roleStr.toLowerCase()) {
      case 'owner':
        return UserRole.owner;
      case 'staff':
        return UserRole.staff;
      case 'member':
        return UserRole.member;
      default:
        return UserRole.member;
    }
  }
}
