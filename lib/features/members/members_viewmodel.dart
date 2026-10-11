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

enum MemberSortOption {
  pendingFeesFirst, // Default: Jiska jitna baki hai vo top me ate hai
  expiringSoon,     // Expired & expiring soonest on top
  recentlyJoined,   // Newest members first
  alphabetical,     // A to Z
}

class MembersViewModel extends ChangeNotifier {
  final GymRepository _repository;

  String _searchQuery = '';
  String _selectedFilter = 'All'; // All, Active, Inactive, Trial, PT Only, Pending Payment
  MemberSortOption _sortOption = MemberSortOption.pendingFeesFirst;

  List<Member>? _cachedFilteredMembers;

  int _cachedActiveCount = 0;
  int _cachedInactiveCount = 0;
  double _cachedTotalPending = 0.0;
  bool _countsDirty = true;

  MembersViewModel(this._repository) {
    fetchMembers();
    _repository.addListener(_onRepositoryChanged);
  }

  void _onRepositoryChanged() {
    _cachedFilteredMembers = null;
    _countsDirty = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _repository.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  Future<void> fetchMembers() async {
    await _repository.fetchMembersFromSupabase();
    await _repository.fetchTransactionsFromSupabase();
    _cachedFilteredMembers = null;
    _countsDirty = true;
    notifyListeners();
  }

  Future<void> saveMember(Member member) async {
    await _repository.saveMember(member);
    await fetchMembers();
  }

  void clearAllData() {
    _searchQuery = '';
    _selectedFilter = 'All';
    _sortOption = MemberSortOption.pendingFeesFirst;
    _cachedFilteredMembers = null;
    _countsDirty = true;
    notifyListeners();
  }

  // Getters
  String get searchQuery => _searchQuery;
  String get selectedFilter => _selectedFilter;
  MemberSortOption get sortOption => _sortOption;

  List<Member> get allMembers => _repository.getMembers();

  void _recomputeCountsIfNeeded() {
    if (!_countsDirty) return;
    int active = 0;
    int inactive = 0;
    double pending = 0.0;
    for (final m in allMembers) {
      if (m.status == 'Active') {
        active++;
      } else if (m.status == 'Inactive') {
        inactive++;
      }
      if (m.pendingAmount > 0) {
        pending += m.pendingAmount;
      }
    }
    _cachedActiveCount = active;
    _cachedInactiveCount = inactive;
    _cachedTotalPending = pending;
    _countsDirty = false;
  }

  int get activeMembersCount {
    _recomputeCountsIfNeeded();
    return _cachedActiveCount;
  }

  int get inactiveMembersCount {
    _recomputeCountsIfNeeded();
    return _cachedInactiveCount;
  }

  double get totalPendingAmount {
    _recomputeCountsIfNeeded();
    return _cachedTotalPending;
  }

  // Fast memoized filtered members list
  List<Member> get filteredMembers {
    if (_cachedFilteredMembers != null) {
      return _cachedFilteredMembers!;
    }
    _cachedFilteredMembers = _computeFilteredMembers();
    return _cachedFilteredMembers!;
  }

  List<Member> _computeFilteredMembers() {
    final query = _searchQuery.trim().toLowerCase();
    final list = _repository.getMembers().where((member) {
      // 1. Search Query Match
      if (query.isNotEmpty) {
        final matches = member.name.toLowerCase().contains(query) ||
            member.email.toLowerCase().contains(query) ||
            member.phone.contains(query);
        if (!matches) return false;
      }

      // 2. Filter Category Match
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

    // 3. Dynamic Sort based on selected sortOption
    switch (_sortOption) {
      case MemberSortOption.pendingFeesFirst:
        // Highest pending amount first, then active status, then name
        list.sort((a, b) {
          final aPending = a.pendingAmount > 0;
          final bPending = b.pendingAmount > 0;
          if (aPending && !bPending) return -1;
          if (!aPending && bPending) return 1;
          if (aPending && bPending) {
            final cmp = b.pendingAmount.compareTo(a.pendingAmount);
            if (cmp != 0) return cmp;
          }
          if (a.status == 'Active' && b.status != 'Active') return -1;
          if (a.status != 'Active' && b.status == 'Active') return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;

      case MemberSortOption.expiringSoon:
        // Expired members first, then closest upcoming expiry dates, then members without expiry
        list.sort((a, b) {
          final aExp = a.parsedExpiryDate;
          final bExp = b.parsedExpiryDate;
          if (aExp != null && bExp == null) return -1;
          if (aExp == null && bExp != null) return 1;
          if (aExp == null && bExp == null) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final aIsExpired = aExp!.isBefore(today);
          final bIsExpired = bExp!.isBefore(today);

          // Both expired -> most recently expired first
          if (aIsExpired && bIsExpired) {
            return bExp.compareTo(aExp);
          }
          // Expired comes before non-expired
          if (aIsExpired && !bIsExpired) return -1;
          if (!aIsExpired && bIsExpired) return 1;

          // Both active -> closest expiry date first
          return aExp.compareTo(bExp);
        });
        break;

      case MemberSortOption.recentlyJoined:
        // Newest join date / created_at first
        list.sort((a, b) {
          final aJoin = a.parsedJoinDate ?? (a.createdAt != null ? DateTime.tryParse(a.createdAt!) : null);
          final bJoin = b.parsedJoinDate ?? (b.createdAt != null ? DateTime.tryParse(b.createdAt!) : null);
          if (aJoin != null && bJoin == null) return -1;
          if (aJoin == null && bJoin != null) return 1;
          if (aJoin != null && bJoin != null) {
            final cmp = bJoin.compareTo(aJoin);
            if (cmp != 0) return cmp;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;

      case MemberSortOption.alphabetical:
        // Name A to Z
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }

    return list;
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _cachedFilteredMembers = null;
    notifyListeners();
  }

  void setFilter(String filter) {
    if (_selectedFilter == filter) return;
    _selectedFilter = filter;
    _cachedFilteredMembers = null;
    notifyListeners();
  }

  void setSortOption(MemberSortOption option) {
    if (_sortOption == option) return;
    _sortOption = option;
    _cachedFilteredMembers = null;
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
    String goal = 'General Fitness',
    String assignedWorkoutId = '',
    String assignedDietId = '',
    Map<String, dynamic>? extraFields,
  }) async {
    final extra = Map<String, dynamic>.from(extraFields ?? {});
    extra['goal'] = goal;

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
      assignedWorkoutId: assignedWorkoutId,
      assignedDietId: assignedDietId,
      medicalDetails: medicalDetails,
      notes: notes,
      pendingAmount: pendingAmount,
      extraFields: extra,
    );

    await _repository.saveMember(newMember);

    // Guaranteed automatic invitation code creation on member create
    try {
      await generateInvitation(
        recordId: newMember.id,
        name: newMember.name,
        phone: newMember.phone,
      );
    } catch (e) {
      debugPrint('Auto invitation generation notice: $e');
    }

    notifyListeners();
  }

  /// Update member profile details (avatar, name, phone, notes, measurements, etc.)
  /// directly without creating any financial transactions.
  Future<void> updateMemberProfile(Member member) => saveMember(member);

  /// Atomically update member's fitness goal, workout plan, and diet plan
  Future<void> updateMemberGoalAndPlans(
    String memberId, {
    required String goal,
    String? workoutId,
    String? dietId,
  }) async {
    final member = allMembers.firstWhere((m) => m.id == memberId);
    final updatedExtra = Map<String, dynamic>.from(member.extraFields);
    updatedExtra['goal'] = goal;

    final updated = member.copyWith(
      assignedWorkoutId: workoutId ?? member.assignedWorkoutId,
      assignedDietId: dietId ?? member.assignedDietId,
      extraFields: updatedExtra,
    );

    await saveMember(updated);
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

  /// Save an old/imported member with historical finance recording.
  /// The transaction uses the past receive date so it does NOT affect
  /// current month's revenue, while ensuring the member's payment and
  /// received amounts are fully tracked in the database and member card.
  Future<void> saveOldMember(
    Member member, {
    String paymentMethod = 'Cash',
    DateTime? paymentReceiveDate,
  }) async {
    await _repository.saveOldMember(member);

    final txAmount = member.totalReceivedAmount;
    if (txAmount > 0) {
      final historicalDate = paymentReceiveDate ??
          (member.joinDate.isNotEmpty ? (DateFormat('dd MMM yyyy').tryParse(member.joinDate) ?? DateTime.now()) : DateTime.now());

      final tx = FinanceTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        title: '${member.name} - Initial Payment (Old Record)',
        amount: txAmount,
        type: 'Revenue',
        category: 'Membership',
        paymentMethod: paymentMethod,
        date: DateFormat('dd MMM yyyy').format(historicalDate),
        transactionDate: historicalDate.toIso8601String(),
        revenueDate: historicalDate.toIso8601String(),
        entryDate: historicalDate.toIso8601String(),
        notes: 'Old Member Import - Payment received on ${DateFormat('dd MMM yyyy').format(historicalDate)}',
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
  Future<void> deleteMember(String id, {String deleteScope = 'profile_only'}) async {
    await _repository.deleteMember(id, deleteScope: deleteScope);
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
    final memberName = member?.name.trim() ?? '';

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

  Future<String> generateInvitation({required String recordId, required String name, required String phone, bool forceRegenerate = false}) async {
    final code = await _repository.generateInvitation(recordId: recordId, name: name, phone: phone, isStaff: false, forceRegenerate: forceRegenerate);
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
