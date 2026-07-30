enum UserRole { owner, staff, member }

class UserProfile {
  final String id;
  final String email;
  final UserRole role;
  final String? gymId;
  final bool setupCompleted;
  final String? fullName;
  final String? phoneNumber;
  final String? photoUrl;
  final String? dob;
  final String? experience;

  UserProfile({
    required this.id,
    required this.email,
    this.role = UserRole.member,
    this.gymId,
    this.setupCompleted = false,
    this.fullName,
    this.phoneNumber,
    this.photoUrl,
    this.dob,
    this.experience,
  });

  UserProfile copyWith({
    UserRole? role,
    String? gymId,
    bool? setupCompleted,
    String? fullName,
    String? phoneNumber,
    String? photoUrl,
    String? dob,
    String? experience,
  }) {
    return UserProfile(
      id: this.id,
      email: this.email,
      role: role ?? this.role,
      gymId: gymId ?? this.gymId,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      dob: dob ?? this.dob,
      experience: experience ?? this.experience,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] != null ? _parseRole(json['role'] as String) : UserRole.member,
      gymId: json['gym_id'] as String?,
      setupCompleted: json['setup_completed'] as bool? ?? false,
      fullName: json['full_name'] as String?,
      phoneNumber: json['phone_number'] as String?,
      photoUrl: json['photo_url'] as String?,
      dob: json['dob'] as String?,
      experience: json['experience'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role.name,
      'gym_id': gymId,
      'setup_completed': setupCompleted,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'photo_url': photoUrl,
      'dob': dob,
      'experience': experience,
    };
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
        throw ArgumentError('Invalid user role: $roleStr');
    }
  }
}
