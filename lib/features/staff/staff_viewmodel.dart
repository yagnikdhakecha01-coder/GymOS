import 'package:flutter/material.dart';
import 'dart:math';
import '../../core/repository/gym_repository.dart';
import '../../core/models/staff.dart';
import '../../core/models/finance.dart';
import '../../core/models/attendance.dart';
import '../../core/models/salary_draft.dart';
import '../../core/models/salary_adjustment.dart';
import '../../core/services/supabase_service.dart';
import 'package:intl/intl.dart';

class StaffViewModel extends ChangeNotifier {
  final GymRepository _repository;

  String _searchQuery = '';
  String _selectedFilter = 'All'; // All, Active, On Leave, Trainer, Admin
  
  // Track salary payment states by month (e.g. {"January 2026": {"staff_uuid_1"}})
  final Map<String, Set<String>> _paidStaffByMonth = {};

  StaffViewModel(this._repository) {
    fetchStaff();
    _repository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _repository.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> fetchStaff() async {
    await _repository.fetchStaffFromSupabase();
    notifyListeners();
  }

  void clearAllData() {
    _searchQuery = '';
    _selectedFilter = 'All';
    _paidStaffByMonth.clear();
    _draftsByMonth.clear();
    _payableByStaff.clear();
    _payableCacheMonth = '';
    notifyListeners();
  }

  // Getters
  String get searchQuery => _searchQuery;
  String get selectedFilter => _selectedFilter;

  List<Staff> get allStaff => _repository.getStaff();

  List<Staff> get filteredStaff {
    final query = _searchQuery.trim().toLowerCase();
    return _repository.getStaff().where((staff) {
      final matchesSearch = staff.name.toLowerCase().contains(query) ||
          staff.email.toLowerCase().contains(query) ||
          staff.phone.contains(query) ||
          staff.role.toLowerCase().contains(query);

      if (!matchesSearch) return false;

      switch (_selectedFilter) {
        case 'Active':
          return staff.status == 'Active';
        case 'On Leave':
          return staff.status == 'On Leave';
        case 'Trainer':
          return staff.role == 'Trainer';
        case 'Admin':
          return staff.role == 'Receptionist' || staff.role == 'Accountant' || staff.role == 'Manager';
        default:
          return true;
      }
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilter(String filter) {
    _selectedFilter = filter;
    notifyListeners();
  }

  String _generateUUIDv4() {
    final random = Random.secure();
    const chars = '0123456789abcdef';
    String hexStr(int length) {
      return List.generate(length, (index) => chars[random.nextInt(16)]).join();
    }
    final y = ['8', '9', 'a', 'b'][random.nextInt(4)];
    return '${hexStr(8)}-${hexStr(4)}-4${hexStr(3)}-$y${hexStr(3)}-${hexStr(12)}';
  }

  // Create
  Future<void> addStaff({
    required String name,
    required String email,
    required String phone,
    required String role,
    required String department,
    required String shift,
    required double salary,
    String experience = 'N/A',
  }) async {
    final newStaff = Staff(
      id: _generateUUIDv4(),
      name: name,
      email: email,
      phone: phone,
      role: role,
      department: department,
      status: 'Active',
      joinDate: DateFormat('dd MMM yyyy').format(DateTime.now()),
      shift: shift,
      experience: experience,
      rating: 5.0,
      sessionsCount: 0,
      membersTrained: 0,
      salary: salary,
      salaryDue: salary, // Initial salary due
      avatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200',
    );

    await _repository.saveStaff(newStaff);
    notifyListeners();
  }

  // Update
  Future<void> updateStaff(Staff staff) async {
    await _repository.saveStaff(staff);
    notifyListeners();
  }

  Future<void> saveStaff(Staff staff) => updateStaff(staff);

  // Delete
  Future<void> deleteStaff(String id) async {
    await _repository.deleteStaff(id);
    notifyListeners();
  }

  // Pay Salary
  Future<void> paySalary(String staffId, double amount, String notes) async {
    final index = allStaff.indexWhere((s) => s.id == staffId);
    if (index >= 0) {
      final staff = allStaff[index];
      double currentDue = staff.salaryDue;
      double newDue = (currentDue - amount).clamp(0.0, double.infinity);

      final updated = staff.copyWith(salaryDue: newDue);
      await _repository.saveStaff(updated);

      // Create salary transaction
      final tx = FinanceTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        title: '${staff.name} - Salary Paid',
        amount: amount,
        type: 'Expense',
        category: 'Salary',
        date: DateFormat('dd MMM yyyy').format(DateTime.now()),
        transactionDate: DateTime.now().toIso8601String(),
        notes: notes,
      );
      await _repository.saveTransaction(tx);
      
      notifyListeners();
    }
  }

  bool isSalaryPaid(String staffId, String month) {
    if (_paidStaffByMonth[month]?.contains(staffId) ?? false) return true;
    final normalizedMonth = month.trim().toLowerCase();
    
    // 1. Check repository salary drafts
    final hasPaidDraft = _repository.salaryDrafts.any((d) {
      final sId = d['staff_id']?.toString() ?? '';
      final sMonth = (d['salary_month'] ?? '').toString().trim().toLowerCase();
      final status = (d['status'] ?? '').toString().trim().toLowerCase();
      return sId == staffId && (sMonth == normalizedMonth || sMonth.contains(normalizedMonth.split(' ').first)) && (status == 'paid' || d['paid_transaction_id'] != null);
    });
    if (hasPaidDraft) return true;

    // 2. Check repository finance transactions matching staff name in title
    final staff = allStaff.cast<Staff?>().firstWhere((s) => s?.id == staffId, orElse: () => null);
    final staffName = staff?.name.trim().toLowerCase() ?? '';
    if (staffName.isNotEmpty) {
      final hasSalaryTx = _repository.getTransactions().any((tx) {
        final cat = tx.category.toLowerCase();
        final title = tx.title.toLowerCase();
        final isSalary = cat.contains('salary') || title.contains('salary');
        final matchesStaff = title.contains(staffName);
        final dateStr = tx.date.toLowerCase();
        final txDateStr = tx.transactionDate.toLowerCase();
        final matchesMonth = dateStr.contains(normalizedMonth) || txDateStr.contains(normalizedMonth) ||
            (dateStr.isNotEmpty && normalizedMonth.contains(dateStr.split(' ').last));
        return isSalary && matchesStaff && matchesMonth;
      });
      if (hasSalaryTx) return true;
    }

    return false;
  }

  void markSalaryAsPaid(String staffId, String month) {
    _paidStaffByMonth.putIfAbsent(month, () => {}).add(staffId);
    _payableByStaff[staffId] = 0.0;
    notifyListeners();
  }

  final Map<String, List<Map<String, dynamic>>> _draftsByMonth = {};
  final Map<String, double> _payableByStaff = {};
  String _payableCacheMonth = '';

  List<Map<String, dynamic>> getDraftsForMonth(String month) {
    return _draftsByMonth[month] ?? [];
  }

  Future<void> fetchSalaryDraftsForMonth(String month) async {
    if (!SupabaseService.isInitialized) return;
    try {
      final List response = await SupabaseService.client
          .from('salary_drafts')
          .select()
          .ilike('salary_month', month.trim());
      
      _draftsByMonth[month] = List<Map<String, dynamic>>.from(response);
      notifyListeners();
    } catch (e) {
      print('fetchSalaryDraftsForMonth error: $e');
    }
  }

  Future<void> fetchPaidSalariesForMonth(String month) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await fetchSalaryDraftsForMonth(month); // Pre-fetch drafts to get correct amounts
      
      final List response = await SupabaseService.client
          .from('salary_drafts')
          .select('staff_id, status')
          .ilike('salary_month', month.trim());
      
      final Set<String> paidSet = {};
      for (final item in response) {
        final status = (item['status'] ?? '').toString().toLowerCase();
        if (status == 'paid') {
          paidSet.add(item['staff_id'].toString());
        }
      }

      // Also include any staff marked paid locally or in local drafts
      for (final d in _repository.salaryDrafts) {
        final sMonth = (d['salary_month'] ?? '').toString().trim().toLowerCase();
        final status = (d['status'] ?? '').toString().trim().toLowerCase();
        if (sMonth == month.trim().toLowerCase() && status == 'paid') {
          paidSet.add(d['staff_id'].toString());
        }
      }

      _paidStaffByMonth[month] = paidSet;
      notifyListeners();
    } catch (e) {
      print('fetchPaidSalariesForMonth error: $e');
    }
  }

  /// Checks if staff was employed during or before the given month.
  /// If an employee joined in month 9 (e.g. September), they must NOT be visible
  /// or payable in salary tabs for month 8 (e.g. August) or earlier.
  bool isStaffEmployedInMonth(Staff staff, String monthStr) {
    if (staff.joinDate.trim().isEmpty) return true;

    DateTime? salaryMonthDate;
    try {
      salaryMonthDate = DateFormat('MMMM yyyy').parse(monthStr.trim());
    } catch (_) {
      try {
        salaryMonthDate = DateFormat('MMM yyyy').parse(monthStr.trim());
      } catch (_) {
        return true;
      }
    }

    DateTime? joinDate;
    final rawJoin = staff.joinDate.trim();
    final formats = [
      'dd MMM yyyy',
      'd MMM yyyy',
      'yyyy-MM-dd',
      'dd-MM-yyyy',
      'dd/MM/yyyy',
      'MMMM yyyy',
      'MMM yyyy',
    ];

    for (final fmt in formats) {
      try {
        joinDate = DateFormat(fmt).parse(rawJoin);
        break;
      } catch (_) {}
    }

    if (joinDate == null) {
      joinDate = DateTime.tryParse(rawJoin);
    }

    if (joinDate == null) return true;

    // Staff joining month value vs salary month value
    final salaryMonthVal = salaryMonthDate.year * 12 + salaryMonthDate.month;
    final joinMonthVal = joinDate.year * 12 + joinDate.month;

    return salaryMonthVal >= joinMonthVal;
  }

  List<Staff> getPendingSalaryStaff(String month) {
    return allStaff.where((s) {
      if (!isStaffEmployedInMonth(s, month)) return false;
      if (isSalaryPaid(s.id, month)) return false;
      final payable = getStaffCachedPayable(s.id);
      return payable > 0;
    }).toList();
  }

  /// Cached pending payable (same as Pay Salary → Pending Payable).
  double getStaffCachedPayable(String staffId) => _payableByStaff[staffId] ?? 0.0;

  double get totalPendingPayableForMonth =>
      _payableByStaff.values.fold(0.0, (sum, v) => sum + v);

  bool _advanceMatchesMonth(Map<String, dynamic> advance, String month) {
    final mStr = (advance['salary_month'] ?? '').toString().trim().toLowerCase();
    final givenDate = advance['given_date'] != null
        ? DateTime.tryParse(advance['given_date'].toString())
        : null;
    final calculatedMonth =
        givenDate != null ? DateFormat('MMMM yyyy').format(givenDate) : '';
    return mStr == month.trim().toLowerCase() ||
        (mStr.isEmpty && calculatedMonth.trim().toLowerCase() == month.trim().toLowerCase());
  }

  double _sumAdvanceDeduction(List<Map<String, dynamic>> advances, String month, {double draftAdvance = 0}) {
    double listSum = 0;
    for (final a in advances) {
      if (!_advanceMatchesMonth(a, month)) continue;
      final s = (a['status']?.toString() ?? '').toLowerCase();
      if (s == 'approved' || s == 'pending' || s == 'given') {
        final amt = a['remaining_amount'] ?? a['advance_amount'] ?? a['amount'];
        if (amt is num) listSum += amt.toDouble();
      }
    }
    if (listSum > 0) return listSum;
    return draftAdvance;
  }

  /// Single source of truth — mirrors PaySalaryScreen._totalPayable exactly.
  Future<double> getStaffPendingPayable({
    required String gymId,
    required Staff staff,
    required String salaryMonth,
  }) async {
    if (!isStaffEmployedInMonth(staff, salaryMonth)) return 0;
    if (isSalaryPaid(staff.id, salaryMonth)) return 0;

    final draft = await getOrCreateSalaryDraft(gymId, staff.id, salaryMonth);
    if (draft != null && draft.status.toLowerCase() == 'paid') {
      markSalaryAsPaid(staff.id, salaryMonth);
      return 0;
    }

    final commissions = await fetchStaffCommissions(staff.id, pendingOnly: true);
    final liveCommission = commissions.fold<double>(
      0,
      (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0),
    );
    final commission = liveCommission > 0 ? liveCommission : (draft?.commissionAmount ?? 0);

    List<SalaryAdjustment> adjustments = [];
    final draftId = draft?.id ?? '';
    if (draftId.isNotEmpty && !draftId.startsWith('draft_')) {
      adjustments = await fetchSalaryAdjustments(draftId);
    }
    final additions = adjustments.where((a) => a.type == 'Addition').fold(0.0, (s, a) => s + a.amount);
    final deductions = adjustments.where((a) => a.type == 'Deduction').fold(0.0, (s, a) => s + a.amount);
    final netAdjustment = additions - deductions;

    final advances = await fetchSalaryAdvances(staff.id);
    final advanceDeduction = _sumAdvanceDeduction(
      advances,
      salaryMonth,
      draftAdvance: draft?.advanceDeduction ?? 0,
    );

    final fixedSalary = (draft?.baseSalary ?? 0) > 0 ? draft!.baseSalary : staff.salary;
    final gross = fixedSalary + commission + netAdjustment;
    final payable = gross - advanceDeduction;
    return payable > 0 ? payable : 0;
  }

  Future<void> refreshStaffPayablesForMonth(String gymId, String month) async {
    _payableCacheMonth = month;
    _payableByStaff.clear();
    notifyListeners();

    await fetchSalaryDraftsForMonth(month);
    await fetchPaidSalariesForMonth(month);
    await fetchGymSalaryAdvances(gymId);

    for (final staff in allStaff.where((s) => s.status != 'Inactive')) {
      if (!isStaffEmployedInMonth(staff, month)) {
        _payableByStaff[staff.id] = 0;
        continue;
      }
      try {
        _payableByStaff[staff.id] = await getStaffPendingPayable(
          gymId: gymId,
          staff: staff,
          salaryMonth: month,
        );
      } catch (e) {
        print('refreshStaffPayables error for ${staff.id}: $e');
        _payableByStaff[staff.id] = 0;
      }
    }
    notifyListeners();
  }

  void invalidateStaffPayable(String staffId) {
    _payableByStaff.remove(staffId);
    notifyListeners();
  }

  // Helper methods to filter transactions and attendance by staff ID
  List<FinanceTransaction> getStaffTransactions(String staffId) {
    return _repository.getTransactions()
        .where((tx) => tx.title.contains(staffId) || tx.notes.contains(staffId) || tx.title.toLowerCase().contains('salary paid'))
        .toList();
  }

  List<AttendanceRecord> getStaffAttendance(String staffId) {
    return _repository.getAttendance()
        .where((r) => r.staffId == staffId && r.userType == 'Staff')
        .toList();
  }

  Future<void> addStaffMember(Staff staff) async {
    await _repository.saveStaff(staff);
    notifyListeners();
  }

  // Request leave
  Future<void> setLeaveStatus(String staffId, String status) async {
    final index = allStaff.indexWhere((s) => s.id == staffId);
    if (index >= 0) {
      final staff = allStaff[index];
      final updated = staff.copyWith(status: status);
      await _repository.saveStaff(updated);
      notifyListeners();
    }
  }

  // --- Invitations & Activation System ---
  Future<Map<String, dynamic>?> getLatestInvitation(String id) => _repository.getLatestInvitation(id, true);

  Future<String> generateInvitation({required String recordId, required String name, required String phone}) async {
    final code = await _repository.generateInvitation(recordId: recordId, name: name, phone: phone, isStaff: true);
    notifyListeners();
    return code;
  }

  Future<String> unlinkAccount(String recordId) async {
    final code = await _repository.unlinkAccount(recordId, true);
    notifyListeners();
    return code;
  }

  // --- Staff Roles Management ---
  List<Map<String, dynamic>> _staffRoles = [];
  List<Map<String, dynamic>> get staffRoles => _staffRoles;

  Future<void> fetchRoles(String gymId) async {
    _staffRoles = await _repository.fetchStaffRoles(gymId);
    notifyListeners();
  }

  Future<void> saveRoles(List<Map<String, dynamic>> roles) async {
    await _repository.saveStaffRoles(roles);
    _staffRoles = List.from(roles);
    notifyListeners();
  }

  Future<void> addCustomRole(String gymId, String name, String icon) async {
    await _repository.addCustomStaffRole(gymId, name, icon);
    await fetchRoles(gymId);
  }

  List<String> getEnabledRoleNames() {
    return _staffRoles
        .where((r) => r['is_enabled'] == true)
        .map((r) => r['role_name'] as String)
        .toList();
  }

  // --- Database Leave Requests ---
  Future<List<Map<String, dynamic>>> fetchLeaveRequests(String staffId) async {
    try {
      await _repository.fetchLeaveRequestsFromSupabase(staffId);
    } catch (_) {}
    return _repository.leaveRequests.where((l) => l['staff_id'] == staffId).toList();
  }

  Future<void> createLeaveRequest({
    required String gymId,
    required String staffId,
    required String leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    await _repository.createLeaveRequestOffline(
      gymId: gymId,
      staffId: staffId,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      leaveType: leaveType,
    );
    notifyListeners();
  }

  Future<void> updateLeaveStatus(String leaveId, String status) async {
    await _repository.updateLeaveStatusOffline(
      requestId: leaveId,
      status: status,
    );
    notifyListeners();
  }

  Future<void> updateSalaryAdvanceStatus(String requestId, String status) async {
    await _repository.updateSalaryAdvanceStatusOffline(
      requestId: requestId,
      status: status,
    );
    notifyListeners();
  }

  // --- Database Salary Advances ---
  Future<List<Map<String, dynamic>>> fetchSalaryAdvances(String staffId) async {
    try {
      await _repository.fetchSalaryAdvancesFromSupabase(staffId);
    } catch (_) {}
    return _repository.salaryAdvances.where((a) => a['staff_id'] == staffId).toList();
  }

  Future<void> createSalaryAdvance({
    required String gymId,
    required String staffId,
    required double amount,
    required String reason,
    required String date,
  }) async {
    await _repository.saveSalaryAdvanceOffline(
      gymId: gymId,
      staffId: staffId,
      amount: amount,
      reason: reason,
      date: date,
    );
    notifyListeners();
  }

  Future<void> fetchGymSalaryAdvances(String gymId) async {
    try {
      await _repository.fetchGymSalaryAdvancesFromSupabase(gymId);
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>> getStaffAdvancesForMonth(String staffId, String month) {
    return _repository.salaryAdvances.where((a) {
      final isStaff = a['staff_id'].toString() == staffId;
      final mStr = (a['salary_month'] ?? '').toString().trim().toLowerCase();
      final givenDate = a['given_date'] != null ? DateTime.tryParse(a['given_date'].toString()) : null;
      final calculatedMonth = givenDate != null ? DateFormat('MMMM yyyy').format(givenDate) : '';
      
      final matchesMonth = mStr == month.trim().toLowerCase() || 
                           (mStr.isEmpty && calculatedMonth.trim().toLowerCase() == month.trim().toLowerCase());
      return isStaff && matchesMonth;
    }).toList();
  }

  // --- Database Salary History ---
  Future<List<Map<String, dynamic>>> fetchSalaryHistory(String staffId) async {
    final gymId = _repository.storage.getGymInfo()?['id'];
    if (gymId != null) {
      try {
        await _repository.fetchSalaryDraftsFromSupabase(gymId);
      } catch (_) {}
    }

    final List<Map<String, dynamic>> result = [];
    final Set<String> processedMonths = {};

    final staff = allStaff.cast<Staff?>().firstWhere((s) => s?.id == staffId, orElse: () => null);
    final commissions = await fetchStaffCommissions(staffId, pendingOnly: false);

    // 1. Load from salaryDrafts
    for (final d in _repository.salaryDrafts) {
      if (d['staff_id']?.toString() == staffId) {
        final status = (d['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'paid' || d['paid_transaction_id'] != null) {
          final month = (d['salary_month'] ?? 'N/A').toString();
          processedMonths.add(month.trim().toLowerCase());
          
          final draftMap = Map<String, dynamic>.from(d);
          final monthComms = commissions.where((c) {
            final cMonth = (c['salary_month'] ?? '').toString().trim().toLowerCase();
            final cDate = c['created_at'] != null ? DateTime.tryParse(c['created_at'].toString()) : null;
            final cCalcMonth = cDate != null ? DateFormat('MMMM yyyy').format(cDate) : '';
            return cMonth == month.trim().toLowerCase() || cCalcMonth.toLowerCase() == month.trim().toLowerCase();
          }).toList();
          final commSum = monthComms.fold<double>(0.0, (s, c) => s + ((c['amount'] as num?)?.toDouble() ?? 0.0));

          final advances = getStaffAdvancesForMonth(staffId, month);
          final advSum = advances.fold<double>(0.0, (s, a) => s + ((a['recovered_amount'] ?? a['advance_amount'] ?? a['amount'] as num?)?.toDouble() ?? 0.0));

          final baseSal = (draftMap['base_salary'] as num?)?.toDouble() ?? staff?.salary ?? 5000.0;
          final commAmount = commSum > 0 ? commSum : ((draftMap['commission_amount'] as num?)?.toDouble() ?? 0.0);
          final advAmount = advSum > 0 ? advSum : ((draftMap['advance_deduction'] as num?)?.toDouble() ?? 0.0);
          final gross = baseSal + commAmount;
          final net = gross - advAmount;

          draftMap['base_salary'] = baseSal;
          draftMap['commission_amount'] = commAmount;
          draftMap['advance_deduction'] = advAmount;
          draftMap['gross_salary'] = gross;
          draftMap['net_salary'] = net;

          // Lookup matching finance transaction to get exact payment date
          final staffName = staff?.name.trim().toLowerCase() ?? '';
          String paidOnDate = '';
          String paymentMode = (draftMap['payment_mode'] ?? 'UPI').toString();
          
          final matchingTx = _repository.getTransactions().cast<FinanceTransaction?>().firstWhere(
            (t) {
              if (t == null) return false;
              if (draftMap['paid_transaction_id'] != null && t.id == draftMap['paid_transaction_id']) return true;
              final isSalary = t.category.toLowerCase().contains('salary') || t.title.toLowerCase().contains('salary');
              final matchesStaff = staffName.isNotEmpty && t.title.toLowerCase().contains(staffName);
              return isSalary && matchesStaff;
            },
            orElse: () => null,
          );

          if (matchingTx != null) {
            paidOnDate = matchingTx.date;
            paymentMode = matchingTx.paymentMethod.isNotEmpty ? matchingTx.paymentMethod : paymentMode;
          }

          if (paidOnDate.isEmpty && draftMap['created_at'] != null) {
            final cr = DateTime.tryParse(draftMap['created_at'].toString());
            if (cr != null) paidOnDate = DateFormat('dd MMM yyyy').format(cr);
          }

          draftMap['paid_on'] = paidOnDate;
          draftMap['paidOn'] = paidOnDate;
          draftMap['payment_mode'] = paymentMode;

          result.add(draftMap);
        }
      }
    }

    // 2. Also load from finance transactions matching staff name in title
    final staffName = staff?.name.trim().toLowerCase() ?? '';
    if (staffName.isNotEmpty) {
      final txs = _repository.getTransactions().where((tx) {
        final cat = tx.category.toLowerCase();
        final title = tx.title.toLowerCase();
        final isSalary = cat.contains('salary') || title.contains('salary');
        final matchesStaff = title.contains(staffName);
        return isSalary && matchesStaff;
      }).toList();

      for (final tx in txs) {
        String mStr = tx.date;
        try {
          final parsed = DateTime.tryParse(tx.transactionDate) ?? DateFormat('dd MMM yyyy').parse(tx.date);
          mStr = DateFormat('MMMM yyyy').format(parsed);
        } catch (_) {}

        if (!processedMonths.contains(mStr.trim().toLowerCase())) {
          processedMonths.add(mStr.trim().toLowerCase());

          final advances = getStaffAdvancesForMonth(staffId, mStr);
          final advSum = advances.fold<double>(0.0, (s, a) => s + ((a['recovered_amount'] ?? a['advance_amount'] ?? a['amount'] as num?)?.toDouble() ?? 0.0));
          final baseSal = staff?.salary ?? 5000.0;
          final netPaid = tx.amount;
          final gross = (netPaid + advSum >= baseSal) ? (netPaid + advSum) : baseSal;
          final comm = gross > (baseSal + advSum) ? (gross - baseSal) : ((netPaid + advSum > baseSal) ? (netPaid + advSum - baseSal) : 0.0);

          result.add({
            'id': tx.id,
            'gym_id': gymId ?? '',
            'staff_id': staffId,
            'salary_month': mStr,
            'base_salary': baseSal,
            'commission_amount': comm,
            'advance_deduction': advSum,
            'other_additions': 0.0,
            'other_deductions': 0.0,
            'net_salary': netPaid,
            'gross_salary': gross,
            'status': 'Paid',
            'created_at': tx.transactionDate.isNotEmpty ? tx.transactionDate : DateTime.now().toIso8601String(),
            'payment_mode': tx.paymentMethod.isNotEmpty ? tx.paymentMethod : 'UPI',
          });
        }
      }
    }

    return result;
  }

  Future<Map<String, List<Map<String, dynamic>>>> getStaffDashboardData(String staffId) async {
    final leaveRequests = await fetchLeaveRequests(staffId);
    final advances = await fetchSalaryAdvances(staffId);
    final salaryHistory = await fetchSalaryHistory(staffId);
    final attendanceRecords = getStaffAttendance(staffId);

    // Map leave requests
    final List<Map<String, dynamic>> mappedLeaves = leaveRequests.map((l) {
      final start = DateTime.tryParse(l['start_date']?.toString() ?? '') ?? DateTime.now();
      final end = DateTime.tryParse(l['end_date']?.toString() ?? '') ?? DateTime.now();
      final diffDays = end.difference(start).inDays + 1;
      final created = DateTime.tryParse(l['created_at']?.toString() ?? '') ?? DateTime.now();

      return {
        'id': l['id'],
        'start_date': l['start_date'],
        'end_date': l['end_date'],
        'from': DateFormat('dd MMM yyyy').format(start),
        'to': DateFormat('dd MMM yyyy').format(end),
        'days': diffDays,
        'leave_type': l['leave_type'] ?? 'Casual',
        'type': '${l['leave_type'] ?? 'Casual'} Leave',
        'reason': l['reason'] ?? 'N/A',
        'status': l['status'] ?? 'Pending',
        'appliedOn': DateFormat('dd MMM yyyy').format(created),
      };
    }).toList();

    // Map leave history (non-pending leaves)
    final leaveHist = mappedLeaves.where((l) => l['status'] != 'Pending').map((l) {
      return {
        'date': l['from'],
        'days': l['days'],
        'status': l['status'],
      };
    }).toList();

    // Map advance records
    final advList = advances.map((adv) {
      final reqDate = DateTime.tryParse(adv['given_date']?.toString() ?? '') ?? DateTime.now();
      return {
        'id': adv['id'],
        'advance_amount': (adv['advance_amount'] as num?)?.toDouble() ?? 0.0,
        'amount': (adv['advance_amount'] as num?)?.toDouble() ?? 0.0,
        'given_date': adv['given_date'],
        'givenOn': DateFormat('dd MMM yyyy').format(reqDate),
        'salary_month': adv['salary_month'] ?? 'Current Month',
        'reason': adv['reason'] ?? 'Personal',
        'status': adv['status'] ?? 'Pending',
      };
    }).toList();

    // Map salary history records
    final salHist = salaryHistory.map((sal) {
      final created = DateTime.tryParse(sal['created_at']?.toString() ?? '') ?? DateTime.now();
      final double netSalary = (sal['net_salary'] as num?)?.toDouble() ?? 0.0;
      final double baseSalary = (sal['base_salary'] as num?)?.toDouble() ?? 0.0;
      final double commissionAmount = (sal['commission_amount'] as num?)?.toDouble() ?? 0.0;
      final double advanceDeduction = (sal['advance_deduction'] as num?)?.toDouble() ?? 0.0;
      final double otherAdditions = (sal['other_additions'] as num?)?.toDouble() ?? 0.0;
      final double otherDeductions = (sal['other_deductions'] as num?)?.toDouble() ?? 0.0;

      final monthStr = (sal['salary_month'] ?? 'N/A').toString();

      // Find all advances related to this month to show itemized dates & amounts
      final monthAdvances = advList.where((a) {
        final aMonth = (a['salary_month'] ?? '').toString().trim().toLowerCase();
        final aGiven = a['given_date'] != null ? DateTime.tryParse(a['given_date'].toString()) : null;
        final calcMonth = aGiven != null ? DateFormat('MMMM yyyy').format(aGiven) : '';
        return aMonth == monthStr.trim().toLowerCase() || calcMonth.toLowerCase() == monthStr.trim().toLowerCase();
      }).toList();

      final totalMonthAdvances = monthAdvances.fold<double>(
        0.0, 
        (sum, a) => sum + ((a['recovered_amount'] ?? a['advance_amount'] ?? a['amount'] as num?)?.toDouble() ?? 0.0),
      );

      final double effectiveAdvanceDeduction = advanceDeduction > 0 ? advanceDeduction : totalMonthAdvances;

      // Effective Commission calculation
      double effectiveCommission = commissionAmount;
      if (effectiveCommission == 0 && netSalary > (baseSalary - effectiveAdvanceDeduction)) {
        effectiveCommission = netSalary + effectiveAdvanceDeduction - baseSalary - otherAdditions + otherDeductions;
      }

      // Total Gross Compensation: Base + Commission + Additions = Gross Earnings
      final double calculatedGross = baseSalary + effectiveCommission + otherAdditions - otherDeductions;
      final double grossFromDraft = (sal['gross_salary'] as num?)?.toDouble() ?? 0.0;
      final double finalGross = calculatedGross > 0
          ? (grossFromDraft > calculatedGross ? grossFromDraft : calculatedGross)
          : (grossFromDraft > 0 ? grossFromDraft : (netSalary + effectiveAdvanceDeduction));

      // Priority paid on date matching
      String paidOnDate = '';
      if (sal['paid_on'] != null && sal['paid_on'].toString().isNotEmpty) {
        paidOnDate = sal['paid_on'].toString();
      } else if (sal['paidOn'] != null && sal['paidOn'].toString().isNotEmpty) {
        paidOnDate = sal['paidOn'].toString();
      }

      if (paidOnDate.isEmpty) {
        final staffName = allStaff.cast<Staff?>().firstWhere((s) => s?.id == staffId, orElse: () => null)?.name.trim().toLowerCase() ?? '';
        final matchingTx = _repository.getTransactions().cast<FinanceTransaction?>().firstWhere(
          (t) {
            if (t == null) return false;
            if (sal['paid_transaction_id'] != null && t.id == sal['paid_transaction_id']) return true;
            final isSalary = t.category.toLowerCase().contains('salary') || t.title.toLowerCase().contains('salary');
            final matchesStaff = staffName.isNotEmpty && t.title.toLowerCase().contains(staffName);
            return isSalary && matchesStaff;
          },
          orElse: () => null,
        );
        if (matchingTx != null) {
          paidOnDate = matchingTx.date;
        }
      }

      if (paidOnDate.isEmpty) {
        paidOnDate = DateFormat('dd MMM yyyy').format(created);
      }

      return {
        'id': sal['id'],
        'month': monthStr,
        'salary_month': monthStr,
        'status': sal['status'] ?? 'Paid',
        'paidOn': paidOnDate,
        'paid_on': paidOnDate,
        'amount': netSalary,
        'net_salary': netSalary,
        'gross_salary': finalGross,
        'base_salary': baseSalary,
        'commission_amount': effectiveCommission,
        'advance_deduction': effectiveAdvanceDeduction,
        'other_additions': otherAdditions,
        'other_deductions': otherDeductions,
        'payment_mode': sal['payment_mode'] ?? 'UPI',
        'advances': monthAdvances,
      };
    }).toList();

    // Map attendance records
    final attList = attendanceRecords.map((att) {
      DateTime parsedDate;
      try {
        parsedDate = DateFormat('dd-MM-yyyy').parse(att.date);
      } catch (_) {
        parsedDate = DateTime.tryParse(att.date) ?? DateTime.now();
      }
      return {
        'date': parsedDate,
        'status': att.status,
        'checkIn': att.checkInTime,
        'checkOut': att.checkOutTime ?? '',
        'working_minutes': att.workingMinutes,
        'late_minutes': att.lateMinutes,
        'early_exit_minutes': att.earlyExitMinutes,
        'overtime_minutes': att.overtimeMinutes,
        'shift_status': att.shiftStatus,
      };
    }).toList();

    return {
      'leaveRequests': mappedLeaves,
      'leaveHistory': leaveHist,
      'advances': advList,
      'advance': advList,
      'salaryHistory': salHist,
      'attendance': attList,
    };
  }

  Future<SalaryDraft?> getOrCreateSalaryDraft(String gymId, String staffId, String salaryMonth) async {
    final data = await _repository.getOrCreateSalaryDraft(gymId, staffId, salaryMonth);
    if (data != null) {
      return SalaryDraft.fromJson(data);
    }
    return null;
  }

  Future<List<SalaryAdjustment>> fetchSalaryAdjustments(String draftId) async {
    final list = await _repository.fetchSalaryAdjustments(draftId);
    return list.map((e) => SalaryAdjustment.fromJson(e)).toList();
  }

  Future<void> addSalaryAdjustment({
    required String gymId,
    required String draftId,
    required String type,
    required double amount,
    required String reason,
    required String userId,
  }) async {
    await _repository.addSalaryAdjustment(
      gymId: gymId,
      draftId: draftId,
      type: type,
      amount: amount,
      reason: reason,
      userId: userId,
    );
    notifyListeners();
  }

  Future<void> paySalaryDraft({
    required String draftId,
    required String paymentMode,
    required String notes,
  }) async {
    await _repository.paySalaryDraft(
      draftId: draftId,
      paymentMode: paymentMode,
      notes: notes,
    );
    _payableByStaff.clear();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> fetchStaffCommissions(String staffId, {bool pendingOnly = true}) async {
    return await _repository.fetchStaffCommissions(staffId, pendingOnly: pendingOnly);
  }

  Future<List<Map<String, dynamic>>> fetchStaffLeaves(String staffId) async {
    return await _repository.fetchStaffLeaves(staffId);
  }

  Future<Map<String, dynamic>?> fetchStaffSalaryMonthLeaveDetails(String staffId, String salaryMonth) async {
    return await _repository.fetchStaffSalaryMonthLeaveDetails(staffId, salaryMonth);
  }

  Future<Map<String, dynamic>?> fetchPaidSalaryDraftDetails(String draftId) async {
    return await _repository.fetchPaidSalaryDraftDetails(draftId);
  }
}
