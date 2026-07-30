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
        notes: notes,
      );
      await _repository.saveTransaction(tx);
      
      notifyListeners();
    }
  }

  bool isSalaryPaid(String staffId, String month) {
    return _paidStaffByMonth[month]?.contains(staffId) ?? false;
  }

  void markSalaryAsPaid(String staffId, String month) {
    _paidStaffByMonth.putIfAbsent(month, () => {}).add(staffId);
    notifyListeners();
  }

  final Map<String, List<Map<String, dynamic>>> _draftsByMonth = {};

  List<Map<String, dynamic>> getDraftsForMonth(String month) {
    return _draftsByMonth[month] ?? [];
  }

  Future<void> fetchSalaryDraftsForMonth(String month) async {
    if (!SupabaseService.isInitialized) return;
    try {
      final List response = await SupabaseService.client
          .from('salary_drafts')
          .select()
          .eq('salary_month', month);
      
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
          .select('staff_id')
          .eq('salary_month', month)
          .eq('status', 'Paid');
      
      final Set<String> paidSet = response.map((item) => item['staff_id'].toString()).toSet();
      _paidStaffByMonth[month] = paidSet;
      notifyListeners();
    } catch (e) {
      print('fetchPaidSalariesForMonth error: $e');
    }
  }

  List<Staff> getPendingSalaryStaff(String month) {
    return allStaff.where((s) => !isSalaryPaid(s.id, month)).toList();
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
    if (!SupabaseService.isInitialized) return [];
    try {
      final List response = await SupabaseService.client
          .from('leave_requests')
          .select()
          .eq('staff_id', staffId)
          .order('start_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('fetchLeaveRequests error: $e');
      return [];
    }
  }

  Future<void> createLeaveRequest({
    required String gymId,
    required String staffId,
    required String leaveType,
    required String startDate,
    required String endDate,
    required String reason,
  }) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.from('leave_requests').insert({
        'gym_id': gymId,
        'staff_id': staffId,
        'leave_type': leaveType,
        'start_date': startDate,
        'end_date': endDate,
        'reason': reason,
        'status': 'Pending',
      });
      notifyListeners();
    } catch (e) {
      print('createLeaveRequest error: $e');
      throw Exception('Failed to request leave: $e');
    }
  }

  Future<void> updateLeaveStatus(String leaveId, String status) async {
    if (!SupabaseService.isInitialized) return;
    try {
      final ownerId = SupabaseService.client.auth.currentUser?.id;
      await SupabaseService.client.from('leave_requests').update({
        'status': status,
        'approved_by': ownerId,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', leaveId);
      notifyListeners();
    } catch (e) {
      print('updateLeaveStatus error: $e');
      throw Exception('Failed to update leave status: $e');
    }
  }

  // --- Database Salary Advances ---
  Future<List<Map<String, dynamic>>> fetchSalaryAdvances(String staffId) async {
    if (!SupabaseService.isInitialized) return [];
    try {
      final List response = await SupabaseService.client
          .from('salary_advance_ledger')
          .select()
          .eq('staff_id', staffId)
          .order('given_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('fetchSalaryAdvances error: $e');
      return [];
    }
  }

  Future<void> createSalaryAdvance({
    required String gymId,
    required String staffId,
    required double amount,
    required String reason,
    required String date,
  }) async {
    if (!SupabaseService.isInitialized) return;
    try {
      final parsedDate = DateTime.tryParse(date) ?? DateTime.now();
      final salaryMonth = DateFormat('MMMM yyyy').format(parsedDate);

      await SupabaseService.client.from('salary_advance_ledger').insert({
        'gym_id': gymId,
        'staff_id': staffId,
        'advance_amount': amount,
        'reason': reason,
        'status': 'Approved',
        'given_date': date,
        'salary_month': salaryMonth,
      });

      notifyListeners();
    } catch (e) {
      print('createSalaryAdvance error: $e');
      rethrow;
    }
  }

  // --- Database Salary History ---
  Future<List<Map<String, dynamic>>> fetchSalaryHistory(String staffId) async {
    if (!SupabaseService.isInitialized) return [];
    try {
      final List response = await SupabaseService.client
          .from('salary_drafts')
          .select()
          .eq('staff_id', staffId)
          .eq('status', 'Paid')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('fetchSalaryHistory error: $e');
      return [];
    }
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
        'from': DateFormat('dd MMM yyyy').format(start),
        'to': DateFormat('dd MMM yyyy').format(end),
        'days': diffDays,
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
        'amount': (adv['advance_amount'] as num?)?.toDouble() ?? 0.0,
        'givenOn': DateFormat('dd MMM yyyy').format(reqDate),
        'reason': adv['reason'] ?? 'Personal',
        'status': adv['status'] ?? 'Approved',
      };
    }).toList();

    // Map salary history records
    final salHist = salaryHistory.map((sal) {
      final created = DateTime.tryParse(sal['created_at']?.toString() ?? '') ?? DateTime.now();
      final double netSalary = (sal['net_salary'] as num?)?.toDouble() ?? 0.0;
      final double advanceDeduction = (sal['advance_deduction'] as num?)?.toDouble() ?? 0.0;
      final double grossSalary = (sal['gross_salary'] as num?)?.toDouble() ?? (netSalary + advanceDeduction);

      return {
        'id': sal['id'],
        'month': sal['salary_month'] ?? 'N/A',
        'paidOn': DateFormat('dd MMM yyyy').format(created),
        'amount': netSalary,
        'gross_salary': grossSalary,
        'base_salary': (sal['base_salary'] as num?)?.toDouble() ?? 0.0,
        'commission_amount': (sal['commission_amount'] as num?)?.toDouble() ?? 0.0,
        'advance_deduction': advanceDeduction,
        'other_additions': (sal['other_additions'] as num?)?.toDouble() ?? 0.0,
        'other_deductions': (sal['other_deductions'] as num?)?.toDouble() ?? 0.0,
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
      'leaveRequests': mappedLeaves.where((l) => l['status'] == 'Pending').toList(),
      'leaveHistory': leaveHist,
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
