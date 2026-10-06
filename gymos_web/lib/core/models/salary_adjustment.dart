class SalaryAdjustment {
  final String id;
  final String gymId;
  final String salaryDraftId;
  final String type; // Addition, Deduction
  final double amount;
  final String reason;
  final String createdAt;

  SalaryAdjustment({
    required this.id,
    required this.gymId,
    required this.salaryDraftId,
    required this.type,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  factory SalaryAdjustment.fromJson(Map<String, dynamic> json) {
    return SalaryAdjustment(
      id: json['id'] as String,
      gymId: json['gym_id'] as String,
      salaryDraftId: json['salary_draft_id'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      reason: json['reason'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
