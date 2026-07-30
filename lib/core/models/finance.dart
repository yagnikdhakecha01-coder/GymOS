class FinanceTransaction {
  final String id;
  final String gymId;
  final String title;
  final double amount;
  final String type; // Revenue, Expense
  final String category; // Membership, Salary, Rent, Utilities, Protein Sale, Personal Training, etc.
  final String paymentMethod; // Cash, UPI, Card, Bank Transfer, Cheque, Other
  final String date; // String display format (e.g. 19 Jul 2026)
  final String transactionDate; // ISO timestamp
  final String referenceId;
  final String createdBy;
  final String notes;
  final String expenseDate;
  final String revenueDate;
  final String entryDate;
  final String createdByInfo;

  FinanceTransaction({
    required this.id,
    this.gymId = '',
    required this.title,
    required this.amount,
    required this.type,
    required this.category,
    this.paymentMethod = 'Cash',
    required this.date,
    this.transactionDate = '',
    this.referenceId = '',
    this.createdBy = '',
    required this.notes,
    this.expenseDate = '',
    this.revenueDate = '',
    this.entryDate = '',
    this.createdByInfo = '',
  });

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) {
    String displayDate = json['date'] as String? ?? '';
    final txDateStr = (json['transaction_date'] ?? json['transactionDate']) as String? ?? '';
    if (displayDate.isEmpty && txDateStr.isNotEmpty) {
      try {
        final parsed = DateTime.parse(txDateStr);
        displayDate = '${parsed.day} ${_getMonthName(parsed.month)} ${parsed.year}';
      } catch (_) {}
    }

    return FinanceTransaction(
      id: json['id'] as String,
      gymId: (json['gym_id'] ?? json['gymId']) as String? ?? '',
      title: json['title'] as String? ?? (json['category'] ?? 'Transaction'),
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String,
      category: json['category'] as String? ?? 'Other',
      paymentMethod: (json['payment_method'] ?? json['paymentMethod']) as String? ?? 'Cash',
      date: displayDate,
      transactionDate: txDateStr,
      referenceId: (json['reference_id'] ?? json['referenceId']) as String? ?? '',
      createdBy: (json['created_by'] ?? json['createdBy']) as String? ?? '',
      notes: json['notes'] as String? ?? '',
      expenseDate: (json['expense_date'] ?? json['expenseDate']) as String? ?? '',
      revenueDate: (json['revenue_date'] ?? json['revenueDate']) as String? ?? '',
      entryDate: (json['entry_date'] ?? json['entryDate']) as String? ?? '',
      createdByInfo: (json['created_by_info'] ?? json['createdByInfo']) as String? ?? '',
    );
  }

  static String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) {
      return months[month - 1];
    }
    return '';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gym_id': gymId,
      'title': title,
      'amount': amount,
      'type': type,
      'category': category,
      'payment_method': paymentMethod,
      'date': date,
      'transaction_date': transactionDate,
      'reference_id': referenceId,
      'created_by': createdBy,
      'notes': notes,
      'expense_date': expenseDate,
      'revenue_date': revenueDate,
      'entry_date': entryDate,
      'created_by_info': createdByInfo,
    };
  }

  FinanceTransaction copyWith({
    String? id,
    String? gymId,
    String? title,
    double? amount,
    String? type,
    String? category,
    String? paymentMethod,
    String? date,
    String? transactionDate,
    String? referenceId,
    String? createdBy,
    String? notes,
    String? expenseDate,
    String? revenueDate,
    String? entryDate,
    String? createdByInfo,
  }) {
    return FinanceTransaction(
      id: id ?? this.id,
      gymId: gymId ?? this.gymId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      category: category ?? this.category,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      date: date ?? this.date,
      transactionDate: transactionDate ?? this.transactionDate,
      referenceId: referenceId ?? this.referenceId,
      createdBy: createdBy ?? this.createdBy,
      notes: notes ?? this.notes,
      expenseDate: expenseDate ?? this.expenseDate,
      revenueDate: revenueDate ?? this.revenueDate,
      entryDate: entryDate ?? this.entryDate,
      createdByInfo: createdByInfo ?? this.createdByInfo,
    );
  }
}
