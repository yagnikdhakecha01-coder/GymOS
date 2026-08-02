import 'package:flutter/material.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/gym_setup.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/services/supabase_service.dart';

class GymSettingsViewModel extends ChangeNotifier {
  final GymRepository _repository;
  final AuthViewModel _authViewModel;

  String _shiftMode = 'Single Shift';
  List<Map<String, dynamic>> _shifts = [];
  bool _loadingShifts = false;

  GymSettingsViewModel(this._repository, this._authViewModel) {
    _repository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _repository.removeListener(notifyListeners);
    super.dispose();
  }

  // --- Gym Info Access ---
  Map<String, dynamic> get gymInfo => _authViewModel.gymInfo ?? {
    'name': 'FitZone Gym',
    'logo': '',
    'address': '123 Main Road, City',
    'phone': '+91 98765 43210',
    'email': 'contact@fitzone.com',
    'timing': '06:00 AM - 10:00 PM',
    'weeklyOff': 'Sunday',
  };

  String get shiftMode => _shiftMode;
  List<Map<String, dynamic>> get shifts => _shifts;
  bool get loadingShifts => _loadingShifts;

  Future<void> loadOperatingHours(String gymId) async {
    _loadingShifts = true;
    notifyListeners();
    try {
      await _repository.fetchGymShiftSettingsFromSupabase(gymId);
    } catch (e) {
      print('Error loading operating hours from Supabase: $e');
    }
    _shiftMode = _repository.shiftMode;
    _shifts = _repository.shiftsList;
    _loadingShifts = false;
    notifyListeners();
  }

  Future<bool> saveOperatingHours(String gymId, String mode, List<Map<String, dynamic>> shiftsList) async {
    try {
      final success = await _repository.saveOperatingHoursOffline(gymId, mode, shiftsList);
      _shiftMode = mode;
      _shifts = shiftsList;
      notifyListeners();
      return success;
    } catch (e) {
      print('Error saving operating hours: $e');
      return false;
    }
  }

  void saveGymInfo({
    required String name,
    required String logo,
    required String address,
    required String phone,
    required String email,
    required String timing,
    required String weeklyOff,
  }) {
    final updated = Map<String, dynamic>.from(gymInfo);
    updated['name'] = name;
    updated['logo'] = logo;
    updated['address'] = address;
    updated['phone'] = phone;
    updated['email'] = email;
    updated['timing'] = timing;
    updated['weeklyOff'] = weeklyOff;

    _authViewModel.setGymInfo(updated);
    notifyListeners();
  }

  // --- Fitness Goals CRUD ---
  List<FitnessGoal> get goals => _repository.getGoals();

  Future<void> saveGoal(FitnessGoal goal) async {
    await _repository.saveGoal(goal);
    notifyListeners();
  }

  Future<void> deleteGoal(String id) async {
    await _repository.deleteGoal(id);
    notifyListeners();
  }

  // --- Custom Member Form CRUD ---
  List<CustomField> get customFields => _repository.getCustomFields();

  Future<void> saveCustomField(CustomField field) async {
    await _repository.saveCustomField(field);
    notifyListeners();
  }

  Future<void> deleteCustomField(String id) async {
    await _repository.deleteCustomField(id);
    notifyListeners();
  }
}
