class SalaryDraft {
  final String id;
  final String gymId;
  final String staffId;
  final String salaryMonth;
  final double baseSalary;
  final double commissionAmount;
  final double advanceDeduction;
  final double otherAdditions;
  final double otherDeductions;
  final double netSalary;
  final String status; // Draft, Approved, Paid

  SalaryDraft({
    required this.id,
    required this.gymId,
    required this.staffId,
    required this.salaryMonth,
    required this.baseSalary,
    required this.commissionAmount,
    required this.advanceDeduction,
    required this.otherAdditions,
    required this.otherDeductions,
    required this.netSalary,
    required this.status,
  });

  factory SalaryDraft.fromJson(Map<String, dynamic> json) {
    return SalaryDraft(
      id: json['id'] as String,
      gymId: json['gym_id'] as String,
      staffId: json['staff_id'] as String,
      salaryMonth: json['salary_month'] as String,
      baseSalary: (json['base_salary'] as num? ?? 0.0).toDouble(),
      commissionAmount: (json['commission_amount'] as num? ?? 0.0).toDouble(),
      advanceDeduction: (json['advance_deduction'] as num? ?? 0.0).toDouble(),
      otherAdditions: (json['other_additions'] as num? ?? 0.0).toDouble(),
      otherDeductions: (json['other_deductions'] as num? ?? 0.0).toDouble(),
      netSalary: (json['net_salary'] as num? ?? 0.0).toDouble(),
      status: json['status'] as String? ?? 'Draft',
    );
  }
}
