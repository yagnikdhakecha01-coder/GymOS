class RecentActivity {
  final String id;
  final String gymId;
  final String activityType; // Payment, Advance, Leave, Membership, Expense
  final String title;
  final String description;
  final DateTime createdAt;

  RecentActivity({
    required this.id,
    required this.gymId,
    required this.activityType,
    required this.title,
    required this.description,
    required this.createdAt,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      id: json['id'] as String,
      gymId: json['gym_id'] as String,
      activityType: json['activity_type'] as String? ?? 'Other',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gym_id': gymId,
      'activity_type': activityType,
      'title': title,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
