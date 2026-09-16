import 'dart:convert';

class ScheduledWorkout {
  final String title;
  final String description; // sets/reps or details

  ScheduledWorkout({required this.title, required this.description});

  factory ScheduledWorkout.fromJson(Map<String, dynamic> json) {
    return ScheduledWorkout(
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
    };
  }
}

class WorkoutPlan {
  final String id;
  final String title;
  final String goal; // Weight Loss, Weight Gain, Muscle Gain, Strength, Fat Loss, Fitness
  final String difficulty; // Beginner, Intermediate, Advanced
  final String description;
  final Map<String, List<ScheduledWorkout>> schedule; // Monday - Sunday

  WorkoutPlan({
    required this.id,
    required this.title,
    required this.goal,
    required this.difficulty,
    this.description = '',
    required this.schedule,
  });

  // Dynamic getters for compatibility with existing views
  int get durationWeeks => 4;
  int get exercisesCount {
    int count = 0;
    schedule.forEach((_, list) => count += list.length);
    return count;
  }
  
  List<ScheduledWorkout> get exercises {
    final List<ScheduledWorkout> list = [];
    schedule.forEach((_, value) => list.addAll(value));
    return list;
  }

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) {
    final Map<String, List<ScheduledWorkout>> parsedSchedule = {};
    dynamic rawSchedule = json['schedule'];
    if (rawSchedule is String && rawSchedule.isNotEmpty) {
      try {
        rawSchedule = jsonDecode(rawSchedule);
      } catch (_) {}
    }
    if (rawSchedule is Map) {
      rawSchedule.forEach((key, val) {
        if (val is List) {
          parsedSchedule[key.toString()] = val.map((e) {
            if (e is Map) {
              return ScheduledWorkout.fromJson(Map<String, dynamic>.from(e));
            }
            return ScheduledWorkout(title: e?.toString() ?? '', description: '');
          }).toList();
        }
      });
    }

    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    for (final day in days) {
      if (!parsedSchedule.containsKey(day)) {
        parsedSchedule[day] = [];
      }
    }

    // Fallback if old exercises format exists
    if (parsedSchedule.values.every((list) => list.isEmpty) && json['exercises'] is List) {
      final exercisesList = json['exercises'] as List;
      if (exercisesList.isNotEmpty) {
        parsedSchedule['Monday'] = exercisesList.take(2).map((e) => ScheduledWorkout(
          title: (e is Map ? e['name'] : null)?.toString() ?? 'Exercise',
          description: '${e is Map ? e['sets'] ?? 3 : 3} sets x ${e is Map ? e['reps'] ?? '12 reps' : '12 reps'}',
        )).toList();
        parsedSchedule['Wednesday'] = exercisesList.skip(2).take(2).map((e) => ScheduledWorkout(
          title: (e is Map ? e['name'] : null)?.toString() ?? 'Exercise',
          description: '${e is Map ? e['sets'] ?? 3 : 3} sets x ${e is Map ? e['reps'] ?? '12 reps' : '12 reps'}',
        )).toList();
      }
    }

    return WorkoutPlan(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      goal: (json['goal'] ?? 'Fitness').toString(),
      difficulty: (json['difficulty'] ?? 'Beginner').toString(),
      description: (json['description'] ?? '').toString(),
      schedule: parsedSchedule,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> scheduleJson = {};
    schedule.forEach((key, val) {
      scheduleJson[key] = val.map((e) => e.toJson()).toList();
    });

    return {
      'id': id,
      'title': title,
      'goal': goal,
      'difficulty': difficulty,
      'description': description,
      'schedule': scheduleJson,
    };
  }

  WorkoutPlan copyWith({
    String? id,
    String? title,
    String? goal,
    String? difficulty,
    String? description,
    Map<String, List<ScheduledWorkout>>? schedule,
  }) {
    return WorkoutPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      goal: goal ?? this.goal,
      difficulty: difficulty ?? this.difficulty,
      description: description ?? this.description,
      schedule: schedule ?? this.schedule,
    );
  }
}
