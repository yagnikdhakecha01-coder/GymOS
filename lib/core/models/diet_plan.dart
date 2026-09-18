import 'dart:convert';

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
      name: json['name']?.toString() ?? '',
      items: json['items']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
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
  final int protein;
  final int carbs;
  final int fat;
  final List<Meal> meals;
  final String notes;
  final String status; // Active, Inactive

  DietPlan({
    required this.id,
    required this.title,
    required this.goal,
    required this.calories,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    required this.meals,
    required this.notes,
    this.status = 'Active',
  });

  factory DietPlan.fromJson(Map<String, dynamic> json) {
    List<Meal> mealsList = [];
    final rawMeals = json['meals'];
    if (rawMeals is List) {
      for (final item in rawMeals) {
        if (item is Map) {
          mealsList.add(Meal.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (rawMeals is String && rawMeals.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMeals);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              mealsList.add(Meal.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
      } catch (_) {}
    }

    final rawCalories = json['calories'] ?? json['calories_goal'];
    int parsedCalories = 2000;
    if (rawCalories is num) {
      parsedCalories = rawCalories.toInt();
    } else if (rawCalories != null) {
      parsedCalories = int.tryParse(rawCalories.toString()) ?? 2000;
    }

    int parseMacro(dynamic val) {
      if (val is num) return val.toInt();
      if (val != null) return int.tryParse(val.toString()) ?? 0;
      return 0;
    }

    final parsedProtein = parseMacro(json['protein'] ?? json['protein_goal']);
    final parsedCarbs = parseMacro(json['carbs'] ?? json['carbs_goal']);
    final parsedFat = parseMacro(json['fat'] ?? json['fat_goal']);

    return DietPlan(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      goal: json['goal']?.toString() ?? 'Fitness',
      calories: parsedCalories,
      protein: parsedProtein,
      carbs: parsedCarbs,
      fat: parsedFat,
      meals: mealsList,
      notes: (json['notes'] ?? json['description'])?.toString() ?? '',
      status: json['status']?.toString() ?? 'Active',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'goal': goal,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
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
    int? protein,
    int? carbs,
    int? fat,
    List<Meal>? meals,
    String? notes,
    String? status,
  }) {
    return DietPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      goal: goal ?? this.goal,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      meals: meals ?? this.meals,
      notes: notes ?? this.notes,
      status: status ?? this.status,
    );
  }
}
