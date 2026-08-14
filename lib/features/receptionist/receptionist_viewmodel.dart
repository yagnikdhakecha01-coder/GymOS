import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/staff.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/member.dart';

class ReceptionistViewModel extends ChangeNotifier {
  final String staffUserId;
  final String gymId;
  final GymRepository _repository;
  Staff? _staffRecord;
  RealtimeChannel? _realtimeChannel;

  // Overview Stats
  int _todayAttendanceCount = 0;
  int _todayTotalExpected = 0;
  int _newMembersCount = 0;
  int _pendingRenewalsCount = 0;
  double _todayIncome = 0.0;
  double _todayExpense = 0.0;

  List<Map<String, dynamic>> _recentActivities = [];
  bool _isLoading = false;

  ReceptionistViewModel({
    required this.staffUserId,
    required this.gymId,
    required GymRepository repository,
  }) : _repository = repository {
    _init();
  }

  Future<void> _init() async {
    await fetchStaffRecord();
    await fetchDashboardStats();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  // Getters
  Staff? get staffRecord => _staffRecord;
  bool get isLoading => _isLoading;
  int get todayAttendanceCount => _todayAttendanceCount;
  int get todayTotalExpected => _todayTotalExpected;
  int get newMembersCount => _newMembersCount;
  int get pendingRenewalsCount => _pendingRenewalsCount;
  double get todayIncome => _todayIncome;
  double get todayExpense => _todayExpense;
  List<Map<String, dynamic>> get recentActivities => _recentActivities;

  Map<String, dynamic> get permissions {
    return _staffRecord?.permissions ?? const {
      'add_member': true,
      'scan_attendance': true,
      'renew_membership': true,
      'add_income': true,
      'add_expense': true,
      'take_payment': true,
      'send_reminder': true,
      'broadcast': false,
    };
  }

  bool hasPermission(String actionKey) {
    return permissions[actionKey] == true;
  }

  // Fetch staff record from DB
  Future<void> fetchStaffRecord() async {
    final staffList = _repository.getStaff();
    final matching = staffList.where((s) => s.userId == staffUserId).toList();
    if (matching.isNotEmpty) {
      _staffRecord = matching.first;
      notifyListeners();
    } else {
      try {
        if (!SupabaseService.isInitialized) return;
        final res = await SupabaseService.client
            .from('staff')
            .select()
            .eq('user_id', staffUserId)
            .eq('gym_id', gymId)
            .maybeSingle();

        if (res != null) {
          _staffRecord = Staff.fromJson(res);
          notifyListeners();
        }
      } catch (e) {
        print('Error fetching staff record in ReceptionistViewModel: $e');
      }
    }
  }

  // Set up live real-time subscription for permission changes
  void _setupRealtimeListener() {
    if (!SupabaseService.isInitialized || _staffRecord == null) return;

    _realtimeChannel = SupabaseService.client
        .channel('public:staff:id=eq.${_staffRecord!.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'staff',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _staffRecord!.id,
          ),
          callback: (payload) {
            print('Receptionist permissions updated in real-time: ${payload.newRecord}');
            _staffRecord = Staff.fromJson(payload.newRecord);
            notifyListeners();
          },
        );
    
    _realtimeChannel!.subscribe();
  }

  // Fetch Dashboard Stats
  Future<void> fetchDashboardStats() async {
    if (_staffRecord == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final gymId = _staffRecord!.gymId;
      final now = DateTime.now();
      final todayDateOnly = DateTime(now.year, now.month, now.day);

      // 1. Today's Attendance Stats
      _todayTotalExpected = _repository.activeMembersCount;
      _todayAttendanceCount = _repository.todayAttendanceCount;

      // 2. New Members registered today
      _newMembersCount = _repository.getMembers().where((m) {
        final created = DateTime.tryParse(m.createdAt ?? '');
        if (created == null) return false;
        final createdDateOnly = DateTime(created.year, created.month, created.day);
        return createdDateOnly.isAtSameMomentAs(todayDateOnly);
      }).length;

      // 3. Pending Renewals (Memberships expiring in next 7 days)
      _pendingRenewalsCount = _repository.getMembers().where((m) {
        final exp = m.extraFields['expiryDate'] as String?;
        if (exp == null || exp.isEmpty) return false;
        final parsed = DateTime.tryParse(exp);
        if (parsed == null) return false;
        final expiryDateOnly = DateTime(parsed.year, parsed.month, parsed.day);
        final diff = expiryDateOnly.difference(todayDateOnly).inDays;
        return diff >= 0 && diff <= 7;
      }).length;

      // 4. Today's Income & Expense Sum
      double income = 0.0;
      double expense = 0.0;
      for (final tx in _repository.getTransactions()) {
        final txDateStr = tx.transactionDate.isNotEmpty ? tx.transactionDate : tx.entryDate;
        final parsed = DateTime.tryParse(txDateStr);
        if (parsed == null) continue;
        final parsedDateOnly = DateTime(parsed.year, parsed.month, parsed.day);
        if (parsedDateOnly.isAtSameMomentAs(todayDateOnly)) {
          if (tx.type == 'Revenue' || tx.type == 'Income') {
            income += tx.amount;
          } else {
            expense += tx.amount;
          }
        }
      }
      _todayIncome = income;
      _todayExpense = expense;

      // 5. Recent Activities logs
      if (SupabaseService.isInitialized) {
        try {
          final logsRes = await SupabaseService.client
              .from('activity_logs')
              .select()
              .eq('gym_id', gymId)
              .order('created_at', ascending: false)
              .limit(30)
              .timeout(const Duration(seconds: 3));

          final filteredLogs = (logsRes as List<dynamic>).where((log) {
            final action = (log['action'] ?? '').toString().toLowerCase();
            return !action.contains('viewed') && !action.contains('opened');
          }).take(10).toList();

          _recentActivities = List<Map<String, dynamic>>.from(filteredLogs);
        } catch (_) {}
      }

    } catch (e) {
      print('Error loading receptionist dashboard stats: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Insert an Audit log entry via RPC
  Future<void> logActivity(String action, String module, {String? targetMember}) async {
    if (!SupabaseService.isInitialized || _staffRecord == null) return;
    try {
      await SupabaseService.client.rpc(
        'log_activity',
        params: {
          'p_gym_id': _staffRecord!.gymId,
          'p_staff_id': _staffRecord!.id,
          'p_action': action,
          'p_module': module,
          'p_target_member': targetMember ?? '',
        },
      );
      // Refresh dashboard activities
      fetchDashboardStats();
    } catch (e) {
      print('Error logging activity: $e');
    }
  }
}
