import 'package:flutter/material.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/diet_plan.dart';
import '../../core/services/supabase_service.dart';

class DietViewModel extends ChangeNotifier {
  final GymRepository _repository;

  String _searchQuery = '';
  String _selectedGoal = 'All';
  bool _isLoading = false;

  DietViewModel(this._repository) {
    _repository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _repository.removeListener(notifyListeners);
    super.dispose();
  }

  bool get isLoading => _isLoading;

  Future<void> fetchDiets() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _repository.fetchDietsFromSupabase();
    } catch (e) {
      print('DietViewModel fetchDiets error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void refresh() {
    fetchDiets();
  }

  String get searchQuery => _searchQuery;
  String get selectedGoal => _selectedGoal;

  List<DietPlan> get diets => _repository.getDiets();

  List<DietPlan> get filteredDiets {
    final query = _searchQuery.trim().toLowerCase();
    return _repository.getDiets().where((plan) {
      final matchesSearch = query.isEmpty ||
          plan.title.toLowerCase().contains(query) ||
          plan.goal.toLowerCase().contains(query);

      if (!matchesSearch) return false;

      if (_selectedGoal.isNotEmpty &&
          _selectedGoal.toLowerCase() != 'all' &&
          plan.goal.trim().toLowerCase() != _selectedGoal.trim().toLowerCase()) {
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

  Future<String?> saveDiet(DietPlan plan) async {
    final err = await _repository.saveDiet(plan);
    notifyListeners();
    return err;
  }

  Future<void> deleteDiet(String id) async {
    await _repository.deleteDiet(id);
    notifyListeners();
  }

  Future<void> duplicateDiet(DietPlan plan) async {
    final duplicated = plan.copyWith(
      id: SupabaseService.generateUuidV4(),
      title: '${plan.title} (Copy)',
    );
    await _repository.saveDiet(duplicated);
    notifyListeners();
  }
}
