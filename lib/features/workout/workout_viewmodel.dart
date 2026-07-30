import 'package:flutter/material.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/workout_plan.dart';
import '../../core/services/supabase_service.dart';

class WorkoutViewModel extends ChangeNotifier {
  final GymRepository _repository;

  String _searchQuery = '';
  String _selectedGoal = 'All';

  WorkoutViewModel(this._repository) {
    _repository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _repository.removeListener(notifyListeners);
    super.dispose();
  }

  void refresh() {
    notifyListeners();
  }

  String get searchQuery => _searchQuery;
  String get selectedGoal => _selectedGoal;

  List<WorkoutPlan> get workouts => _repository.getWorkouts();

  List<WorkoutPlan> get filteredWorkouts {
    final query = _searchQuery.trim().toLowerCase();
    return _repository.getWorkouts().where((plan) {
      final matchesSearch = plan.title.toLowerCase().contains(query) ||
          plan.goal.toLowerCase().contains(query) ||
          plan.difficulty.toLowerCase().contains(query);

      if (!matchesSearch) return false;

      if (_selectedGoal != 'All' && plan.goal != _selectedGoal) {
        return false;
      }
      return true;
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setGoalFilter(String goal) {
    _selectedGoal = goal;
    notifyListeners();
  }

  Future<String?> saveWorkout(WorkoutPlan plan) async {
    final error = await _repository.saveWorkout(plan);
    notifyListeners();
    return error;
  }

  Future<void> deleteWorkout(String id) async {
    await _repository.deleteWorkout(id);
    notifyListeners();
  }

  Future<void> duplicateWorkout(WorkoutPlan plan) async {
    final duplicated = plan.copyWith(
      id: SupabaseService.generateUuidV4(),
      title: '${plan.title} (Copy)',
    );
    await _repository.saveWorkout(duplicated);
    notifyListeners();
  }
}
