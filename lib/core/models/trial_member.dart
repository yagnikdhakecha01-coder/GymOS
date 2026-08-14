import 'package:intl/intl.dart';

class TrialMember {
  final String id;
  final String gymId;
  final String name;
  final String phone;
  final String avatar;
  final String trialType; // 'Free', 'Paid'
  final int trialDays;
  final String startDate; // yyyy-MM-dd
  final String endDate; // yyyy-MM-dd
  final String status; // 'Active', 'Expired', 'Converted'
  final double fee;
  final double discount;
  final double receivedAmount;
  final String? paymentMethod;
  final String? paymentDate; // yyyy-MM-dd
  final String createdAt; // ISO String

  TrialMember({
    required this.id,
    required this.gymId,
    required this.name,
    required this.phone,
    required this.avatar,
    required this.trialType,
    required this.trialDays,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.fee,
    required this.discount,
    required this.receivedAmount,
    this.paymentMethod,
    this.paymentDate,
    required this.createdAt,
  });

  double get finalAmount => (fee - discount).clamp(0.0, double.infinity);
  double get remainingAmount => (finalAmount - receivedAmount).clamp(0.0, double.infinity);

  int get daysUntilExpiry {
    try {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final end = DateTime.parse(endDate);
      final endDateOnly = DateTime(end.year, end.month, end.day);
      return endDateOnly.difference(todayDate).inDays;
    } catch (_) {
      return 999;
    }
  }

  bool get isExpiringTodayOrExpired {
    if (status == 'Converted') return false;
    return daysUntilExpiry <= 0;
  }

  String get calculatedStatus {
    if (status == 'Converted') return 'Converted';
    
    try {
      if (isExpiringTodayOrExpired) {
        return 'Expired';
      }
    } catch (_) {
      // Fallback if parsing fails
    }
    return 'Active';
  }

  factory TrialMember.fromJson(Map<String, dynamic> json) {
    return TrialMember(
      id: json['id'] as String,
      gymId: json['gym_id'] as String? ?? '',
      name: json['name'] as String,
      phone: json['phone'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      trialType: json['trial_type'] as String? ?? 'Free',
      trialDays: json['trial_days'] as int? ?? 0,
      startDate: json['start_date'] as String? ?? '',
      endDate: json['end_date'] as String? ?? '',
      status: json['status'] as String? ?? 'Active',
      fee: (json['fee'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      receivedAmount: (json['received_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['payment_method'] as String?,
      paymentDate: json['payment_date'] as String?,
      createdAt: json['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gym_id': gymId,
      'name': name,
      'phone': phone,
      'avatar': avatar,
      'trial_type': trialType,
      'trial_days': trialDays,
      'start_date': startDate,
      'end_date': endDate,
      'status': status,
      'fee': fee,
      'discount': discount,
      'received_amount': receivedAmount,
      'payment_method': paymentMethod,
      'payment_date': paymentDate,
      'created_at': createdAt,
    };
  }

  TrialMember copyWith({
    String? id,
    String? gymId,
    String? name,
    String? phone,
    String? avatar,
    String? trialType,
    int? trialDays,
    String? startDate,
    String? endDate,
    String? status,
    double? fee,
    double? discount,
    double? receivedAmount,
    String? paymentMethod,
    String? paymentDate,
    String? createdAt,
  }) {
    return TrialMember(
      id: id ?? this.id,
      gymId: gymId ?? this.gymId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      avatar: avatar ?? this.avatar,
      trialType: trialType ?? this.trialType,
      trialDays: trialDays ?? this.trialDays,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      fee: fee ?? this.fee,
      discount: discount ?? this.discount,
      receivedAmount: receivedAmount ?? this.receivedAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentDate: paymentDate ?? this.paymentDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
