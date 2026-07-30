import 'package:flutter/material.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/member.dart';
import '../../core/models/finance.dart';
import '../../core/models/membership_plan.dart';
import '../../core/models/workout_plan.dart';
import '../../core/models/diet_plan.dart';
import '../../core/models/attendance.dart';
import 'package:intl/intl.dart';

class MembersViewModel extends ChangeNotifier {
  final GymRepository _repository;

  String _searchQuery = '';
  String _selectedFilter = 'All'; // All, Active, Inactive, PT Only, Pending Payment

  MembersViewModel(this._repository) {
    fetchMembers();
    _repository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _repository.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> fetchMembers() async {
    await _repository.fetchMembersFromSupabase();
    await _repository.fetchTransactionsFromSupabase();
    notifyListeners();
  }

  // Getters
  String get searchQuery => _searchQuery;
  String get selectedFilter => _selectedFilter;

  List<Member> get allMembers => _repository.getMembers();

  // Filtered members list
  List<Member> get filteredMembers {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _repository.getMembers().where((member) {
      // Apply Search Query
      final matchesSearch = member.name.toLowerCase().contains(query) ||
          member.email.toLowerCase().contains(query) ||
          member.phone.contains(query);

      if (!matchesSearch) return false;

      // Apply Filter Category
      switch (_selectedFilter) {
        case 'Active':
          return member.status == 'Active';
        case 'Inactive':
          return member.status == 'Inactive';
        case 'Trial':
          return member.status == 'Trial';
        case 'PT Only':
          return member.ptMember == true;
        case 'Pending Payment':
          return member.pendingAmount > 0;
        default:
          return true;
      }
    }).toList();

    if (_selectedFilter == 'All') {
      // Sort: Active first, then Trial, then Inactive / other statuses
      final activeList = filtered.where((m) => m.status == 'Active').toList();
      final trialList = filtered.where((m) => m.status == 'Trial').toList();
      final inactiveList = filtered.where((m) => m.status != 'Active' && m.status != 'Trial').toList();
      return [...activeList, ...trialList, ...inactiveList];
    }

    return filtered;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilter(String filter) {
    _selectedFilter = filter;
    notifyListeners();
  }

  // Create
  Future<void> addMember({
    required String name,
    required String email,
    required String phone,
    required String joinDate,
    required String membershipPlanId,
    required bool ptMember,
    String ptTrainer = '',
    String medicalDetails = 'None',
    String notes = '',
    double pendingAmount = 0.0,
  }) async {
    final newMember = Member(
      id: 'mem_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      phone: phone,
      avatar: '',
      joinDate: joinDate.isNotEmpty ? joinDate : DateFormat('dd MMM yyyy').format(DateTime.now()),
      status: 'Active',
      membershipPlanId: membershipPlanId,
      ptMember: ptMember,
      ptTrainer: ptTrainer,
      assignedWorkoutId: '',
      assignedDietId: '',
      medicalDetails: medicalDetails,
      notes: notes,
      pendingAmount: pendingAmount,
    );

    await _repository.saveMember(newMember);
    notifyListeners();
  }

  // Update
  Future<void> updateMember(Member member, {String paymentMethod = 'Cash'}) async {
    await _repository.saveMember(member);
    if (member.totalReceivedAmount > 0) {
      final tx = FinanceTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        title: '${member.name} - Initial Payment',
        amount: member.totalReceivedAmount,
        type: 'Revenue',
        category: 'Membership',
        paymentMethod: paymentMethod,
        date: DateFormat('dd MMM yyyy').format(DateTime.now()),
        notes: 'Automatic Membership Initial Payment',
        referenceId: member.id,
      );
      await _repository.saveTransaction(tx);
    }
    notifyListeners();
  }

  // Delete
  Future<void> deleteMember(String id) async {
    await _repository.deleteMember(id);
    notifyListeners();
  }

  // Assign plans
  Future<void> assignWorkout(String memberId, String workoutId) async {
    final memberIndex = allMembers.indexWhere((m) => m.id == memberId);
    if (memberIndex >= 0) {
      final updated = allMembers[memberIndex].copyWith(assignedWorkoutId: workoutId);
      await _repository.saveMember(updated);
      notifyListeners();
    }
  }

  Future<void> assignDiet(String memberId, String dietId) async {
    final memberIndex = allMembers.indexWhere((m) => m.id == memberId);
    if (memberIndex >= 0) {
      final updated = allMembers[memberIndex].copyWith(assignedDietId: dietId);
      await _repository.saveMember(updated);
      notifyListeners();
    }
  }

  // Record Payment
  Future<void> recordPayment({
    required String memberId,
    required double amount,
    required String paymentMethod,
    required String category,
    required String notes,
  }) async {
    final memberIndex = allMembers.indexWhere((m) => m.id == memberId);
    if (memberIndex >= 0) {
      final member = allMembers[memberIndex];
      double currentPending = member.pendingAmount;
      double newPending = (currentPending - amount).clamp(0.0, double.infinity);
      double newReceived = member.totalReceivedAmount + amount;
      String newStatus = newPending <= 0 ? 'Paid' : 'Partial';

      final updated = member.copyWith(
        pendingAmount: newPending,
        totalReceivedAmount: newReceived,
        paymentStatus: newStatus,
      );
      await _repository.saveMember(updated);

      // Save finance transaction record
      final tx = FinanceTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        title: '${member.name} - Payment Received',
        amount: amount,
        type: 'Revenue',
        category: category,
        paymentMethod: paymentMethod,
        date: DateFormat('dd MMM yyyy').format(DateTime.now()),
        notes: notes,
        referenceId: memberId,
      );
      await _repository.saveTransaction(tx);
      
      notifyListeners();
    }
  }

  MembershipPlan? getMemberPlan(String planId) {
    try {
      return _repository.getMemberships().firstWhere((e) => e.id == planId);
    } catch (_) {
      return null;
    }
  }

  List<FinanceTransaction> getMemberTransactions(String memberId) {
    return _repository.getTransactions()
        .where((tx) => tx.referenceId == memberId)
        .toList();
  }

  List<AttendanceRecord> getMemberAttendance(String memberId) {
    return _repository.getAttendance()
        .where((r) => r.userId == memberId && r.userType == 'Member')
        .toList();
  }

  WorkoutPlan? getMemberWorkout(String workoutId) {
    try {
      return _repository.getWorkouts().firstWhere((e) => e.id == workoutId);
    } catch (_) {
      return null;
    }
  }

  DietPlan? getMemberDiet(String dietId) {
    try {
      return _repository.getDiets().firstWhere((e) => e.id == dietId);
    } catch (_) {
      return null;
    }
  }

  // --- Invitations & Activation System ---
  Future<Map<String, dynamic>?> getLatestInvitation(String id) => _repository.getLatestInvitation(id, false);

  Future<String> generateInvitation({required String recordId, required String name, required String phone}) async {
    final code = await _repository.generateInvitation(recordId: recordId, name: name, phone: phone, isStaff: false);
    notifyListeners();
    return code;
  }

  Future<String> unlinkAccount(String recordId) async {
    final code = await _repository.unlinkAccount(recordId, false);
    notifyListeners();
    return code;
  }
}
