import 'package:flutter/material.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/membership_plan.dart';
import '../../core/services/supabase_service.dart';

class MembershipViewModel extends ChangeNotifier {
  final GymRepository _repository;
  List<MembershipPlan> _plans = [];
  bool _isLoading = false;

  MembershipViewModel(this._repository) {
    loadPlans();
    _repository.addListener(loadPlans);
  }

  @override
  void dispose() {
    _repository.removeListener(loadPlans);
    super.dispose();
  }

  List<MembershipPlan> get plans => _plans.isEmpty ? _repository.getMemberships() : _plans;
  bool get isLoading => _isLoading;

  Future<void> loadPlans() async {
    _isLoading = true;
    notifyListeners();

    try {
      final gymInfo = _repository.storage.getGymInfo();
      final gymId = gymInfo?['id'];
      if (gymId != null && SupabaseService.isInitialized) {
        final response = await SupabaseService.client
            .from('membership_plans')
            .select()
            .eq('gym_id', gymId);

        final List list = response as List;
        _plans = list.map((e) => MembershipPlan.fromJson(e)).toList();
        _repository.updateMembershipsCache(_plans);
      } else {
        _plans = _repository.getMemberships();
      }
    } catch (e) {
      print('loadPlans database error: $e. Falling back to local cache.');
      _plans = _repository.getMemberships();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> savePlan(MembershipPlan plan) async {
    _isLoading = true;
    notifyListeners();

    try {
      final gymInfo = _repository.storage.getGymInfo();
      final gymId = gymInfo?['id'];
      if (gymId != null && SupabaseService.isInitialized) {
        final Map<String, dynamic> data = {
          'id': plan.id,
          'gym_id': gymId,
          'title': plan.title,
          'price': plan.price,
          'duration_months': plan.durationMonths,
          'duration_days': plan.durationDays,
          'pt_included': plan.ptIncluded,
          'diet_included': plan.dietIncluded,
          'workout_included': plan.workoutIncluded,
          'freeze_days': plan.freezeDays,
          'reminder_days': plan.reminderDays,
          'logo': plan.logo,
          'description': plan.description,
          'status': plan.status,
        };
        await SupabaseService.client.from('membership_plans').upsert(data);
      }
    } catch (e) {
      print('savePlan database error: $e. Saving locally only.');
    }

    await _repository.saveMembership(plan);
    await loadPlans();
  }

  Future<void> deletePlan(String id) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (SupabaseService.isInitialized) {
        await SupabaseService.client.from('membership_plans').delete().eq('id', id);
      }
    } catch (e) {
      print('deletePlan database error: $e.');
    }

    await _repository.deleteMembership(id);
    await loadPlans();
  }

  Future<void> duplicatePlan(MembershipPlan plan) async {
    final duplicated = plan.copyWith(
      id: 'm_plan_${DateTime.now().millisecondsSinceEpoch}',
      title: '${plan.title} (Copy)',
    );
    await savePlan(duplicated);
  }
}
