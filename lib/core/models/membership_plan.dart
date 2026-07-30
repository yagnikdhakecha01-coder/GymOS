class MembershipPlan {
  final String id;
  final String title;
  final double price;
  final int durationMonths;
  final int durationDays; // precise duration in days
  final bool ptIncluded;
  final bool dietIncluded;
  final bool workoutIncluded;
  final int freezeDays;
  final int reminderDays;
  final String logo;
  final String description;
  final String status; // Active, Inactive

  MembershipPlan({
    required this.id,
    required this.title,
    required this.price,
    required this.durationMonths,
    required this.durationDays,
    required this.ptIncluded,
    required this.dietIncluded,
    required this.workoutIncluded,
    required this.freezeDays,
    required this.reminderDays,
    this.logo = '🎟️',
    this.description = '',
    this.status = 'Active',
  });

  factory MembershipPlan.fromJson(Map<String, dynamic> json) {
    final days = json['duration_days'] as int? ?? json['durationDays'] as int? ?? (json['duration_months'] as int? ?? json['durationMonths'] as int? ?? 1) * 30;
    return MembershipPlan(
      id: json['id'] as String,
      title: json['title'] as String,
      price: (json['price'] as num).toDouble(),
      durationMonths: json['duration_months'] as int? ?? json['durationMonths'] as int? ?? (days ~/ 30),
      durationDays: days,
      ptIncluded: json['pt_included'] as bool? ?? json['ptIncluded'] as bool? ?? false,
      dietIncluded: json['diet_included'] as bool? ?? json['dietIncluded'] as bool? ?? false,
      workoutIncluded: json['workout_included'] as bool? ?? json['workoutIncluded'] as bool? ?? false,
      freezeDays: json['freeze_days'] as int? ?? json['freezeDays'] as int? ?? 0,
      reminderDays: json['reminder_days'] as int? ?? json['reminderDays'] as int? ?? 5,
      logo: json['logo'] as String? ?? '🎟️',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'Active',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'price': price,
      'durationMonths': durationMonths,
      'durationDays': durationDays,
      'ptIncluded': ptIncluded,
      'dietIncluded': dietIncluded,
      'workoutIncluded': workoutIncluded,
      'freezeDays': freezeDays,
      'reminderDays': reminderDays,
      'logo': logo,
      'description': description,
      'status': status,
    };
  }

  MembershipPlan copyWith({
    String? id,
    String? title,
    double? price,
    int? durationMonths,
    int? durationDays,
    bool? ptIncluded,
    bool? dietIncluded,
    bool? workoutIncluded,
    int? freezeDays,
    int? reminderDays,
    String? logo,
    String? description,
    String? status,
  }) {
    return MembershipPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      price: price ?? this.price,
      durationMonths: durationMonths ?? this.durationMonths,
      durationDays: durationDays ?? this.durationDays,
      ptIncluded: ptIncluded ?? this.ptIncluded,
      dietIncluded: dietIncluded ?? this.dietIncluded,
      workoutIncluded: workoutIncluded ?? this.workoutIncluded,
      freezeDays: freezeDays ?? this.freezeDays,
      reminderDays: reminderDays ?? this.reminderDays,
      logo: logo ?? this.logo,
      description: description ?? this.description,
      status: status ?? this.status,
    );
  }
}
