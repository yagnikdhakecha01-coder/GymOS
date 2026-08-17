class Member {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String alternatePhone;
  final String avatar;
  final String joinDate;
  final String status; // Active, Inactive, Pending
  final String membershipPlanId;
  final bool ptMember;
  final String ptTrainer; // Staff ID
  final String assignedWorkoutId;
  final String assignedDietId;
  final String medicalDetails;
  final String notes;
  final double pendingAmount;
  final double discountAmount;
  final double totalReceivedAmount;
  final String paymentStatus;
  final Map<String, dynamic> extraFields; // Stores health history, measurements, custom form values, etc.
  final String? createdAt; // Database created_at timestamp

  Member({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.alternatePhone = '',
    required this.avatar,
    required this.joinDate,
    required this.status,
    required this.membershipPlanId,
    required this.ptMember,
    required this.ptTrainer,
    required this.assignedWorkoutId,
    required this.assignedDietId,
    required this.medicalDetails,
    required this.notes,
    required this.pendingAmount,
    this.discountAmount = 0.0,
    this.totalReceivedAmount = 0.0,
    this.paymentStatus = 'Pending',
    this.extraFields = const {},
    this.createdAt,
  });

  String get memberCode =>
      (extraFields['member_code'] as String?) ??
      (extraFields['memberCode'] as String?) ??
      (phone.isNotEmpty ? phone : (id.length > 8 ? id.substring(0, 8).toUpperCase() : id));

  static Map<String, dynamic> _parseExtraFields(dynamic raw) {
    if (raw == null) return const {};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      alternatePhone: (json['alternate_phone'] ?? json['alternatePhone']) as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      joinDate: (json['join_date'] ?? json['joinDate']) as String? ?? '',
      status: json['status'] as String? ?? 'Active',
      membershipPlanId: (json['membership_plan_id'] ?? json['membershipPlanId']) as String? ?? '',
      ptMember: (json['pt_member'] ?? json['ptMember']) as bool? ?? false,
      ptTrainer: (json['pt_trainer'] ?? json['ptTrainer']) as String? ?? '',
      assignedWorkoutId: (json['assigned_workout_id'] ?? json['assignedWorkoutId']) as String? ?? '',
      assignedDietId: (json['assigned_diet_id'] ?? json['assignedDietId']) as String? ?? '',
      medicalDetails: (json['medical_details'] ?? json['medicalDetails']) as String? ?? 'None',
      notes: json['notes'] as String? ?? '',
      pendingAmount: ((json['pending_amount'] ?? json['pendingAmount']) as num?)?.toDouble() ?? 0.0,
      discountAmount: ((json['discount_amount'] ?? json['discountAmount']) as num?)?.toDouble() ?? 0.0,
      totalReceivedAmount: ((json['total_received_amount'] ?? json['totalReceivedAmount']) as num?)?.toDouble() ?? 0.0,
      paymentStatus: (json['payment_status'] ?? json['paymentStatus']) as String? ?? 'Pending',
      extraFields: _parseExtraFields(json['extra_fields'] ?? json['extraFields']),
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'alternate_phone': alternatePhone,
      'alternatePhone': alternatePhone,
      'avatar': avatar,
      'join_date': joinDate,
      'joinDate': joinDate,
      'status': status,
      'membership_plan_id': membershipPlanId,
      'membershipPlanId': membershipPlanId,
      'pt_member': ptMember,
      'ptMember': ptMember,
      'pt_trainer': ptTrainer,
      'ptTrainer': ptTrainer,
      'assigned_workout_id': assignedWorkoutId,
      'assignedWorkoutId': assignedWorkoutId,
      'assigned_diet_id': assignedDietId,
      'assignedDietId': assignedDietId,
      'medical_details': medicalDetails,
      'medicalDetails': medicalDetails,
      'notes': notes,
      'pending_amount': pendingAmount,
      'pendingAmount': pendingAmount,
      'discount_amount': discountAmount,
      'discountAmount': discountAmount,
      'total_received_amount': totalReceivedAmount,
      'totalReceivedAmount': totalReceivedAmount,
      'payment_status': paymentStatus,
      'paymentStatus': paymentStatus,
      'extra_fields': extraFields,
      'extraFields': extraFields,
      if (createdAt != null) 'created_at': createdAt,
    };
  }

  Member copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? alternatePhone,
    String? avatar,
    String? joinDate,
    String? status,
    String? membershipPlanId,
    bool? ptMember,
    String? ptTrainer,
    String? assignedWorkoutId,
    String? assignedDietId,
    String? medicalDetails,
    String? notes,
    double? pendingAmount,
    double? discountAmount,
    double? totalReceivedAmount,
    String? paymentStatus,
    Map<String, dynamic>? extraFields,
    String? createdAt,
  }) {
    return Member(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      alternatePhone: alternatePhone ?? this.alternatePhone,
      avatar: avatar ?? this.avatar,
      joinDate: joinDate ?? this.joinDate,
      status: status ?? this.status,
      membershipPlanId: membershipPlanId ?? this.membershipPlanId,
      ptMember: ptMember ?? this.ptMember,
      ptTrainer: ptTrainer ?? this.ptTrainer,
      assignedWorkoutId: assignedWorkoutId ?? this.assignedWorkoutId,
      assignedDietId: assignedDietId ?? this.assignedDietId,
      medicalDetails: medicalDetails ?? this.medicalDetails,
      notes: notes ?? this.notes,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      totalReceivedAmount: totalReceivedAmount ?? this.totalReceivedAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      extraFields: extraFields ?? this.extraFields,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
