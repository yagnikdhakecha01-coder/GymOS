import 'package:flutter/material.dart';
import 'dart:math';
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

  void clearAllData() {
    _searchQuery = '';
    _selectedFilter = 'All';
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

    // Sort: Members with pending fees at the TOP (highest pending amount first), then by status
    filtered.sort((a, b) {
      final aPending = a.pendingAmount > 0;
      final bPending = b.pendingAmount > 0;
      if (aPending && !bPending) return -1;
      if (!aPending && bPending) return 1;
      if (aPending && bPending) {
        return b.pendingAmount.compareTo(a.pendingAmount);
      }
      // If both don't have pending, sort active first, then trial, then inactive
      if (a.status == 'Active' && b.status != 'Active') return -1;
      if (a.status != 'Active' && b.status == 'Active') return 1;
      return 0;
    });

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
      id: _generateUUIDv4(),
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
  Future<void> updateMember(Member member, {String paymentMethod = 'Cash', double? transactionAmount, bool isRenewal = false}) async {
    await _repository.saveMember(member);
    final txAmount = transactionAmount ?? member.totalReceivedAmount;
    if (txAmount > 0) {
      final tx = FinanceTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        title: '${member.name} - ${isRenewal ? 'Renewal Payment' : 'Initial Payment'}',
        amount: txAmount,
        type: 'Revenue',
        category: 'Membership',
        paymentMethod: paymentMethod,
        date: DateFormat('dd MMM yyyy').format(DateTime.now()),
        transactionDate: DateTime.now().toIso8601String(),
        notes: isRenewal ? 'Membership Renewal Payment' : 'Automatic Membership Initial Payment',
        referenceId: member.id,
      );
      await _repository.saveTransaction(tx);
    }
    notifyListeners();
  }

  Future<void> updateMemberPt({
    required String memberId,
    required bool ptMember,
    required String ptTrainerId,
    required double commissionPercentage,
  }) async {
    await _repository.updateMemberPtAssignment(
      memberId: memberId,
      ptMember: ptMember,
      ptTrainerId: ptTrainerId,
      commissionPercentage: commissionPercentage,
    );
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
        transactionDate: DateTime.now().toIso8601String(),
        notes: notes,
        referenceId: memberId,
      );
      await _repository.saveTransaction(tx);

      // Sync member_memberships.paid_amount to prevent DB trigger
      // from overwriting correct values on app restart
      await _repository.updateMemberMembershipPayment(
        memberId: memberId,
        paymentAmount: amount,
        newTotalReceived: newReceived,
        newPendingAmount: newPending,
      );
      
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
    final member = allMembers.cast<Member?>().firstWhere((m) => m?.id == memberId, orElse: () => null);
    final memberName = member?.name?.trim() ?? '';

    final results = _repository.getTransactions().where((tx) {
      // 1. Exclude all Gym Operational Expenses
      if (tx.type == 'Expense') return false;

      // 2. Direct ID match (referenceId or createdBy matching memberId)
      if (tx.referenceId == memberId || tx.createdBy == memberId) return true;

      // 3. Strict Name Match (Exact Title Prefix or Full Name Word Boundary)
      if (memberName.length >= 2) {
        final titleLower = tx.title.toLowerCase();
        final notesLower = tx.notes.toLowerCase();
        final nameLower = memberName.toLowerCase();

        // Title Prefix Match (e.g. "Rahul Sharma - Payment Received")
        if (titleLower.startsWith('$nameLower -') || 
            titleLower.startsWith('$nameLower :') ||
            titleLower == nameLower) {
          return true;
        }

        // Full Name Word-Boundary Match (e.g. "Rahul Sharma" as a whole phrase, not partial substrings)
        final namePattern = RegExp(r'\b' + RegExp.escape(nameLower) + r'\b');
        if (namePattern.hasMatch(titleLower) || namePattern.hasMatch(notesLower)) {
          return true;
        }
      }

      return false;
    }).toList();

    // Sort by transaction date descending (newest first)
    results.sort((a, b) {
      if (a.transactionDate.isNotEmpty && b.transactionDate.isNotEmpty) {
        return b.transactionDate.compareTo(a.transactionDate);
      }
      return 0;
    });

    return results;
  }

  Future<List<FinanceTransaction>> fetchMemberTransactionsFromBackend(String memberId) async {
    final remoteTx = await _repository.fetchMemberTransactionsFromBackend(memberId);
    if (remoteTx.isNotEmpty) {
      return remoteTx;
    }
    return getMemberTransactions(memberId);
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

  String _generateUUIDv4() {
    final rnd = Random.secure();
    final bytes = List.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final chars = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${chars[0]}${chars[1]}${chars[2]}${chars[3]}-'
        '${chars[4]}${chars[5]}-'
        '${chars[6]}${chars[7]}-'
        '${chars[8]}${chars[9]}-'
        '${chars[10]}${chars[11]}${chars[12]}${chars[13]}${chars[14]}${chars[15]}';
  }
}
