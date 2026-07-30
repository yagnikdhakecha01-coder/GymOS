import 'package:flutter/material.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/diet_plan.dart';

class DietViewModel extends ChangeNotifier {
  final GymRepository _repository;

  String _searchQuery = '';
  String _selectedGoal = 'All';

  DietViewModel(this._repository);

  void refresh() {
    notifyListeners();
  }

  String get searchQuery => _searchQuery;
  String get selectedGoal => _selectedGoal;

  List<DietPlan> get diets => _repository.getDiets();

  List<DietPlan> get filteredDiets {
    final query = _searchQuery.trim().toLowerCase();
    return _repository.getDiets().where((plan) {
      final matchesSearch = plan.title.toLowerCase().contains(query) ||
          plan.goal.toLowerCase().contains(query);

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

  Future<void> saveDiet(DietPlan plan) async {
    await _repository.saveDiet(plan);
    notifyListeners();
  }

  Future<void> deleteDiet(String id) async {
    await _repository.deleteDiet(id);
    notifyListeners();
  }

  Future<void> duplicateDiet(DietPlan plan) async {
    final duplicated = plan.copyWith(
      id: 'd_${DateTime.now().millisecondsSinceEpoch}',
      title: '${plan.title} (Copy)',
    );
    await _repository.saveDiet(duplicated);
    notifyListeners();
  }
}
