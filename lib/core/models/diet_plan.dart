class Meal {
  final String name; // Breakfast, Lunch, Snack, Dinner, etc.
  final String items;
  final String time;

  Meal({
    required this.name,
    required this.items,
    required this.time,
  });

  factory Meal.fromJson(Map<String, dynamic> json) {
    return Meal(
      name: json['name'] as String,
      items: json['items'] as String? ?? '',
      time: json['time'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'items': items,
      'time': time,
    };
  }
}

class DietPlan {
  final String id;
  final String title;
  final String goal; // Weight Loss, Weight Gain, Fitness, Muscle Gain, Maintenance
  final int calories;
  final List<Meal> meals;
  final String notes;
  final String status; // Active, Inactive

  DietPlan({
    required this.id,
    required this.title,
    required this.goal,
    required this.calories,
    required this.meals,
    required this.notes,
    this.status = 'Active',
  });

  factory DietPlan.fromJson(Map<String, dynamic> json) {
    var rawMeals = json['meals'] as List? ?? [];
    List<Meal> mealsList = rawMeals.map((e) => Meal.fromJson(e as Map<String, dynamic>)).toList();

    return DietPlan(
      id: json['id'] as String,
      title: json['title'] as String,
      goal: json['goal'] as String? ?? 'Fitness',
      calories: json['calories'] as int? ?? 2000,
      meals: mealsList,
      notes: json['notes'] as String? ?? '',
      status: json['status'] as String? ?? 'Active',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'goal': goal,
      'calories': calories,
      'meals': meals.map((m) => m.toJson()).toList(),
      'notes': notes,
      'status': status,
    };
  }

  DietPlan copyWith({
    String? id,
    String? title,
    String? goal,
    int? calories,
    List<Meal>? meals,
    String? notes,
    String? status,
  }) {
    return DietPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      goal: goal ?? this.goal,
      calories: calories ?? this.calories,
      meals: meals ?? this.meals,
      notes: notes ?? this.notes,
      status: status ?? this.status,
    );
  }
}
