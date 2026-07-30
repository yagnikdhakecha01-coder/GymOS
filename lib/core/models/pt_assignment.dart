class PtAssignment {
  final String id;
  final String gymId;
  final String memberId;
  final String staffId;
  final double commissionPercentage;
  final String assignmentStatus; // Active, Inactive
  final String ptStartDate;
  final String? createdBy;
  final String createdAt;
  final String updatedAt;

  PtAssignment({
    required this.id,
    required this.gymId,
    required this.memberId,
    required this.staffId,
    required this.commissionPercentage,
    this.assignmentStatus = 'Active',
    required this.ptStartDate,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PtAssignment.fromJson(Map<String, dynamic> json) {
    return PtAssignment(
      id: json['id'] as String,
      gymId: json['gym_id'] as String,
      memberId: json['member_id'] as String,
      staffId: json['staff_id'] as String,
      commissionPercentage: (json['commission_percentage'] as num?)?.toDouble() ?? 0.0,
      assignmentStatus: json['assignment_status'] as String? ?? 'Active',
      ptStartDate: json['pt_start_date'] as String? ?? '',
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gym_id': gymId,
      'member_id': memberId,
      'staff_id': staffId,
      'commission_percentage': commissionPercentage,
      'assignment_status': assignmentStatus,
      'pt_start_date': ptStartDate,
      'created_by': createdBy,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
