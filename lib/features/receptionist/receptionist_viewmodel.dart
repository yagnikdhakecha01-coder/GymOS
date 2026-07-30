import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/staff.dart';

class ReceptionistViewModel extends ChangeNotifier {
  final String staffUserId;
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

  ReceptionistViewModel({required this.staffUserId}) {
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
    try {
      if (!SupabaseService.isInitialized) return;
      final res = await SupabaseService.client
          .from('staff')
          .select()
          .eq('user_id', staffUserId)
          .maybeSingle();

      if (res != null) {
        _staffRecord = Staff.fromJson(res);
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching staff record in ReceptionistViewModel: $e');
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
    if (!SupabaseService.isInitialized || _staffRecord == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final gymId = _staffRecord!.gymId;
      final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

      // 1. Today's Attendance Stats
      final attendanceLogs = await SupabaseService.client
          .from('attendance_logs')
          .select('id, status')
          .eq('gym_id', gymId)
          .eq('date', todayStr);

      final totalMembers = await SupabaseService.client
          .from('members')
          .select('id')
          .eq('gym_id', gymId);
      
      _todayTotalExpected = totalMembers.length;
      _todayAttendanceCount = attendanceLogs.where((l) => l['status'] == 'Present' || l['status'] == 'Late' || l['status'] == 'Half Leave').length;

      // 2. New Members registered today
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day).toIso8601String();
      final newMembers = await SupabaseService.client
          .from('members')
          .select('id')
          .eq('gym_id', gymId)
          .gte('created_at', startOfToday);

      _newMembersCount = newMembers.length;

      // 3. Pending Renewals (Memberships expiring in next 7 days or already expired)
      final endOfRange = DateTime.now().add(const Duration(days: 7)).toIso8601String();
      final renewals = await SupabaseService.client
          .from('member_memberships')
          .select('id')
          .eq('gym_id', gymId)
          .lte('end_date', endOfRange);

      _pendingRenewalsCount = renewals.length;

      // 4. Today's Income & Expense Sum
      final nowTx = DateTime.now();
      final startOfTodayTx = DateTime(nowTx.year, nowTx.month, nowTx.day).toUtc().toIso8601String();
      final endOfTodayTx = DateTime(nowTx.year, nowTx.month, nowTx.day, 23, 59, 59, 999).toUtc().toIso8601String();

      final transactions = await SupabaseService.client
          .from('finance_transactions')
          .select('amount, type')
          .eq('gym_id', gymId)
          .gte('transaction_date', startOfTodayTx)
          .lte('transaction_date', endOfTodayTx);

      double income = 0.0;
      double expense = 0.0;
      for (var tx in transactions) {
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        if (tx['type'] == 'Revenue') {
          income += amount;
        } else {
          expense += amount;
        }
      }
      _todayIncome = income;
      _todayExpense = expense;

      // 5. Recent Activities logs
      final logsRes = await SupabaseService.client
          .from('activity_logs')
          .select()
          .eq('gym_id', gymId)
          .order('created_at', ascending: false)
          .limit(10);

      _recentActivities = List<Map<String, dynamic>>.from(logsRes);

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
