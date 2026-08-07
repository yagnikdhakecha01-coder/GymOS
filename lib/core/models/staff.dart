class Staff {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role; // Trainer, Receptionist, Dietitian, Accountant, Manager
  final String department;
  final String status; // Active, Inactive, On Leave
  final String joinDate;
  final String shift;
  final String experience;
  final double rating;
  final int sessionsCount;
  final int membersTrained;
  final double salary;
  final double salaryDue;
  final String avatar;
  final String? userId;
  final String gymId;

  // New fields
  final String gender;
  final String dob;
  final String aadhaar;
  final String emergencyName;
  final String emergencyPhone;
  final String address;
  final String employmentType; // Full Time, Part Time, Freelancer
  final String salaryType; // Fixed Salary, Percentage, Both
  final double commissionPercentage;
  final String qualification;
  final String notes;
  final Map<String, dynamic> permissions;

  // Custom Shift Properties
  final String shiftType; // 'single' or 'both'
  final String shift1Start; // e.g. '06:00 AM'
  final String shift1End; // e.g. '02:00 PM' or '11:00 AM'
  final String shift2Start; // e.g. '04:00 PM'
  final String shift2End; // e.g. '09:00 PM'

  Staff({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.department,
    required this.status,
    required this.joinDate,
    required this.shift,
    required this.experience,
    required this.rating,
    required this.sessionsCount,
    required this.membersTrained,
    required this.salary,
    required this.salaryDue,
    required this.avatar,
    this.userId,
    this.gymId = '',
    this.gender = '',
    this.dob = '',
    this.aadhaar = '',
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.address = '',
    this.employmentType = 'Full Time',
    this.salaryType = 'Fixed Salary',
    this.commissionPercentage = 0.0,
    this.qualification = '',
    this.notes = '',
    this.permissions = const {
      'add_member': true,
      'scan_attendance': true,
      'renew_membership': true,
      'add_income': true,
      'add_expense': true,
      'take_payment': true,
      'send_reminder': true,
      'broadcast': false,
      'manual_attendance': false,
      'attendance_correction': false,
    },
    this.shiftType = 'single',
    this.shift1Start = '09:00 AM',
    this.shift1End = '05:00 PM',
    this.shift2Start = '04:00 PM',
    this.shift2End = '09:00 PM',
  });

  factory Staff.fromJson(Map<String, dynamic> json) {
    return Staff(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'Trainer',
      department: json['department'] as String? ?? 'Training',
      status: json['status'] as String? ?? 'Active',
      joinDate: (json['join_date'] ?? json['joinDate']) as String? ?? '',
      shift: json['shift'] as String? ?? '9:00 AM - 5:00 PM',
      experience: json['experience'] as String? ?? 'N/A',
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      sessionsCount: (json['sessions_count'] ?? json['sessionsCount']) as int? ?? 0,
      membersTrained: (json['members_trained_count'] ?? json['membersTrained']) as int? ?? 0,
      salary: (json['salary'] as num?)?.toDouble() ?? 0.0,
      salaryDue: ((json['salary_due'] ?? json['salaryDue']) as num?)?.toDouble() ?? 0.0,
      avatar: json['avatar'] as String? ?? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200',
      userId: json['user_id'] as String?,
      gymId: json['gym_id'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      dob: json['dob'] as String? ?? '',
      aadhaar: json['aadhaar'] as String? ?? '',
      emergencyName: json['emergency_name'] as String? ?? '',
      emergencyPhone: json['emergency_phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      employmentType: json['employment_type'] as String? ?? 'Full Time',
      salaryType: json['salary_type'] as String? ?? 'Fixed Salary',
      commissionPercentage: (json['commission_percentage'] as num?)?.toDouble() ?? 0.0,
      qualification: json['qualification'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      permissions: json['permissions'] as Map<String, dynamic>? ?? const {
        'add_member': true,
        'scan_attendance': true,
        'renew_membership': true,
        'add_income': true,
        'add_expense': true,
        'take_payment': true,
        'send_reminder': true,
        'broadcast': false,
        'manual_attendance': false,
        'attendance_correction': false,
      },
      shiftType: json['shift_type'] as String? ?? 'single',
      shift1Start: json['shift1_start'] as String? ?? '09:00 AM',
      shift1End: json['shift1_end'] as String? ?? '05:00 PM',
      shift2Start: json['shift2_start'] as String? ?? '04:00 PM',
      shift2End: json['shift2_end'] as String? ?? '09:00 PM',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'department': department,
      'status': status,
      'joinDate': joinDate,
      'shift': shift,
      'experience': experience,
      'rating': rating,
      'sessionsCount': sessionsCount,
      'membersTrained': membersTrained,
      'salary': salary,
      'salaryDue': salaryDue,
      'avatar': avatar,
      'user_id': userId,
      'gym_id': gymId,
      'gender': gender,
      'dob': dob,
      'aadhaar': aadhaar,
      'emergency_name': emergencyName,
      'emergency_phone': emergencyPhone,
      'address': address,
      'employment_type': employmentType,
      'salary_type': salaryType,
      'commission_percentage': commissionPercentage,
      'qualification': qualification,
      'notes': notes,
      'permissions': permissions,
      'shift_type': shiftType,
      'shift1_start': shift1Start,
      'shift1_end': shift1End,
      'shift2_start': shift2Start,
      'shift2_end': shift2End,
    };
  }

  Staff copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? role,
    String? department,
    String? status,
    String? joinDate,
    String? shift,
    String? experience,
    double? rating,
    int? sessionsCount,
    int? membersTrained,
    double? salary,
    double? salaryDue,
    String? avatar,
    String? userId,
    String? gymId,
    String? gender,
    String? dob,
    String? aadhaar,
    String? emergencyName,
    String? emergencyPhone,
    String? address,
    String? employmentType,
    String? salaryType,
    double? commissionPercentage,
    String? qualification,
    String? notes,
    Map<String, dynamic>? permissions,
    String? shiftType,
    String? shift1Start,
    String? shift1End,
    String? shift2Start,
    String? shift2End,
  }) {
    return Staff(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      department: department ?? this.department,
      status: status ?? this.status,
      joinDate: joinDate ?? this.joinDate,
      shift: shift ?? this.shift,
      experience: experience ?? this.experience,
      rating: rating ?? this.rating,
      sessionsCount: sessionsCount ?? this.sessionsCount,
      membersTrained: membersTrained ?? this.membersTrained,
      salary: salary ?? this.salary,
      salaryDue: salaryDue ?? this.salaryDue,
      avatar: avatar ?? this.avatar,
      userId: userId ?? this.userId,
      gymId: gymId ?? this.gymId,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      aadhaar: aadhaar ?? this.aadhaar,
      emergencyName: emergencyName ?? this.emergencyName,
      emergencyPhone: emergencyPhone ?? this.emergencyPhone,
      address: address ?? this.address,
      employmentType: employmentType ?? this.employmentType,
      salaryType: salaryType ?? this.salaryType,
      commissionPercentage: commissionPercentage ?? this.commissionPercentage,
      qualification: qualification ?? this.qualification,
      notes: notes ?? this.notes,
      permissions: permissions ?? this.permissions,
      shiftType: shiftType ?? this.shiftType,
      shift1Start: shift1Start ?? this.shift1Start,
      shift1End: shift1End ?? this.shift1End,
      shift2Start: shift2Start ?? this.shift2Start,
      shift2End: shift2End ?? this.shift2End,
    );
  }
}
