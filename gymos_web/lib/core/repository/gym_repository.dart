import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/local_storage.dart';
import '../services/supabase_service.dart';
import '../models/member.dart';
import '../models/staff.dart';
import '../models/workout_plan.dart';
import '../models/diet_plan.dart';
import '../models/membership_plan.dart';
import '../models/finance.dart';
import '../models/attendance.dart';
import '../models/gym_setup.dart';
import '../models/activity.dart';
import '../models/attendance_settings.dart';
import '../models/display_session.dart';
import '../models/attendance_alert.dart';
import '../models/attendance_correction.dart';
import '../models/trial_member.dart';
import '../models/manual_attendance_entry.dart';
import '../models/attendance_audit_log.dart';
import '../models/gym_rules_model.dart';

import '../services/notification_service.dart';

class GymRepository extends ChangeNotifier {
  final LocalStorageService _storage;
  Timer? _syncTimer;
  RealtimeChannel? _realtimeChannel;
  String? _subscribedGymId;
  StreamSubscription<AuthState>? _authStateSubscription;

  // Database stats cache for dashboard
  double _dbMonthlyRevenue = 0.0;
  int _dbActiveMembers = 0;
  int _dbTotalMembers = 0;
  int _dbTodayAttendance = 0;
  int _dbExpiringToday = 0;
  int _dbExpiring15Days = 0;
  int _dbPendingLeaves = 0;
  int _dbPendingHolidays = 0;
  int _dbPendingAdvances = 0;
  Map<String, dynamic> _dashboardAlertsData = {};
  bool _loadingDashboardStats = false;

  Map<String, dynamic>? _todayAttendanceDetails;
  Map<String, dynamic>? get todayAttendanceDetails => _todayAttendanceDetails;

  bool get loadingDashboardStats => _loadingDashboardStats;

  DateTime _selectedDashboardDate = DateTime.now();
  DateTime get selectedDashboardDate => _selectedDashboardDate;

  void setSelectedDashboardDate(DateTime date) {
    _selectedDashboardDate = date;
    // Trigger remote fetch to update stats from Supabase in background
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId != null) {
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);
      fetchDashboardStatsFromSupabase(gymId, formattedDate);
    }
    notifyListeners();
  }

  int get activeMembersCount {
    final localActive = _members.where((m) => m.status == 'Active').length;
    return _dbActiveMembers > 0 ? _dbActiveMembers : localActive;
  }

  int get totalMembersCount {
    final localTotal = _members.length;
    return _dbTotalMembers > 0 ? _dbTotalMembers : localTotal;
  }

  double get monthlyRevenue {
    final targetMonth = _selectedDashboardDate.month;
    final targetYear = _selectedDashboardDate.year;
    final targetMonthShort = _getMonthShortName(targetMonth).toLowerCase();
    final targetYearStr = targetYear.toString();

    return _transactions.where((t) {
      if (t.type != 'Revenue') return false;

      if (t.transactionDate.isNotEmpty) {
        try {
          final dt = DateTime.parse(t.transactionDate);
          return dt.month == targetMonth && dt.year == targetYear;
        } catch (_) {}
      }

      final dateParts = t.date.split(' ');
      if (dateParts.length >= 3) {
        final monthStr = dateParts[1].toLowerCase();
        final yearStr = dateParts[2];
        return monthStr == targetMonthShort && yearStr == targetYearStr;
      }

      return false;
    }).fold(0.0, (sum, t) => sum + t.amount);
  }

  static String _getMonthShortName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) {
      return months[month - 1];
    }
    return '';
  }

  int get todayAttendanceCount {
    final dateStr = DateFormat('dd-MM-yyyy').format(_selectedDashboardDate);
    final localCount = _attendance
        .where((a) => a.date == dateStr && a.status != 'Absent')
        .length;
    // Fallback to server count if local is 0
    return localCount > 0 ? localCount : _dbTodayAttendance;
  }

  int get expiringTodayCount => _dbExpiringToday;
  int get expiring15DaysCount => _dbExpiring15Days;
  int get pendingLeavesCount => _dbPendingLeaves;
  int get pendingHolidaysCount => _dbPendingHolidays;
  int get pendingAdvancesCount => _dbPendingAdvances;

  double get attendancePercentage {
    final active = activeMembersCount;
    final todayAtt = todayAttendanceCount;
    return active > 0 ? (todayAtt / active) * 100 : 0.0;
  }

  // Raw JSON caches to prevent redundant notifyListeners calls
  String _lastMembersRaw = '';
  String _lastStaffRaw = '';
  String _lastTransactionsRaw = '';
  String _lastDietsRaw = '';
  String _lastMembershipsRaw = '';
  String _lastWorkoutsRaw = '';

  // Network connection error tracking
  bool _hasNetworkConnectionError = false;

  void _handleNetworkError(String methodName, Object error) {
    final errorStr = error.toString();
    final isConnectionError = errorStr.contains('SocketException') ||
                              errorStr.contains('ClientException') ||
                              errorStr.contains('Failed host lookup') ||
                              errorStr.contains('No address associated with hostname');
    if (isConnectionError) {
      if (!_hasNetworkConnectionError) {
        _hasNetworkConnectionError = true;
        print('Database Sync: Network connection lost ($methodName: $errorStr)');
      }
    } else {
      print('$methodName error: $error');
    }
  }

  void _resetNetworkError() {
    if (_hasNetworkConnectionError) {
      _hasNetworkConnectionError = false;
      print('Database Sync: Network connection restored.');
    }
  }

  // In-memory caches
  List<Member> _members = [];
  List<TrialMember> _trialMembers = [];
  String _lastTrialMembersRaw = '';
  List<Staff> _staff = [];
  List<WorkoutPlan> _workouts = [];
  List<DietPlan> _diets = [];
  List<MembershipPlan> _memberships = [];
  List<FinanceTransaction> _transactions = [];
  List<AttendanceRecord> _attendance = [];
  List<FitnessGoal> _goals = [];
  List<CustomField> _customFields = [];
  List<RecentActivity> _recentActivities = [];
  GymAttendanceSettings? _attendanceSettings;
  List<AttendanceDisplaySession> _displaySessions = [];
  List<AttendanceAlert> _alerts = [];
  List<AttendanceCorrectionRequest> _corrections = [];
  Map<String, dynamic> _dashboardStats = {};
  Map<String, dynamic> _reportsAnalytics = {};

  Map<String, dynamic> get reportsAnalytics => _reportsAnalytics;
  String get _currentGymId => _storage.getGymInfo()?['id'] ?? 'default';
  String get _reportsAnalyticsKey => 'gymos_reports_analytics_$_currentGymId';
  String get _membersKey => 'gymos_members_$_currentGymId';
  String get _trialMembersKey => 'gymos_trial_members_$_currentGymId';
  String get _staffKey => 'gymos_staff_$_currentGymId';
  String get _transactionsKey => 'gymos_transactions_$_currentGymId';
  String get _workoutsKey => 'gymos_workouts_$_currentGymId';
  String get _dietsKey => 'gymos_diets_$_currentGymId';
  String get _membershipsKey => 'gymos_memberships_$_currentGymId';
  String get _attendanceKey => 'gymos_attendance_$_currentGymId';
  String get _goalsKey => 'gymos_fitness_goals_$_currentGymId';
  String get _customFieldsKey => 'gymos_custom_fields_$_currentGymId';
  String get _dashboardStatsKey => 'gymos_dashboard_stats_$_currentGymId';
  String get _salaryAdvancesKey => 'gymos_salary_advances_$_currentGymId';
  String get _salaryDraftsKey => 'gymos_salary_drafts_$_currentGymId';
  String get _leaveRequestsKey => 'gymos_leave_requests_$_currentGymId';
  String get _gymShiftSettingsKey => 'gymos_gym_shift_settings_$_currentGymId';
  String get _gymShiftsListKey => 'gymos_gym_shifts_list_$_currentGymId';
  String get _attendanceSettingsKey => 'gymos_attendance_settings_$_currentGymId';
  String get _recentActivitiesKey => 'gymos_recent_activities_$_currentGymId';
  String get _alertsKey => 'gymos_attendance_alerts_$_currentGymId';
  String get _correctionsKey => 'gymos_attendance_corrections_$_currentGymId';

  List<Map<String, dynamic>> _salaryAdvances = [];
  List<Map<String, dynamic>> _salaryDrafts = [];
  List<Map<String, dynamic>> _leaveRequests = [];

  String _shiftMode = 'Single Shift';
  List<Map<String, dynamic>> _shiftsList = [];

  List<Map<String, dynamic>> get salaryAdvances => List.unmodifiable(_salaryAdvances);
  List<Map<String, dynamic>> get salaryDrafts => List.unmodifiable(_salaryDrafts);
  List<Map<String, dynamic>> get leaveRequests => List.unmodifiable(_leaveRequests);
  String get shiftMode => _shiftMode;
  List<Map<String, dynamic>> get shiftsList => _shiftsList;

  List<AttendanceAlert> get alerts => _alerts;
  List<AttendanceCorrectionRequest> get corrections => _corrections;
  Map<String, dynamic> get dashboardStats => _dashboardStats;
  Map<String, dynamic> get dashboardAlertsData => _dashboardAlertsData;
  void updateDashboardAlertsData(Map<String, dynamic> data) {
    _dashboardAlertsData = data;
    notifyListeners();
  }

  GymRepository(this._storage) {
    _loadAllFromStorage();
    _loadQueuesFromStorage();
    _startSyncTimer();
    if (SupabaseService.isInitialized) {
      _authStateSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        final session = data.session;
        if (event == AuthChangeEvent.signedOut) {
          clearAllData();
        } else if ((event == AuthChangeEvent.signedIn ||
                    event == AuthChangeEvent.tokenRefreshed ||
                    event == AuthChangeEvent.initialSession) &&
                   session != null) {
          reloadForActiveGym();
        }
      });
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      await triggerBackgroundSync();
    });
  }

  void _subscribeToRealtime(String gymId) {
    if (!SupabaseService.isInitialized || _subscribedGymId == gymId) return;
    try {
      _realtimeChannel?.unsubscribe();
      _subscribedGymId = gymId;
      _realtimeChannel = SupabaseService.client
          .channel('public_gym_realtime_$gymId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            callback: (payload) {
              final tableName = payload.table;
              print('Supabase Realtime Event Received: ${payload.eventType} on table: $tableName');

              // Verify gym_id matches if present in record to prevent multi-gym bleed
              final newRec = payload.newRecord;
              final oldRec = payload.oldRecord;
              final recordGymId = newRec['gym_id']?.toString() ?? oldRec['gym_id']?.toString();
              if (recordGymId != null && recordGymId != gymId) {
                return; // Event belongs to a different gym, ignore safely
              }
              
              if (tableName == 'members') {
                fetchMembersFromSupabase();
              } else if (tableName == 'trial_members') {
                fetchTrialMembersFromSupabase();
              } else if (tableName == 'staff') {
                fetchStaffFromSupabase();
              } else if (tableName == 'transactions' || tableName == 'finance_transactions') {
                fetchTransactionsFromSupabase();
                fetchMembersFromSupabase();
              } else if (tableName == 'attendance_logs') {
                fetchAttendanceLogsFromSupabase();
              } else if (tableName == 'workout_plans') {
                fetchWorkoutsFromSupabase();
              } else if (tableName == 'diet_plans') {
                fetchDietsFromSupabase();
              } else if (tableName == 'goals') {
                fetchGoalsFromSupabase();
              } else if (tableName == 'custom_fields') {
                fetchCustomFieldsFromSupabase();
              } else if (tableName == 'attendance_settings') {
                fetchAttendanceSettingsFromSupabase();
              } else if (tableName == 'display_sessions') {
                fetchDisplaySessionsFromSupabase();
              }
              // Optimization: Unhandled tables are ignored instead of running avalanche syncAllFromSupabase()

              // Update stats for live screen dashboard counters only for relevant changes
              if (tableName == 'members' || tableName == 'attendance_logs' || tableName == 'transactions' || tableName == 'finance_transactions') {
                final currentGymId = _storage.getGymInfo()?['id'];
                if (currentGymId != null) {
                  final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                  fetchDashboardStatsFromSupabase(currentGymId, todayStr);
                  fetchOwnerDashboardStats(currentGymId);
                }
              }
            },
          )
          .subscribe();
      print('Subscribed to Supabase Realtime channel for Gym $gymId');
    } catch (e) {
      print('Realtime subscription error: $e');
    }
  }

  Future<void> syncAllFromSupabase() async {
    if (!SupabaseService.isInitialized) return;
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) return;

    final role = _storage.getUserRole();
    if (role == 'member') {
      try {
        await fetchAttendanceLogsFromSupabase();
      } catch (e) {
        print('Member background sync error: $e');
      }
      return;
    }

    _subscribeToRealtime(gymId);

    try {
      await fetchMembersFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchTrialMembersFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchStaffFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchTransactionsFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchGoalsFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchCustomFieldsFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchWorkoutsFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchDietsFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchRecentActivitiesFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchAttendanceSettingsFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchAttendanceLogsFromSupabase();
      if (_hasNetworkConnectionError) return;
      await fetchDisplaySessionsFromSupabase();
      if (_hasNetworkConnectionError) return;
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await fetchDashboardStatsFromSupabase(gymId, todayStr);
      if (_hasNetworkConnectionError) return;
      await fetchReportsAnalyticsFromSupabase(gymId, todayStr);
      if (_hasNetworkConnectionError) return;
      await fetchOwnerDashboardStats(gymId);
      if (_hasNetworkConnectionError) return;
      await fetchAttendanceAlerts(gymId);
      if (_hasNetworkConnectionError) return;
      await fetchAttendanceCorrections(gymId);
    } catch (e) {
      print('Background sync error: $e');
    }
  }

  Future<void> fetchDashboardStatsFromSupabase(String gymId, String targetDate) async {
    if (!SupabaseService.isInitialized) return;
    _loadingDashboardStats = true;
    try {
      final response = await SupabaseService.client.rpc(
        'get_gym_dashboard_stats',
        params: {
          'p_gym_id': gymId,
          'p_target_date': targetDate,
        },
      );
      if (response != null && response is List && response.isNotEmpty) {
        final data = response[0] as Map<String, dynamic>;
        _dbMonthlyRevenue = (data['monthly_revenue'] as num?)?.toDouble() ?? 0.0;
        _dbActiveMembers = (data['active_members'] as num?)?.toInt() ?? 0;
        _dbTotalMembers = (data['total_members'] as num?)?.toInt() ?? 0;
        _dbTodayAttendance = (data['today_attendance'] as num?)?.toInt() ?? 0;
        _dbExpiringToday = (data['expiring_today'] as num?)?.toInt() ?? 0;
        _dbExpiring15Days = (data['expiring_15_days'] as num?)?.toInt() ?? 0;
        _dbPendingLeaves = (data['pending_leaves'] as num?)?.toInt() ?? 0;
        _dbPendingHolidays = (data['pending_holidays'] as num?)?.toInt() ?? 0;

        // Clamp to local pending counts so locally approved items stay hidden
        final localPendingLeaves2 = _leaveRequests.where((l) => l['status'] == 'Pending' && l['leave_type'] != 'Other').length;
        final localPendingHolidays2 = _leaveRequests.where((l) => l['status'] == 'Pending' && l['leave_type'] == 'Other').length;
        if (_dbPendingLeaves > localPendingLeaves2) _dbPendingLeaves = localPendingLeaves2;
        if (_dbPendingHolidays > localPendingHolidays2) _dbPendingHolidays = localPendingHolidays2;
      }

      // Query get_dashboard_alerts_v1 to get accurate realtime counts for alerts section
      try {
        final alertsResponse = await SupabaseService.client.rpc(
          'get_dashboard_alerts_v1',
          params: {'p_gym_id': gymId},
        );
        if (alertsResponse != null && alertsResponse is Map) {
          final alertsMap = Map<String, dynamic>.from(alertsResponse);
          _dashboardAlertsData = alertsMap;
          _dbExpiringToday = (alertsMap['memberships_ending_today']?['count'] as num?)?.toInt() ?? _dbExpiringToday;
          
          final exp1 = (alertsMap['memberships_expiring_1_day']?['count'] as num?)?.toInt() ?? 0;
          final exp3 = (alertsMap['memberships_expiring_3_days']?['count'] as num?)?.toInt() ?? 0;
          final exp7 = (alertsMap['memberships_expiring_7_days']?['count'] as num?)?.toInt() ?? 0;
          final exp15 = (alertsMap['memberships_expiring_15_days']?['count'] as num?)?.toInt() ?? 0;
          _dbExpiring15Days = exp1 + exp3 + exp7 + exp15;
          
          _dbPendingLeaves = (alertsMap['staff_leave_requests']?['count'] as num?)?.toInt() ?? 0;
          _dbPendingHolidays = (alertsMap['holiday_requests']?['count'] as num?)?.toInt() ?? 0;
          _dbPendingAdvances = (alertsMap['staff_advance_requests']?['count'] as num?)?.toInt() ?? 0;

          // Clamp to local pending counts only if local cache has items loaded
          if (_leaveRequests.isNotEmpty) {
            final localPendingLeaves = _leaveRequests.where((l) => l['status'] == 'Pending' && l['leave_type'] != 'Other').length;
            final localPendingHolidays = _leaveRequests.where((l) => l['status'] == 'Pending' && l['leave_type'] == 'Other').length;
            if (_dbPendingLeaves > localPendingLeaves) _dbPendingLeaves = localPendingLeaves;
            if (_dbPendingHolidays > localPendingHolidays) _dbPendingHolidays = localPendingHolidays;
          }
          if (_salaryAdvances.isNotEmpty) {
            final localPendingAdvances = _salaryAdvances.where((a) => a['status'] == 'Pending').length;
            if (_dbPendingAdvances > localPendingAdvances) _dbPendingAdvances = localPendingAdvances;
          }
        }
      } catch (alertsErr) {
        print('fetchDashboardStatsFromSupabase (alerts fetch fallback) error: $alertsErr');
      }
    } catch (e) {
      _handleNetworkError('fetchDashboardStatsFromSupabase', e);
    } finally {
      _loadingDashboardStats = false;
      notifyListeners();
    }
  }

  Future<void> fetchReportsAnalyticsFromSupabase(String gymId, String targetDate) async {
    if (!SupabaseService.isInitialized) return;
    try {
      final response = await SupabaseService.client.rpc(
        'get_reports_analytics',
        params: {
          'p_gym_id': gymId,
          'p_target_date': targetDate,
        },
      );
      if (response != null && response is List && response.isNotEmpty) {
        _reportsAnalytics = Map<String, dynamic>.from(response[0] as Map);
        await _storage.setString(_reportsAnalyticsKey, jsonEncode(_reportsAnalytics));
        notifyListeners();
      }
    } catch (e) {
      print('fetchReportsAnalyticsFromSupabase error: $e');
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _authStateSubscription?.cancel();
    super.dispose();
  }

  void clearAllData() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _subscribedGymId = null;

    _members = [];
    _staff = [];
    _workouts = [];
    _diets = [];
    _memberships = [];
    _transactions = [];
    _attendance = [];
    _goals = [];
    _customFields = [];
    _recentActivities = [];
    _alerts = [];
    _corrections = [];
    _dashboardStats = {};
    _todayAttendanceDetails = null;

    _dbMonthlyRevenue = 0.0;
    _dbActiveMembers = 0;
    _dbTotalMembers = 0;
    _dbTodayAttendance = 0;
    _dbExpiringToday = 0;
    _dbExpiring15Days = 0;
    _dbPendingLeaves = 0;
    _dbPendingHolidays = 0;
    _dbPendingAdvances = 0;
    _dashboardAlertsData = {};

    _lastMembersRaw = '';
    _lastStaffRaw = '';
    _lastTransactionsRaw = '';
    _lastWorkoutsRaw = '';
    _lastDietsRaw = '';
    _lastMembershipsRaw = '';

    _hasNetworkConnectionError = false;

    notifyListeners();
  }

  // --- Offline First Queues & Background Sync ---
  List<Map<String, dynamic>> _attendanceQueue = [];
  List<Map<String, dynamic>> _crudQueue = [];
  List<ManualAttendanceEntry> _manualAttendanceQueue = [];
  List<AttendanceAuditLog> _auditLogs = [];
  bool _isSyncing = false;

  List<Map<String, dynamic>> get attendanceQueue => List.unmodifiable(_attendanceQueue);
  List<Map<String, dynamic>> get crudQueue => List.unmodifiable(_crudQueue);
  List<ManualAttendanceEntry> get manualAttendanceQueue => List.unmodifiable(_manualAttendanceQueue);
  List<AttendanceAuditLog> get auditLogs => List.unmodifiable(_auditLogs);

  /// Returns true only if there are queue items that have actually failed to sync
  /// (e.g. after network retry or error). Normal pending/in-flight items will NOT trigger warnings.
  bool get hasFailedQueueItems {
    final hasFailedAttendance = _attendanceQueue.any((item) =>
        item['sync_status'] == 'failed' || (item['retry_count'] ?? 0) > 0 || item['error_message'] != null);

    final hasFailedCrud = _crudQueue.any((item) =>
        item['sync_status'] == 'failed' || (item['retry_count'] ?? 0) > 0 || item['error_message'] != null);

    final hasFailedManual = _manualAttendanceQueue.any((item) =>
        item.syncStatus == 'failed' || item.retryCount > 0 || item.errorMessage != null);

    return hasFailedAttendance || hasFailedCrud || hasFailedManual;
  }

  /// Returns count of failed queue items
  int get failedQueueCount {
    int count = 0;
    count += _attendanceQueue.where((item) =>
        item['sync_status'] == 'failed' || (item['retry_count'] ?? 0) > 0 || item['error_message'] != null).length;
    count += _crudQueue.where((item) =>
        item['sync_status'] == 'failed' || (item['retry_count'] ?? 0) > 0 || item['error_message'] != null).length;
    count += _manualAttendanceQueue.where((item) =>
        item.syncStatus == 'failed' || item.retryCount > 0 || item.errorMessage != null).length;
    return count;
  }

  Future<void> clearFailedQueueOperations() async {
    _crudQueue.removeWhere((item) => item['sync_status'] == 'failed' || item['error_message'] != null);
    _attendanceQueue.removeWhere((item) => item['sync_status'] == 'failed' || item['error_message'] != null);
    _manualAttendanceQueue.removeWhere((item) => item.syncStatus == 'failed' || item.errorMessage != null);
    await _saveQueuesToStorage();
    notifyListeners();
  }

  Future<void> removeQueueItem(String id) async {
    _crudQueue.removeWhere((item) => item['uuid'] == id);
    _attendanceQueue.removeWhere((item) => item['attendance_uuid'] == id);
    _manualAttendanceQueue.removeWhere((item) => item.operationUuid == id);
    await _saveQueuesToStorage();
    notifyListeners();
  }

  void _loadQueuesFromStorage() {
    final rawAtt = _storage.getString(LocalStorageService.keyAttendanceQueue);
    if (rawAtt != null && rawAtt.isNotEmpty) {
      try {
        _attendanceQueue = List<Map<String, dynamic>>.from(jsonDecode(rawAtt));
      } catch (_) {}
    }

    final rawCrud = _storage.getString(LocalStorageService.keyCrudQueue);
    if (rawCrud != null && rawCrud.isNotEmpty) {
      try {
        _crudQueue = List<Map<String, dynamic>>.from(jsonDecode(rawCrud));
        // Auto-heal / clean entries that had 22P02 UUID syntax failure or invalid non-UUID keys
        _crudQueue.removeWhere((item) {
          final err = item['error_message']?.toString() ?? '';
          if (err.contains('22P02') || err.contains('invalid input syntax for type uuid')) {
            print('Auto-Heal on load: Purging permanently failed UUID-syntax queue entry ${item['uuid']}');
            return true;
          }
          if (item['table'] == 'attendance_logs') {
            final payload = item['payload'] as Map<String, dynamic>?;
            if (payload != null) {
              final id = payload['id']?.toString();
              if (item['action'] == 'update' && (id == null || !_isValidUUID(id))) {
                print('Auto-Heal on load: Purging invalid attendance_logs update entry ${item['uuid']} due to non-UUID id: $id');
                return true;
              }
            }
          }
          return false;
        });

        // Reset retry count for failed/stuck items so they get retried now that we have fixed the database column
        for (var item in _crudQueue) {
          if (item['sync_status'] == 'failed' || (item['retry_count'] ?? 0) > 5) {
            item['sync_status'] = 'pending';
            item['retry_count'] = 0;
            item['error_message'] = null;
          }
        }
      } catch (_) {}
    }

    // Load manual attendance queue
    final rawManual = _storage.getString(LocalStorageService.keyManualAttendanceQueue);
    if (rawManual != null && rawManual.isNotEmpty) {
      try {
        final List decoded = jsonDecode(rawManual);
        _manualAttendanceQueue = decoded.map((e) => ManualAttendanceEntry.fromJson(e)).toList();
      } catch (_) {}
    }

    // Load audit logs
    final rawAudit = _storage.getString(LocalStorageService.keyAttendanceAuditLog);
    if (rawAudit != null && rawAudit.isNotEmpty) {
      try {
        final List decoded = jsonDecode(rawAudit);
        _auditLogs = decoded.map((e) => AttendanceAuditLog.fromJson(e)).toList();
      } catch (_) {}
    }
  }

  Future<void> _saveQueuesToStorage() async {
    await _storage.setString(LocalStorageService.keyAttendanceQueue, jsonEncode(_attendanceQueue));
    await _storage.setString(LocalStorageService.keyCrudQueue, jsonEncode(_crudQueue));
    await _storage.setString(
      LocalStorageService.keyManualAttendanceQueue,
      jsonEncode(_manualAttendanceQueue.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveAuditLogsToStorage() async {
    await _storage.setString(
      LocalStorageService.keyAttendanceAuditLog,
      jsonEncode(_auditLogs.map((e) => e.toJson()).toList()),
    );
  }

  Future<bool> isSupabaseReachable() async {
    if (!SupabaseService.isInitialized) return false;
    try {
      await SupabaseService.client.from('gyms').select('id').limit(1).timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get hasPendingOfflineOperations =>
      _crudQueue.isNotEmpty ||
      _attendanceQueue.isNotEmpty ||
      _manualAttendanceQueue.isNotEmpty;

  Future<void> triggerBackgroundSync({bool forceRetry = false}) async {
    if (_isSyncing) return;
    // Optimization: Skip network ping if there are no pending operations in offline queue
    if (!forceRetry && !hasPendingOfflineOperations) {
      return;
    }
    _isSyncing = true;
    try {
      final reachable = await isSupabaseReachable();
      if (!reachable) {
        print('Offline Sync: Supabase is currently unreachable. Will retry on next timer.');
        _isSyncing = false;
        return;
      }
      _resetNetworkError();

      if (forceRetry) {
        // Reset retry count of failed operations so they try again
        for (var item in _crudQueue) {
          if (item['sync_status'] == 'failed' || (item['retry_count'] ?? 0) > 5) {
            item['sync_status'] = 'pending';
            item['retry_count'] = 0;
            item['error_message'] = null;
          }
        }
        for (var item in _attendanceQueue) {
          if (item['sync_status'] == 'failed' || (item['retry_count'] ?? 0) > 5) {
            item['sync_status'] = 'pending';
            item['retry_count'] = 0;
            item['error_message'] = null;
          }
        }
        for (var item in _manualAttendanceQueue) {
          if (item.syncStatus == 'failed' || item.retryCount > 5) {
            item.syncStatus = 'pending';
            item.retryCount = 0;
            item.errorMessage = null;
          }
        }
        await _saveQueuesToStorage();
        notifyListeners();
      }

      await _processAttendanceQueue();
      await _processCrudQueue();
      await _processManualAttendanceQueue();
      await _runBackgroundVerification();
    } catch (e) {
      print('triggerBackgroundSync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<bool> isAttendanceProcessed(String uuid) async {
    if (!SupabaseService.isInitialized) return false;
    try {
      final res = await SupabaseService.client
          .from('attendance_logs')
          .select('id')
          .eq('id', uuid)
          .maybeSingle();
      return res != null;
    } catch (_) {}
    return false;
  }

  Future<bool> isOperationProcessed(Map<String, dynamic> item) async {
    if (!SupabaseService.isInitialized) return false;
    
    final table = item['table'] as String;
    final action = item['action'] as String;
    final payload = item['payload'] as Map<String, dynamic>;
    
    if (table.startsWith('rpc_')) {
      if (table == 'rpc_pay_salary_draft') {
        final draftId = payload['p_draft_id'] as String?;
        if (draftId != null) {
          try {
            final res = await SupabaseService.client
                .from('salary_drafts')
                .select('status')
                .eq('id', draftId)
                .maybeSingle();
            if (res != null && (res['status'] == 'Paid' || res['status'] == 'paid')) {
              return true;
            }
          } catch (_) {}
        }
      }
      return false;
    }
    
    final id = payload['id'] as String?;
    if (id == null) return false;
    
    try {
      if (action == 'insert') {
        final res = await SupabaseService.client
            .from(table)
            .select('id')
            .eq('id', id)
            .maybeSingle();
        return res != null;
      } else if (action == 'delete') {
        final res = await SupabaseService.client
            .from(table)
            .select('id')
            .eq('id', id)
            .maybeSingle();
        return res == null;
      }
    } catch (_) {}
    
    return false;
  }

  Future<void> _processAttendanceQueue() async {
    if (_attendanceQueue.isEmpty) return;
    if (!SupabaseService.isInitialized) return;

    final List<Map<String, dynamic>> toProcess = List.from(_attendanceQueue);

    for (var item in toProcess) {
      if (item['sync_status'] == 'synced' || (item['retry_count'] ?? 0) > 5) continue;

      item['sync_status'] = 'syncing';
      await _saveQueuesToStorage();

      try {
        final attendanceUuid = item['attendance_uuid'] as String;
        final alreadyProcessed = await isAttendanceProcessed(attendanceUuid);
        
        if (alreadyProcessed) {
          print('Attendance Sync: Log $attendanceUuid already processed on server. Skipping insert.');
        } else {
          final gymId = item['gym_id'] as String;
          final memberId = item['member_id'] as String?;
          final staffId = item['staff_id'] as String?;
          final userId = item['user_id'] as String?;
          final attendanceType = item['attendance_type'] as String;
          final shiftId = item['shift_id'] as String?;
          final date = item['date'] as String;
          final checkInIso = item['check_in'] as String;
          final checkOutIso = item['check_out'] as String?;
          final status = item['status'] as String;
          final userType = item['user_type'] as String;
          final validShiftId = _isValidUUID(shiftId) ? shiftId : null;
          final shiftStatus = item['shift_status'] as String? ?? (!_isValidUUID(shiftId) ? shiftId : null);

          final data = {
            'id': attendanceUuid,
            'gym_id': gymId,
            'user_id': _isValidUUID(userId) ? userId : null,
            'role': userType,
            'user_type': userType,
            'member_id': _isValidUUID(memberId) ? memberId : null,
            'staff_id': _isValidUUID(staffId) ? staffId : null,
            if (validShiftId != null) 'shift_id': validShiftId,
            if (shiftStatus != null && shiftStatus.isNotEmpty) 'shift_status': shiftStatus,
            'date': date,
            'check_in': checkInIso,
            'check_out': checkOutIso,
            'status': status,
            'method': 'Manual',
          };

          await SupabaseService.client.from('attendance_logs').upsert(data);
        }

        // Success - remove from queue
        _attendanceQueue.removeWhere((q) => q['attendance_uuid'] == attendanceUuid);
        await _saveQueuesToStorage();
        print('Synced attendance log $attendanceUuid successfully.');
      } catch (e) {
        final errStr = e.toString();
        final attendanceUuid = item['attendance_uuid']?.toString() ?? '';
        if (errStr.contains('23505') || errStr.contains('uniq_attendance_user_date_shift') || errStr.contains('duplicate key')) {
          print('Attendance Sync Auto-Heal: Record already exists on server ($attendanceUuid). Updating existing server record.');
          try {
            final gymId = item['gym_id'] as String;
            final date = item['date'] as String;
            final userId = item['user_id'] as String?;
            final memberId = item['member_id'] as String?;
            final staffId = item['staff_id'] as String?;
            final checkInIso = item['check_in'] as String?;
            final checkOutIso = item['check_out'] as String?;
            final status = item['status'] as String?;

            var updateQuery = SupabaseService.client.from('attendance_logs').update({
              if (checkInIso != null) 'check_in': checkInIso,
              if (checkOutIso != null) 'check_out': checkOutIso,
              if (status != null) 'status': status,
            }).eq('gym_id', gymId).eq('date', date);

            if (userId != null && userId.isNotEmpty) {
              updateQuery = updateQuery.eq('user_id', userId);
            } else if (memberId != null && memberId.isNotEmpty) {
              updateQuery = updateQuery.eq('member_id', memberId);
            } else if (staffId != null && staffId.isNotEmpty) {
              updateQuery = updateQuery.eq('staff_id', staffId);
            }
            await updateQuery;
          } catch (_) {}

          // Remove duplicate conflict item from queue so it's resolved cleanly
          _attendanceQueue.removeWhere((q) => q['attendance_uuid'] == attendanceUuid);
          await _saveQueuesToStorage();
          continue;
        }

        if (errStr.contains('22P02') || errStr.contains('invalid input syntax for type uuid')) {
          print('Attendance Sync Auto-Heal: 22P02 Invalid UUID encountered ($attendanceUuid). Removing bad entry.');
          _attendanceQueue.removeWhere((q) => q['attendance_uuid'] == attendanceUuid);
          await _saveQueuesToStorage();
          continue;
        }

        print('Error syncing attendance log: $e');
        item['sync_status'] = 'failed';
        item['retry_count'] = (item['retry_count'] ?? 0) + 1;
        item['error_message'] = e.toString();
        await _saveQueuesToStorage();

        // Push Local Sync Alert
        try {
          await NotificationService.showNotification(
            id: item['attendance_uuid'].hashCode,
            title: 'Attendance Sync Failed',
            body: 'Failed to sync manual attendance for ${item['user_name']}: $e',
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _processCrudQueue() async {
    if (_crudQueue.isEmpty) return;
    if (!SupabaseService.isInitialized) return;

    final List<Map<String, dynamic>> toProcess = List.from(_crudQueue);

    // Sort queue by table dependency weight so parent records (members, staff, gyms) are always synced first
    int getTablePriority(String table) {
      if (table == 'gyms') return 1;
      if (table == 'members') return 2;
      if (table == 'staff') return 2;
      if (table == 'membership_plans') return 2;
      if (table == 'member_memberships') return 3;
      if (table == 'pt_assignments') return 3;
      if (table == 'finance_transactions') return 4;
      return 5;
    }

    toProcess.sort((a, b) {
      final pA = getTablePriority(a['table']?.toString() ?? '');
      final pB = getTablePriority(b['table']?.toString() ?? '');
      return pA.compareTo(pB);
    });

    for (var item in toProcess) {
      if ((item['retry_count'] ?? 0) > 5) continue;

      try {
        final uuid = item['uuid'] as String;
        final table = item['table'] as String;
        final action = item['action'] as String;
        final payload = item['payload'] as Map<String, dynamic>? ?? {};

        // Auto-heal corrupt queue entries that violate non-null database constraints
        if (table == 'leave_requests' || table == 'salary_advance_ledger' || table == 'finance_transactions' || table == 'member_memberships' || table == 'members') {
          if (action != 'update') {
            final gymId = payload['gym_id'] ?? payload['gymId'];
            if (gymId == null || gymId.toString().isEmpty) {
              print('Auto-Heal: Removing corrupt queue entry $uuid for table $table due to missing gym_id.');
              _crudQueue.removeWhere((q) => q['uuid'] == uuid);
              await _saveQueuesToStorage();
              continue;
            }
          }
        }

        // Auto-heal finance_transactions category strings to match database check constraint
        if (table == 'finance_transactions' && payload.containsKey('category')) {
          final rawCategory = payload['category']?.toString() ?? 'Other';
          payload['category'] = _sanitizeCategory(rawCategory);
        }

        // Auto-heal corrupt attendance updates missing check_in or invalid UUIDs
        if (table == 'attendance_logs') {
          // If action is update, verify id is a valid UUID
          if (action == 'update') {
            final logId = payload['id']?.toString();
            if (logId == null || !_isValidUUID(logId)) {
              print('Auto-Heal: Removing corrupt attendance_logs queue entry $uuid due to invalid/missing id ($logId).');
              _crudQueue.removeWhere((q) => q['uuid'] == uuid);
              await _saveQueuesToStorage();
              continue;
            }
          }

          final checkIn = payload['check_in'];
          if (checkIn == null || checkIn.toString().isEmpty) {
            print('Auto-Heal: Removing corrupt attendance_logs queue entry $uuid due to missing check_in.');
            _crudQueue.removeWhere((q) => q['uuid'] == uuid);
            await _saveQueuesToStorage();
            continue;
          }

          // Auto-heal non-UUID strings passed to UUID columns
          if (payload.containsKey('shift_id')) {
            final shiftIdVal = payload['shift_id']?.toString();
            if (shiftIdVal != null && !_isValidUUID(shiftIdVal)) {
              if (payload['shift_status'] == null || payload['shift_status'].toString().isEmpty) {
                payload['shift_status'] = shiftIdVal;
              }
              payload.remove('shift_id');
            }
          }
          for (final uuidCol in ['user_id', 'member_id', 'staff_id', 'display_id', 'created_by']) {
            if (payload.containsKey(uuidCol)) {
              final val = payload[uuidCol]?.toString();
              if (val != null && !_isValidUUID(val)) {
                payload.remove(uuidCol);
              }
            }
          }
        }

        item['sync_status'] = 'syncing';
        await _saveQueuesToStorage();

        final alreadyProcessed = await isOperationProcessed(item);
        if (alreadyProcessed) {
          print('Sync: Operation $uuid already processed on server. Skipping execution.');
        } else {
          if (table == 'rpc_pay_salary_draft') {
            await SupabaseService.client.rpc(
              'pay_salary_draft_v2',
              params: payload,
            );
          } else if (table == 'rpc_save_gym_operating_hours') {
            await SupabaseService.client.rpc(
              'save_gym_operating_hours',
              params: payload,
            );
          } else if (table == 'rpc_sync_member_payment_amounts') {
            await SupabaseService.client.rpc(
              'sync_member_payment_amounts',
              params: payload,
            );
          } else if (table == 'rpc_change_member_pt') {
            await SupabaseService.client.rpc(
              'change_member_pt',
              params: payload,
            );
          } else if (action == 'update') {
            final id = payload['id'] as String;
            final updateData = Map<String, dynamic>.from(payload)..remove('id')..remove('uuid')..remove('gym_id');
            await SupabaseService.client.from(table).update(updateData).eq('id', id);
          } else if (action == 'insert') {
            await SupabaseService.client.from(table).upsert(payload);
          } else if (action == 'delete') {
            final id = payload['id'] as String;
            await SupabaseService.client.from(table).delete().eq('id', id);
          }
        }

        // Success - remove from queue
        _crudQueue.removeWhere((q) => q['uuid'] == uuid);
        await _saveQueuesToStorage();
        print('Synced CRUD operation $uuid successfully.');
      } catch (e) {
        final errStr = e.toString();
        final uuid = item['uuid']?.toString() ?? '';
        if (errStr.contains('23505') || errStr.contains('uniq_attendance_user_date_shift') || errStr.contains('duplicate key')) {
          print('CRUD Sync Auto-Heal: Duplicate constraint 23505 encountered ($uuid). Removing conflict from queue.');
          _crudQueue.removeWhere((q) => q['uuid'] == uuid);
          await _saveQueuesToStorage();
          continue;
        }

        if (errStr.contains('22P02') || errStr.contains('invalid input syntax for type uuid')) {
          print('CRUD Sync Auto-Heal: 22P02 Invalid UUID encountered ($uuid). Removing corrupt entry from queue.');
          _crudQueue.removeWhere((q) => q['uuid'] == uuid);
          await _saveQueuesToStorage();
          continue;
        }

        print('Error syncing CRUD operation: $e');
        item['sync_status'] = 'failed';
        item['retry_count'] = (item['retry_count'] ?? 0) + 1;
        item['error_message'] = e.toString();
        await _saveQueuesToStorage();

        // Push Local Sync Alert
        try {
          await NotificationService.showNotification(
            id: item['uuid'].hashCode,
            title: 'Data Sync Failed',
            body: 'Failed to sync ${item['table']} action: $e',
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _runBackgroundVerification() async {
    try {
      final gymId = _storage.getGymInfo()?['id'];
      await fetchMembersFromSupabase();
      await fetchTrialMembersFromSupabase();
      await fetchStaffFromSupabase();
      await fetchTransactionsFromSupabase();
      await fetchAttendanceLogsFromSupabase();
      await fetchAttendanceSettingsFromSupabase();
      if (gymId != null) {
        await fetchOwnerDashboardStats(gymId);
      }
      // Refresh offline caches for emergency attendance
      await cacheOfflineMemberData();
      await cacheOfflineStaffData();
    } catch (e) {
      print('Background verification error: $e');
    }
  }

  Future<void> queueAttendance({
    required String gymId,
    String? memberId,
    String? staffId,
    String? userId,
    required String attendanceType,
    String? shiftId,
    required String date,
    required String checkIn,
    String? checkOut,
    required String status,
    required String userType,
    required String userName,
  }) async {
    final String uuid = _generateUuidV4();
    final nowStr = DateTime.now().toIso8601String();

    final item = {
      'attendance_uuid': uuid,
      'gym_id': gymId,
      'member_id': memberId,
      'staff_id': staffId,
      'user_id': userId,
      'attendance_type': attendanceType,
      'shift_id': shiftId,
      'date': date,
      'check_in': checkIn,
      'check_out': checkOut,
      'status': status,
      'user_type': userType,
      'user_name': userName,
      'created_at': nowStr,
      'updated_at': nowStr,
      'sync_status': 'pending',
      'retry_count': 0,
      'error_message': null,
    };

    _attendanceQueue.add(item);
    await _saveQueuesToStorage();

    final localRecord = AttendanceRecord(
      id: uuid,
      userId: userId ?? staffId ?? memberId ?? '',
      userName: userName,
      userType: userType,
      checkInTime: DateFormat('hh:mm a').format(DateTime.parse(checkIn).toLocal()),
      checkOutTime: checkOut != null ? DateFormat('hh:mm a').format(DateTime.parse(checkOut).toLocal()) : null,
      date: date,
      status: status,
      workingMinutes: 0,
      lateMinutes: 0,
      earlyExitMinutes: 0,
      overtimeMinutes: 0,
      ruleVersion: 1,
      staffId: staffId,
    );

    _attendance.insert(0, localRecord);
    await _storage.setString(_attendanceKey, jsonEncode(_attendance.map((e) => e.toJson()).toList()));
    notifyListeners();

    triggerBackgroundSync();
  }

  Future<void> queueCheckOut({
    required String gymId,
    String? memberId,
    String? staffId,
    required String date,
    required String checkOutTimeIso,
  }) async {
    final nowStr = DateTime.now().toIso8601String();
    final targetId = memberId ?? staffId;
    final index = _attendance.indexWhere((r) => 
      (r.userId == targetId || r.staffId == targetId) && 
      r.date == date && 
      r.checkOutTime == null
    );

    if (index >= 0) {
      final existingRecord = _attendance[index];
      final checkOutTimeStr = DateFormat('hh:mm a').format(DateTime.parse(checkOutTimeIso).toLocal());
      
      _attendance[index] = existingRecord.copyWith(
        checkOutTime: checkOutTimeStr,
      );
      await _storage.setString(_attendanceKey, jsonEncode(_attendance.map((e) => e.toJson()).toList()));
      notifyListeners();

      final qIndex = _attendanceQueue.indexWhere((q) => 
        q['attendance_uuid'] == existingRecord.id && 
        q['sync_status'] == 'pending'
      );

      if (qIndex >= 0) {
        _attendanceQueue[qIndex]['check_out'] = checkOutTimeIso;
        _attendanceQueue[qIndex]['attendance_type'] = 'Check Out';
        _attendanceQueue[qIndex]['updated_at'] = nowStr;
      } else {
        final checkOutItem = {
          'attendance_uuid': existingRecord.id,
          'gym_id': gymId,
          'member_id': memberId,
          'staff_id': staffId,
          'user_id': existingRecord.userId,
          'attendance_type': 'Check Out',
          'shift_id': _isValidUUID(existingRecord.shiftStatus) ? existingRecord.shiftStatus : null,
          if (existingRecord.shiftStatus != null && existingRecord.shiftStatus!.isNotEmpty)
            'shift_status': existingRecord.shiftStatus,
          'date': date,
          'check_in': DateTime.now().toIso8601String(),
          'check_out': checkOutTimeIso,
          'status': existingRecord.status,
          'user_type': existingRecord.userType,
          'user_name': existingRecord.userName,
          'created_at': nowStr,
          'updated_at': nowStr,
          'sync_status': 'pending',
          'retry_count': 0,
          'error_message': null,
        };
        _attendanceQueue.add(checkOutItem);
      }
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  // ===================================================================
  // EMERGENCY ATTENDANCE RECOVERY SYSTEM
  // ===================================================================

  // --- Offline Member/Staff Cache ---

  /// Caches active member data locally for offline manual attendance.
  Future<void> cacheOfflineMemberData() async {
    try {
      final members = getMembers().where((m) => m.status == 'Active').toList();
      final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());
      final todayAttIds = _attendance
          .where((a) => a.date == todayStr && a.userType == 'Member')
          .map((a) => a.userId)
          .toSet();

      final cacheData = members.map((m) => {
        'id': m.id,
        'name': m.name,
        'avatar': m.avatar,
        'phone': m.phone,
        'status': m.status,
        'membership_plan_id': m.membershipPlanId,
        'marked_today': todayAttIds.contains(m.id),
      }).toList();

      await _storage.setString(
        LocalStorageService.keyOfflineMemberCache,
        jsonEncode(cacheData),
      );
    } catch (e) {
      print('cacheOfflineMemberData error: $e');
    }
  }

  /// Caches active staff data locally for offline manual attendance.
  Future<void> cacheOfflineStaffData() async {
    try {
      final staff = getStaff().where((s) => s.status == 'Active').toList();
      final cacheData = staff.map((s) => {
        'id': s.id,
        'name': s.name,
        'avatar': s.avatar,
        'phone': s.phone,
        'role': s.role,
        'shift': s.shift,
        'user_id': s.userId,
        'status': s.status,
      }).toList();

      await _storage.setString(
        LocalStorageService.keyOfflineStaffCache,
        jsonEncode(cacheData),
      );
    } catch (e) {
      print('cacheOfflineStaffData error: $e');
    }
  }

  /// Returns cached members for offline manual attendance.
  /// Falls back to in-memory members if cache is empty.
  List<Map<String, dynamic>> getOfflineMembers() {
    final raw = _storage.getString(LocalStorageService.keyOfflineMemberCache);
    if (raw != null && raw.isNotEmpty) {
      try {
        return List<Map<String, dynamic>>.from(jsonDecode(raw));
      } catch (_) {}
    }
    // Fallback: build from in-memory members
    final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final todayAttIds = _attendance
        .where((a) => a.date == todayStr && a.userType == 'Member')
        .map((a) => a.userId)
        .toSet();

    return getMembers()
        .where((m) => m.status == 'Active')
        .map((m) => {
              'id': m.id,
              'name': m.name,
              'avatar': m.avatar,
              'phone': m.phone,
              'status': m.status,
              'membership_plan_id': m.membershipPlanId,
              'marked_today': todayAttIds.contains(m.id),
            })
        .toList();
  }

  /// Returns cached staff for offline manual attendance.
  /// Falls back to in-memory staff if cache is empty.
  List<Map<String, dynamic>> getOfflineStaff() {
    final raw = _storage.getString(LocalStorageService.keyOfflineStaffCache);
    if (raw != null && raw.isNotEmpty) {
      try {
        return List<Map<String, dynamic>>.from(jsonDecode(raw));
      } catch (_) {}
    }
    // Fallback: build from in-memory staff
    return getStaff()
        .where((s) => s.status == 'Active')
        .map((s) => {
              'id': s.id,
              'name': s.name,
              'avatar': s.avatar,
              'phone': s.phone,
              'role': s.role,
              'shift': s.shift,
              'user_id': s.userId,
              'status': s.status,
            })
        .toList();
  }

  // --- Manual Attendance Queue ---

  /// Queues manual member attendance for multiple members at once.
  /// Saves locally first, syncs to cloud automatically when available.
  Future<void> queueManualMemberAttendance({
    required String gymId,
    required List<Map<String, dynamic>> members,
    required String reason,
    required String addedBy,
    required String addedByRole,
  }) async {
    final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final now = DateTime.now();

    for (final member in members) {
      final memberId = member['id'] as String;
      final memberName = member['name'] as String;

      // Duplicate check: skip if already in queue or already marked today
      final alreadyQueued = _manualAttendanceQueue.any(
        (e) => e.memberId == memberId && e.date == todayStr,
      );
      final alreadyMarked = _attendance.any(
        (a) => a.userId == memberId && a.date == todayStr && a.status != 'Absent',
      );
      if (alreadyQueued || alreadyMarked) continue;

      final uuid = _generateUuidV4();
      final entry = ManualAttendanceEntry(
        operationUuid: uuid,
        gymId: gymId,
        memberId: memberId,
        userType: 'Member',
        userName: memberName,
        userAvatar: member['avatar'] as String?,
        status: 'Present',
        date: todayStr,
        checkInIso: nowIso,
        reason: reason,
        addedBy: addedBy,
        addedByRole: addedByRole,
        createdAt: now,
        updatedAt: now,
      );

      _manualAttendanceQueue.add(entry);

      // Add to local attendance list immediately
      final localRecord = AttendanceRecord(
        id: uuid,
        userId: memberId,
        userName: memberName,
        userType: 'Member',
        checkInTime: DateFormat('hh:mm a').format(now),
        date: todayStr,
        status: 'Present',
        method: 'Manual',
        workingMinutes: 0,
        lateMinutes: 0,
        earlyExitMinutes: 0,
        overtimeMinutes: 0,
        ruleVersion: 1,
      );
      _attendance.insert(0, localRecord);

      // Add audit log
      _addAuditLog(
        gymId: gymId,
        actionType: 'manual_attendance',
        performedBy: addedBy,
        performedByRole: addedByRole,
        targetUserName: memberName,
        targetUserType: 'Member',
        targetUserId: memberId,
        date: todayStr,
        newStatus: 'Present',
        reason: reason,
      );
    }

    await _storage.setString(
      _attendanceKey,
      jsonEncode(_attendance.map((e) => e.toJson()).toList()),
    );
    await _saveQueuesToStorage();
    notifyListeners();

    // Trigger background sync
    triggerBackgroundSync();
  }

  /// Queues manual staff attendance.
  /// Saves locally first, syncs to cloud automatically when available.
  Future<void> queueManualStaffAttendance({
    required String gymId,
    required String staffId,
    required String? userId,
    required String staffName,
    required String? shiftId,
    required String? shiftName,
    required String checkInIso,
    required String? checkOutIso,
    required String date,
    required String reason,
    required String addedBy,
    required String addedByRole,
  }) async {
    // Duplicate check
    final alreadyQueued = _manualAttendanceQueue.any(
      (e) => e.staffId == staffId && e.date == date,
    );
    final alreadyMarked = _attendance.any(
      (a) => (a.userId == staffId || a.staffId == staffId) && a.date == date && a.status != 'Absent',
    );
    if (alreadyQueued || alreadyMarked) return;

    final uuid = _generateUuidV4();
    final now = DateTime.now();

    final entry = ManualAttendanceEntry(
      operationUuid: uuid,
      gymId: gymId,
      staffId: staffId,
      userId: userId,
      userType: 'Staff',
      userName: staffName,
      status: 'Present',
      date: date,
      checkInIso: checkInIso,
      checkOutIso: checkOutIso,
      shiftId: shiftId,
      shiftName: shiftName,
      reason: reason,
      addedBy: addedBy,
      addedByRole: addedByRole,
      createdAt: now,
      updatedAt: now,
    );

    _manualAttendanceQueue.add(entry);

    // Add to local attendance list immediately
    final checkInLocal = DateTime.parse(checkInIso).toLocal();
    String? checkOutStr;
    if (checkOutIso != null) {
      checkOutStr = DateFormat('hh:mm a').format(DateTime.parse(checkOutIso).toLocal());
    }
    final localRecord = AttendanceRecord(
      id: uuid,
      userId: userId ?? staffId,
      userName: staffName,
      userType: 'Staff',
      checkInTime: DateFormat('hh:mm a').format(checkInLocal),
      checkOutTime: checkOutStr,
      date: date,
      status: 'Present',
      method: 'Manual',
      workingMinutes: 0,
      lateMinutes: 0,
      earlyExitMinutes: 0,
      overtimeMinutes: 0,
      ruleVersion: 1,
      staffId: staffId,
    );
    _attendance.insert(0, localRecord);

    // Add audit log
    _addAuditLog(
      gymId: gymId,
      actionType: 'manual_attendance',
      performedBy: addedBy,
      performedByRole: addedByRole,
      targetUserName: staffName,
      targetUserType: 'Staff',
      targetUserId: staffId,
      date: date,
      newStatus: 'Present',
      newCheckIn: DateFormat('hh:mm a').format(checkInLocal),
      newCheckOut: checkOutStr,
      newShift: shiftName,
      reason: reason,
    );

    await _storage.setString(
      _attendanceKey,
      jsonEncode(_attendance.map((e) => e.toJson()).toList()),
    );
    await _saveQueuesToStorage();
    notifyListeners();

    triggerBackgroundSync();
  }

  // --- Manual Attendance Queue Processing ---

  /// Processes pending manual attendance entries and syncs them to Supabase.
  /// Automatically resolves absent conflicts.
  Future<void> _processManualAttendanceQueue() async {
    if (_manualAttendanceQueue.isEmpty) return;
    if (!SupabaseService.isInitialized) return;

    final List<ManualAttendanceEntry> toProcess = List.from(_manualAttendanceQueue);

    for (final entry in toProcess) {
      if (entry.syncStatus == 'synced' || entry.retryCount > 5) continue;

      entry.syncStatus = 'syncing';
      entry.updatedAt = DateTime.now();
      await _saveQueuesToStorage();

      try {
        // Check if a present record already exists for this member/staff on this date
        final hasPresentOnServer = await _hasPresentRecordOnServer(
          gymId: entry.gymId,
          memberId: entry.memberId,
          staffId: entry.staffId,
          userId: entry.userId,
          date: entry.date,
        );

        if (!hasPresentOnServer) {
          // Resolve absent conflict: remove auto-absent record if exists
          await _resolveAbsentConflict(
            gymId: entry.gymId,
            userId: entry.userId ?? entry.memberId ?? entry.staffId ?? '',
            memberId: entry.memberId,
            staffId: entry.staffId,
            date: entry.date,
          );

          // Upsert the present record
          final data = {
            'id': entry.operationUuid,
            'gym_id': entry.gymId,
            'user_id': entry.userId,
            'member_id': entry.memberId,
            'staff_id': entry.staffId,
            'user_type': entry.userType,
            'role': entry.userType,
            'shift_id': entry.shiftId,
            'date': entry.date,
            'check_in': entry.checkInIso,
            'check_out': entry.checkOutIso,
            'status': entry.status,
            'method': 'Manual',
          };

          await SupabaseService.client.from('attendance_logs').upsert(data);

          // Sync audit log for this entry
          await _syncAuditLogForEntry(entry);
        } else {
          print('Emergency Sync: Duplicate present record already exists on server for [REDACTED] on ${entry.date}. Skipping insert.');
        }

        // Success — remove from queue
        _manualAttendanceQueue.removeWhere((e) => e.operationUuid == entry.operationUuid);
        await _saveQueuesToStorage();
        print('Emergency Sync: Manual attendance ${entry.operationUuid} synced successfully.');
      } catch (e) {
        print('Emergency Sync Error: ${entry.operationUuid}: $e');
        entry.syncStatus = 'failed';
        entry.retryCount++;
        entry.errorMessage = e.toString();
        entry.updatedAt = DateTime.now();
        await _saveQueuesToStorage();

        try {
          await NotificationService.showNotification(
            id: entry.operationUuid.hashCode,
            title: 'Manual Attendance Sync Failed',
            body: 'Failed to sync manual attendance for ${entry.userName}: $e',
          );
        } catch (_) {}
      }
    }
  }

  // --- Auto-Absent Conflict Resolution ---

  /// Resolves absent conflicts: if the server has an auto-generated Absent record
  /// for the same user on the same date, delete it so the Present record takes precedence.
  Future<void> _resolveAbsentConflict({
    required String gymId,
    required String userId,
    String? memberId,
    String? staffId,
    required String date,
  }) async {
    if (!SupabaseService.isInitialized) return;
    try {
      // Check for existing absent record by member_id or user_id
      var query = SupabaseService.client
          .from('attendance_logs')
          .select('id')
          .eq('gym_id', gymId)
          .eq('date', date)
          .eq('status', 'Absent');

      List<dynamic> results;
      if (memberId != null && memberId.isNotEmpty) {
        results = await query.eq('member_id', memberId);
      } else if (staffId != null && staffId.isNotEmpty) {
        results = await query.eq('staff_id', staffId);
      } else if (userId.isNotEmpty) {
        results = await query.eq('user_id', userId);
      } else {
        return;
      }

      for (final record in results) {
        final recordId = record['id'] as String;
        await SupabaseService.client
            .from('attendance_logs')
            .delete()
            .eq('id', recordId);
        print('Absent Conflict Resolved: Removed auto-absent record $recordId');
      }
    } catch (e) {
      print('_resolveAbsentConflict error: $e');
      // Non-fatal: the upsert will still work even if this fails
    }
  }

  /// Helper to check if a Present/Late attendance record already exists for a user on a given date.
  Future<bool> _hasPresentRecordOnServer({
    required String gymId,
    String? memberId,
    String? staffId,
    String? userId,
    required String date,
  }) async {
    if (!SupabaseService.isInitialized) return false;
    try {
      var query = SupabaseService.client
          .from('attendance_logs')
          .select('id')
          .eq('gym_id', gymId)
          .eq('date', date)
          .neq('status', 'Absent');

      List<dynamic> results;
      if (memberId != null && memberId.isNotEmpty) {
        results = await query.eq('member_id', memberId);
      } else if (staffId != null && staffId.isNotEmpty) {
        results = await query.eq('staff_id', staffId);
      } else if (userId != null && userId.isNotEmpty) {
        results = await query.eq('user_id', userId);
      } else {
        return false;
      }
      return results.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // --- Owner Direct Attendance Correction ---

  /// Owner directly corrects an attendance record (no request/review workflow).
  /// Updates local DB immediately and queues cloud update.
  Future<Map<String, dynamic>> ownerCorrectAttendance({
    required String gymId,
    required String logId,
    required String targetUserId,
    required String targetUserName,
    required String targetUserType,
    required String date,
    String? newStatus,
    String? newCheckIn,
    String? newCheckOut,
    String? newShift,
    required String reason,
    required String correctedBy,
  }) async {
    // Find existing local record
    final index = _attendance.indexWhere((a) => a.id == logId);
    String? oldStatus;
    String? oldCheckIn;
    String? oldCheckOut;
    String? oldShift;

    if (index >= 0) {
      final existing = _attendance[index];
      oldStatus = existing.status;
      oldCheckIn = existing.checkInTime;
      oldCheckOut = existing.checkOutTime;
      oldShift = existing.shiftStatus;

      // Update local record
      _attendance[index] = existing.copyWith(
        status: newStatus ?? existing.status,
        checkInTime: newCheckIn ?? existing.checkInTime,
        checkOutTime: newCheckOut ?? existing.checkOutTime,
        shiftStatus: newShift ?? existing.shiftStatus,
      );

      await _storage.setString(
        _attendanceKey,
        jsonEncode(_attendance.map((e) => e.toJson()).toList()),
      );
    }

    // Add audit log
    _addAuditLog(
      gymId: gymId,
      actionType: 'attendance_correction',
      performedBy: correctedBy,
      performedByRole: 'Owner',
      targetUserName: targetUserName,
      targetUserType: targetUserType,
      targetUserId: targetUserId,
      date: date,
      oldStatus: oldStatus,
      newStatus: newStatus,
      oldCheckIn: oldCheckIn,
      newCheckIn: newCheckIn,
      oldCheckOut: oldCheckOut,
      newCheckOut: newCheckOut,
      oldShift: oldShift,
      newShift: newShift,
      reason: reason,
    );

    // Queue cloud update via CRUD queue
    final existing = index >= 0 ? _attendance[index] : null;

    String? formatToIso(String? timeStr) {
      if (timeStr == null || timeStr.isEmpty) return null;
      try {
        final parsed = DateFormat('hh:mm a').parse(timeStr);
        final dateObj = DateFormat('dd-MM-yyyy').parse(date);
        final fullDt = DateTime(dateObj.year, dateObj.month, dateObj.day, parsed.hour, parsed.minute);
        return fullDt.toUtc().toIso8601String();
      } catch (_) {
        try {
          DateTime.parse(timeStr);
          return timeStr;
        } catch (_) {
          return null;
        }
      }
    }

    final rawShift = newShift ?? existing?.shiftStatus;
    final validShiftId = _isValidUUID(rawShift) ? rawShift : null;
    final shiftStatusVal = !_isValidUUID(rawShift) ? rawShift : (existing?.shiftStatus);

    final updatePayload = <String, dynamic>{
      'id': logId,
      'gym_id': gymId,
      'user_id': (existing?.userId != null && _isValidUUID(existing!.userId)) ? existing.userId : null,
      'role': existing?.userType ?? targetUserType,
      'user_type': existing?.userType ?? targetUserType,
      'member_id': (existing?.userType ?? targetUserType) == 'Member' && _isValidUUID(existing?.userId ?? targetUserId) ? (existing?.userId ?? targetUserId) : null,
      'staff_id': (existing?.userType ?? targetUserType) == 'Staff' && _isValidUUID(existing?.staffId ?? existing?.userId ?? targetUserId) ? (existing?.staffId ?? existing?.userId ?? targetUserId) : null,
      'date': existing?.date ?? date,
      'status': newStatus ?? existing?.status ?? 'Present',
      'method': existing?.method ?? 'Manual',
      if (validShiftId != null) 'shift_id': validShiftId,
      if (shiftStatusVal != null && shiftStatusVal.isNotEmpty) 'shift_status': shiftStatusVal,
      'check_in': formatToIso(newCheckIn ?? existing?.checkInTime) ?? DateTime.now().toUtc().toIso8601String(),
      'check_out': formatToIso(newCheckOut ?? existing?.checkOutTime),
    };

    // Try direct Supabase update first to avoid unnecessary queueing
    bool isDirectlyUpdated = false;
    if (SupabaseService.isInitialized) {
      try {
        final id = updatePayload['id'] as String;
        final updateData = Map<String, dynamic>.from(updatePayload)..remove('id')..remove('uuid');
        await SupabaseService.client.from('attendance_logs').update(updateData).eq('id', id);
        isDirectlyUpdated = true;
      } catch (e) {
        print('correctAttendanceLog direct update failed, queueing: $e');
      }
    }

    if (!isDirectlyUpdated) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'attendance_logs',
        'action': 'update',
        'payload': updatePayload,
        'sync_status': 'pending',
        'retry_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
    notifyListeners();

    return {'success': true, 'message': 'Attendance corrected successfully'};
  }

  // --- Audit Log Methods ---

  /// Adds an audit log entry locally (and queues for cloud sync).
  void _addAuditLog({
    required String gymId,
    required String actionType,
    required String performedBy,
    required String performedByRole,
    required String targetUserName,
    required String targetUserType,
    required String targetUserId,
    required String date,
    String? oldStatus,
    String? newStatus,
    String? oldCheckIn,
    String? newCheckIn,
    String? oldCheckOut,
    String? newCheckOut,
    String? oldShift,
    String? newShift,
    required String reason,
  }) {
    final log = AttendanceAuditLog(
      id: _generateUuidV4(),
      gymId: gymId,
      actionType: actionType,
      performedBy: performedBy,
      performedByRole: performedByRole,
      targetUserName: targetUserName,
      targetUserType: targetUserType,
      targetUserId: targetUserId,
      date: date,
      oldStatus: oldStatus,
      newStatus: newStatus,
      oldCheckIn: oldCheckIn,
      newCheckIn: newCheckIn,
      oldCheckOut: oldCheckOut,
      newCheckOut: newCheckOut,
      oldShift: oldShift,
      newShift: newShift,
      reason: reason,
      createdAt: DateTime.now(),
    );

    _auditLogs.insert(0, log);
    _saveAuditLogsToStorage();
  }

  /// Retrieves audit logs, optionally filtered by date and user type.
  List<AttendanceAuditLog> getAuditLogs({String? date, String? userType}) {
    return _auditLogs.where((log) {
      if (date != null && log.date != date) return false;
      if (userType != null && log.targetUserType != userType) return false;
      return true;
    }).toList();
  }

  /// Syncs a single audit log entry to the cloud.
  Future<void> _syncAuditLogForEntry(ManualAttendanceEntry entry) async {
    if (!SupabaseService.isInitialized) return;
    try {
      // Find audit logs related to this entry
      final relatedLogs = _auditLogs.where((log) =>
        log.targetUserId == (entry.memberId ?? entry.staffId ?? '') &&
        log.date == entry.date &&
        log.actionType == 'manual_attendance'
      );

      for (final log in relatedLogs) {
        try {
          await SupabaseService.client.from('attendance_audit_log').upsert(log.toJson());
        } catch (e) {
          print('Audit log sync error: $e');
          // Non-fatal: audit log sync failure should not block attendance sync
        }
      }
    } catch (e) {
      print('_syncAuditLogForEntry error: $e');
    }
  }

  /// Returns members who have NOT been marked present today.
  /// Used by Emergency Member Attendance screen.
  List<Map<String, dynamic>> getUnmarkedMembersToday() {
    final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

    // Get IDs of members already marked (from local attendance + manual queue)
    final markedIds = <String>{};
    for (final a in _attendance) {
      if (a.date == todayStr && a.userType == 'Member' && a.status != 'Absent') {
        markedIds.add(a.userId);
      }
    }
    for (final e in _manualAttendanceQueue) {
      if (e.date == todayStr && e.userType == 'Member') {
        if (e.memberId != null) markedIds.add(e.memberId!);
      }
    }

    final allMembers = getOfflineMembers();
    return allMembers.where((m) {
      final id = m['id'] as String;
      final status = m['status'] as String? ?? '';
      return status == 'Active' && !markedIds.contains(id);
    }).toList();
  }

  // ===================================================================
  // END EMERGENCY ATTENDANCE RECOVERY SYSTEM
  // ===================================================================

  LocalStorageService get storage => _storage;

  bool get isInitialSyncComplete {
    final gymId = _storage.getGymInfo()?['id'] ?? 'default';
    return _storage.getBool('${LocalStorageService.keyInitialSyncComplete}_$gymId') ?? false;
  }

  Future<void> setInitialSyncComplete(bool value) async {
    final gymId = _storage.getGymInfo()?['id'] ?? 'default';
    await _storage.setBool('${LocalStorageService.keyInitialSyncComplete}_$gymId', value);
    notifyListeners();
  }

  bool _isSyncingInitial = false;
  bool get isSyncingInitial => _isSyncingInitial;

  Future<void> performInitialSync(String gymId) async {
    if (_isSyncingInitial) return;
    _isSyncingInitial = true;
    notifyListeners();

    try {
      print('Starting initial offline-first sync for gym $gymId...');
      
      await Future.wait([
        fetchMembersFromSupabase(),
        fetchTrialMembersFromSupabase(),
        fetchStaffFromSupabase(),
        fetchTransactionsFromSupabase(),
        fetchAttendanceLogsFromSupabase(),
        fetchAttendanceSettingsFromSupabase(),
        fetchGymShiftSettingsFromSupabase(gymId),
        fetchGoalsFromSupabase(),
        fetchCustomFieldsFromSupabase(),
        fetchRecentActivitiesFromSupabase(),
        fetchDisplaySessionsFromSupabase(),
        fetchWorkoutsFromSupabase(),
        fetchDietsFromSupabase(),
        fetchMembershipsFromSupabase(),
        fetchOwnerDashboardStats(gymId),
      ]);

      await Future.wait([
        fetchSalaryDraftsFromSupabase(gymId),
        fetchAttendanceAlerts(gymId),
        fetchAttendanceCorrections(gymId),
      ]);

      await setInitialSyncComplete(true);
      print('Initial sync completed successfully for gym $gymId.');
    } catch (e) {
      print('Initial sync failed: $e');
    } finally {
      _isSyncingInitial = false;
      notifyListeners();
    }
  }

  Future<void> reloadForActiveGym() async {
    _loadAllFromStorage();
    
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId != null) {
      if (!isInitialSyncComplete) {
        await performInitialSync(gymId);
      } else {
        // Run verification pulls in the background silently
        _runBackgroundVerification();
      }
    }
  }

  // Initial load
  void _loadAllFromStorage() {
    _loadMembers();
    _loadStaff();
    _loadWorkouts();
    _loadDiets();
    _loadMemberships();
    _loadTransactions();
    _loadAttendance();
    _loadGoals();
    _loadCustomFields();
    _loadSalaryAdvances();
    _loadSalaryDrafts();
    _loadLeaveRequests();
    _loadAttendanceSettings();
    _loadShiftSettings();
    _loadDashboardStats();
    _loadReportsAnalytics();
    _loadRecentActivities();
    _loadAlerts();
    _loadCorrections();
  }

  void _loadRecentActivities() {
    final raw = _storage.getString(_recentActivitiesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        _recentActivities = decoded.map((e) => RecentActivity.fromJson(e)).toList();
      } catch (_) {}
    } else {
      _recentActivities = [];
    }
  }

  void _loadAlerts() {
    final raw = _storage.getString(_alertsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        _alerts = decoded.map((e) => AttendanceAlert.fromJson(e)).toList();
      } catch (_) {
        _alerts = [];
      }
    } else {
      _alerts = [];
    }
  }

  void _loadCorrections() {
    final raw = _storage.getString(_correctionsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        _corrections = decoded.map((e) => AttendanceCorrectionRequest.fromJson(e)).toList();
      } catch (_) {
        _corrections = [];
      }
    } else {
      _corrections = [];
    }
  }

  Future<void> _saveRecentActivitiesToStorage() async {
    try {
      await _storage.setString(_recentActivitiesKey, jsonEncode(_recentActivities.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void _loadReportsAnalytics() {
    final raw = _storage.getString(_reportsAnalyticsKey);
    if (raw != null) {
      try {
        _reportsAnalytics = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        _reportsAnalytics = {};
      }
    } else {
      _reportsAnalytics = {};
    }
  }

  void _loadAttendanceSettings() {
    final raw = _storage.getString(_attendanceSettingsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _attendanceSettings = GymAttendanceSettings.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
  }

  void _loadDashboardStats() {
    final raw = _storage.getString(_dashboardStatsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _dashboardStats = Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {
        _dashboardStats = {};
      }
    } else {
      _dashboardStats = {};
    }
  }

  void _loadShiftSettings() {
    _shiftMode = _storage.getString(_gymShiftSettingsKey) ?? 'Single Shift';
    final rawShifts = _storage.getString(_gymShiftsListKey);
    if (rawShifts != null && rawShifts.isNotEmpty) {
      try {
        _shiftsList = List<Map<String, dynamic>>.from(jsonDecode(rawShifts));
      } catch (_) {
        _shiftsList = [];
      }
    } else {
      _shiftsList = [];
    }
  }

  void _loadSalaryAdvances() {
    final raw = _storage.getString(_salaryAdvancesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _salaryAdvances = List<Map<String, dynamic>>.from(jsonDecode(raw));
      } catch (_) {
        _salaryAdvances = [];
      }
    } else {
      _salaryAdvances = [];
    }
  }

  void _loadSalaryDrafts() {
    final raw = _storage.getString(_salaryDraftsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _salaryDrafts = List<Map<String, dynamic>>.from(jsonDecode(raw));
      } catch (_) {
        _salaryDrafts = [];
      }
    } else {
      _salaryDrafts = [];
    }
  }

  void _loadLeaveRequests() {
    final raw = _storage.getString(_leaveRequestsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _leaveRequests = List<Map<String, dynamic>>.from(jsonDecode(raw));
      } catch (_) {
        _leaveRequests = [];
      }
    } else {
      _leaveRequests = [];
    }
  }

  // --- Members ---
  List<Member> getMembers() => List.unmodifiable(_members);
  List<TrialMember> getTrialMembers() => List.unmodifiable(_trialMembers);

  void _loadMembers() {
    final raw = _storage.getString(_membersKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        _members = decoded.map((e) => Member.fromJson(e)).toList();
        _lastMembersRaw = raw;
      } catch (e) {
        _members = [];
      }
    } else {
      _members = [];
    }

    final rawTrial = _storage.getString(_trialMembersKey);
    if (rawTrial != null && rawTrial.isNotEmpty) {
      try {
        final List decoded = jsonDecode(rawTrial);
        _trialMembers = decoded.map((e) => TrialMember.fromJson(e)).toList();
        _lastTrialMembersRaw = rawTrial;
      } catch (e) {
        _trialMembers = [];
      }
    } else {
      _trialMembers = [];
    }
  }

  Future<void> checkSubscriptionLimit(String type) async {
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) return;

    if (!SupabaseService.isInitialized) return;

    try {
      final res = await SupabaseService.client
          .from('subscriptions')
          .select('plan_id, status, subscription_plans(max_members, max_staff)')
          .eq('gym_id', gymId)
          .maybeSingle();

      if (res != null) {
        final status = res['status'] as String;
        final planId = res['plan_id'] as String;
        final plan = res['subscription_plans'] as Map<String, dynamic>?;

        if (status == 'expired' || status == 'cancelled' || status == 'failed_payment') {
          throw Exception('limit_reached:Your subscription status is ${status.toUpperCase()}. Plan tiers are managed by your account administrator.');
        }

        if (plan != null) {
          if (type == 'member') {
            final maxMembers = plan['max_members'] as int?;
            // A maxMembers value of null, -1, or <= 0 indicates unlimited members
            if (maxMembers != null && maxMembers > 0) {
              final currentMembers = _members.length;
              if (currentMembers >= maxMembers) {
                throw Exception('limit_reached:Your plan allows a maximum of $maxMembers members. Plan capacity is managed by your account administrator.');
              }
            }
          } else if (type == 'staff') {
            final maxStaff = plan['max_staff'] as int?;
            // A maxStaff value of null, -1, or <= 0 indicates unlimited staff
            if (maxStaff != null && maxStaff > 0) {
              final currentStaff = _staff.length;
              if (currentStaff >= maxStaff) {
                throw Exception('limit_reached:Your plan allows a maximum of $maxStaff staff members. Plan capacity is managed by your account administrator.');
              }
            }
          }
        }
      }
    } catch (e) {
      if (e.toString().contains('limit_reached:')) {
        rethrow;
      }
    }
  }

  Future<void> saveMember(Member member) async {
    if (!_isValidUUID(member.id)) {
      throw Exception('Invalid member ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) {
      throw Exception('Active Gym ID not found. Please select or create a gym.');
    }

    final index = _members.indexWhere((m) => m.id == member.id);
    if (index == -1) {
      await checkSubscriptionLimit('member');
    }

    // 1. Immediately update local state & cache
    if (index >= 0) {
      _members[index] = member;
    } else {
      _members.insert(0, member);
    }
    await _storage.setString(_membersKey, jsonEncode(_members.map((e) => e.toJson()).toList()));
    notifyListeners();

    // 2. Queue Member save payload for sync
    final bool isUpdate = index >= 0;
    final Map<String, dynamic> data = {
      'id': member.id,
      'gym_id': gymId,
      'name': member.name,
      'email': member.email,
      'phone': member.phone,
      'status': member.status,
      'join_date': member.joinDate,
      'avatar': member.avatar,
      'membership_plan_id': (member.membershipPlanId.isNotEmpty && member.membershipPlanId != 'null') ? member.membershipPlanId : null,
      'pt_member': member.ptMember,
      'pt_trainer': _isValidUUID(member.ptTrainer) ? member.ptTrainer : null,
      'assigned_workout_id': _isValidUUID(member.assignedWorkoutId) ? member.assignedWorkoutId : null,
      'assigned_diet_id': _isValidUUID(member.assignedDietId) ? member.assignedDietId : null,
      'medical_details': member.medicalDetails,
      'notes': member.notes,
      'pending_amount': member.pendingAmount,
      'discount_amount': member.discountAmount,
      'total_received_amount': member.totalReceivedAmount,
      'payment_status': member.paymentStatus,
      'extra_fields': member.extraFields,
    };

    // Direct Supabase update or insert when online
    bool isDirectlyInserted = false;
    if (SupabaseService.isInitialized) {
      try {
        if (isUpdate) {
          final updatePayload = Map<String, dynamic>.from(data)..remove('id')..remove('gym_id');
          await SupabaseService.client.from('members').update(updatePayload).eq('id', member.id);
        } else {
          await SupabaseService.client.from('members').insert(data);
        }
        isDirectlyInserted = true;
        _lastMembersRaw = ''; // Reset cache signature so next fetch updates cleanly
      } catch (e) {
        print('saveMember direct Supabase operation skipped/failed: $e. Fallback to queue.');
      }
    }

    // Only queue if direct insert/update failed (prevents double-queueing)
    if (!isDirectlyInserted) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'members',
        'action': isUpdate ? 'update' : 'insert',
        'payload': data,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
    }

    // 3. Queue PT assignment update offline if applicable
    if (member.ptMember && _isValidUUID(member.ptTrainer)) {
      final matchingStaff = _staff.where((s) => s.id == member.ptTrainer).toList();
      final commissionPercentage = matchingStaff.isNotEmpty ? matchingStaff.first.commissionPercentage : 0.0;

      if (!isDirectlyInserted) {
        _crudQueue.add({
          'uuid': _generateUuidV4(),
          'table': 'pt_assignments',
          'action': 'insert',
          'payload': {
            'gym_id': gymId,
            'member_id': member.id,
            'staff_id': member.ptTrainer,
            'commission_percentage': commissionPercentage,
            'assignment_status': 'Active',
            'pt_start_date': DateTime.now().toIso8601String().substring(0, 10),
          },
          'created_at': DateTime.now().toIso8601String(),
          'retry_count': 0,
          'error_message': null,
        });
      } else {
        // Direct insert succeeded for member, also try PT assignment directly
        try {
          await SupabaseService.client.from('pt_assignments').upsert({
            'gym_id': gymId,
            'member_id': member.id,
            'staff_id': member.ptTrainer,
            'commission_percentage': commissionPercentage,
            'assignment_status': 'Active',
            'pt_start_date': DateTime.now().toIso8601String().substring(0, 10),
          });
        } catch (e) {
          print('saveMember direct PT assignment upsert failed, queueing: $e');
          _crudQueue.add({
            'uuid': _generateUuidV4(),
            'table': 'pt_assignments',
            'action': 'insert',
            'payload': {
              'gym_id': gymId,
              'member_id': member.id,
              'staff_id': member.ptTrainer,
              'commission_percentage': commissionPercentage,
              'assignment_status': 'Active',
              'pt_start_date': DateTime.now().toIso8601String().substring(0, 10),
            },
            'created_at': DateTime.now().toIso8601String(),
            'retry_count': 0,
            'error_message': null,
          });
        }
      }
    }

    if (!isDirectlyInserted) {
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  /// Save an old/imported member WITHOUT creating PT assignment or commission entries.
  /// Used for pre-existing member data import where finance and commission
  /// should NOT be affected.
  Future<void> saveOldMember(Member member) async {
    if (!_isValidUUID(member.id)) {
      throw Exception('Invalid member ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) {
      throw Exception('Active Gym ID not found. Please select or create a gym.');
    }

    final index = _members.indexWhere((m) => m.id == member.id);
    if (index == -1) {
      await checkSubscriptionLimit('member');
    }

    // 1. Immediately update local state & cache
    if (index >= 0) {
      _members[index] = member;
    } else {
      _members.insert(0, member);
    }
    await _storage.setString(_membersKey, jsonEncode(_members.map((e) => e.toJson()).toList()));
    notifyListeners();

    // 2. Queue Member save payload for sync
    final Map<String, dynamic> data = {
      'id': member.id,
      'gym_id': gymId,
      'name': member.name,
      'phone': member.phone,
      'status': member.status,
      'join_date': member.joinDate,
      'avatar': member.avatar,
      'membership_plan_id': member.membershipPlanId,
      'pt_member': member.ptMember,
      'pt_trainer': _isValidUUID(member.ptTrainer) ? member.ptTrainer : null,
      'assigned_workout_id': _isValidUUID(member.assignedWorkoutId) ? member.assignedWorkoutId : null,
      'assigned_diet_id': _isValidUUID(member.assignedDietId) ? member.assignedDietId : null,
      'medical_details': member.medicalDetails,
      'notes': member.notes,
      'pending_amount': member.pendingAmount,
      'discount_amount': member.discountAmount,
      'total_received_amount': member.totalReceivedAmount,
      'payment_status': member.paymentStatus,
      'extra_fields': member.extraFields,
    };

    // Direct Supabase upsert when online
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('members').upsert(data);
      } catch (e) {
        print('saveOldMember direct Supabase upsert skipped/failed: $e. Fallback to queue.');
      }
    }

    _crudQueue.add({
      'uuid': _generateUuidV4(),
      'table': 'members',
      'action': 'insert',
      'payload': data,
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
      'error_message': null,
    });

    // NOTE: PT assignment queue is intentionally SKIPPED for old members
    // to avoid generating commission ledger entries for historical data.

    await _saveQueuesToStorage();
    triggerBackgroundSync();
  }

  Future<void> updateMemberPtAssignment({
    required String memberId,
    required bool ptMember,
    required String ptTrainerId,
    required double commissionPercentage,
  }) async {
    final gymId = _storage.getGymInfo()?['id'];
    final memberIndex = _members.indexWhere((m) => m.id == memberId);
    if (memberIndex >= 0) {
      final oldMember = _members[memberIndex];
      final updatedMember = oldMember.copyWith(
        ptMember: ptMember,
        ptTrainer: ptTrainerId,
      );
      _members[memberIndex] = updatedMember;
      await _storage.setString(_membersKey, jsonEncode(_members.map((e) => e.toJson()).toList()));
      notifyListeners();
    }

    final payload = {
      'p_gym_id': gymId,
      'p_member_id': memberId,
      'p_pt_member': ptMember,
      'p_staff_id': _isValidUUID(ptTrainerId) ? ptTrainerId : null,
      'p_commission_percentage': commissionPercentage,
    };

    bool isDirectlyDone = false;
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.rpc('change_member_pt', params: payload);
        isDirectlyDone = true;
      } catch (e) {
        print('updateMemberPtAssignment RPC skipped/failed: $e. Fallback to queue.');
      }
    }

    if (!isDirectlyDone) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'rpc_change_member_pt',
        'action': 'rpc',
        'payload': payload,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });

      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  /// Queue an update to member_memberships to keep paid_amount in sync
  /// with app-side payment tracking. This prevents the DB trigger
  /// fn_sync_member_payment_status from overwriting members.total_received_amount
  /// with stale data on app restart.
  Future<void> updateMemberMembershipPayment({
    required String memberId,
    required double paymentAmount,
    required double newTotalReceived,
    required double newPendingAmount,
  }) async {
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null || !_isValidUUID(memberId)) return;

    // Try direct RPC call first, only queue on failure
    final rpcPayload = {
      'p_member_id': memberId,
      'p_gym_id': gymId,
      'p_payment_amount': paymentAmount,
      'p_new_total_received': newTotalReceived,
      'p_new_pending_amount': newPendingAmount,
    };

    bool isDirectlyDone = false;
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.rpc('sync_member_payment_amounts', params: rpcPayload);
        isDirectlyDone = true;
      } catch (e) {
        print('updateMemberMembershipPayment direct RPC failed, queueing: $e');
      }
    }

    if (!isDirectlyDone) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'rpc_sync_member_payment_amounts',
        'action': 'rpc',
        'payload': rpcPayload,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
    }
  }

  Future<void> saveTrialMember(TrialMember trial) async {
    if (!SupabaseService.isInitialized) {
      throw Exception('Supabase client is not initialized.');
    }
    if (!_isValidUUID(trial.id)) {
      throw Exception('Invalid trial ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) {
      throw Exception('Active Gym ID not found.');
    }
    try {
      final Map<String, dynamic> data = trial.toJson();
      data['gym_id'] = gymId;
      await SupabaseService.client.from('trial_members').upsert(data);
      await fetchTrialMembersFromSupabase();
    } catch (e) {
      print('Supabase saveTrialMember error: $e');
      throw Exception('Failed to save trial member: $e');
    }
  }

  Future<void> updateTrialStatus(String trialId, String status) async {
    if (!SupabaseService.isInitialized || !_isValidUUID(trialId)) return;
    try {
      await SupabaseService.client
          .from('trial_members')
          .update({'status': status})
          .eq('id', trialId);
      await fetchTrialMembersFromSupabase();
    } catch (e) {
      print('Supabase updateTrialStatus error: $e');
    }
  }

  Future<void> fetchTrialMembersFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('trial_members')
              .select()
              .eq('gym_id', gymId);
          _resetNetworkError();
          final responseStr = jsonEncode(response);
          if (responseStr != _lastTrialMembersRaw) {
            _lastTrialMembersRaw = responseStr;
            _trialMembers = response.map((e) => TrialMember.fromJson(e)).toList();
            await _storage.setString(_trialMembersKey, responseStr);
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchTrialMembersFromSupabase', e);
        }
      }
    }
  }

  bool _isValidUUID(String? str) {
    if (str == null || str.isEmpty) return false;
    final regExp = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return regExp.hasMatch(str);
  }

  String _sanitizeCategory(String category) {
    switch (category) {
      case 'Membership Fee':
        return 'Membership';
      case 'Supplements':
        return 'Protein Sale';
      case 'Locker Fee':
        return 'Locker Rent';
      case 'Other Income':
        return 'Other';
      case 'Salaries':
        return 'Salary';
      case 'Equipment':
        return 'Maintenance';
      case 'Other Expense':
        return 'Other';
      default:
        return category;
    }
  }

  Future<void> deleteMember(String id, {String deleteScope = 'profile_only'}) async {
    if (!_isValidUUID(id)) {
      throw Exception('Invalid member ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];

    // 1. Remove from local list and save to storage
    _members.removeWhere((m) => m.id == id);
    await _storage.setString(_membersKey, jsonEncode(_members.map((e) => e.toJson()).toList()));

    // Clean up local cached attendance & transactions if scope is 'all'
    if (deleteScope == 'all') {
      _attendance.removeWhere((a) => a.userId == id);
      await _storage.setString(_attendanceKey, jsonEncode(_attendance.map((e) => e.toJson()).toList()));

      _transactions.removeWhere((tx) => tx.referenceId == id);
      await _storage.setString(_transactionsKey, jsonEncode(_transactions.map((e) => e.toJson()).toList()));
    }

    notifyListeners();

    // 2. Safe Archive Delete via RPC if online
    bool isDirectlyDeleted = false;
    if (SupabaseService.isInitialized && gymId != null) {
      try {
        final res = await SupabaseService.client.rpc('admin_archive_delete_member', params: {
          'p_member_id': id,
          'p_gym_id': gymId,
          'p_delete_scope': deleteScope,
        });
        if (res != null && (res as Map)['success'] == true) {
          isDirectlyDeleted = true;
        }
      } catch (e) {
        print('admin_archive_delete_member RPC skipped/failed: $e. Fallback to direct delete.');
        try {
          await SupabaseService.client
              .from('members')
              .delete()
              .eq('id', id)
              .eq('gym_id', gymId);
          isDirectlyDeleted = true;
        } catch (e2) {
          print('deleteMember direct Supabase delete failed: $e2');
        }
      }
    }

    // 3. Queue delete operation only if direct delete failed
    if (!isDirectlyDeleted) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'members',
        'action': 'delete',
        'payload': {
          'id': id,
          if (gymId != null) 'gym_id': gymId,
          'delete_scope': deleteScope,
        },
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  // --- Staff ---
  List<Staff> getStaff() => List.unmodifiable(_staff);

  void _loadStaff() {
    final raw = _storage.getString(_staffKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        _staff = decoded.map((e) => Staff.fromJson(e)).toList();
        _lastStaffRaw = raw;
      } catch (e) {
        _staff = [];
      }
    } else {
      _staff = [];
    }
  }

  Future<void> saveStaff(Staff staff) async {
    if (!_isValidUUID(staff.id)) {
      throw Exception('Invalid staff ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) {
      throw Exception('Active Gym ID not found. Please select or create a gym.');
    }

    final index = _staff.indexWhere((s) => s.id == staff.id);
    if (index == -1) {
      await checkSubscriptionLimit('staff');
    }

    // 1. Immediately update local state & cache
    if (index >= 0) {
      _staff[index] = staff;
    } else {
      _staff.insert(0, staff);
    }
    await _storage.setString(_staffKey, jsonEncode(_staff.map((e) => e.toJson()).toList()));
    notifyListeners();

    // 2. Queue Staff save payload for sync
    final Map<String, dynamic> data = {
      'id': staff.id,
      'gym_id': gymId,
      'name': staff.name,
      'email': staff.email,
      'phone': staff.phone,
      'role': staff.role,
      'department': staff.department,
      'status': staff.status,
      'avatar': staff.avatar,
      'join_date': staff.joinDate,
      'shift': staff.shift,
      'shift_type': staff.shiftType,
      'shift1_start': staff.shift1Start,
      'shift1_end': staff.shift1End,
      'shift2_start': staff.shift2Start,
      'shift2_end': staff.shift2End,
      'experience': staff.experience,
      'rating': staff.rating,
      'sessions_count': staff.sessionsCount,
      'members_trained_count': staff.membersTrained,
      'salary': staff.salary,
      'salary_due': staff.salaryDue,
      'gender': staff.gender,
      'dob': staff.dob,
      'aadhaar': staff.aadhaar,
      'emergency_name': staff.emergencyName,
      'emergency_phone': staff.emergencyPhone,
      'address': staff.address,
      'employment_type': staff.employmentType,
      'salary_type': staff.salaryType,
      'commission_percentage': staff.commissionPercentage,
      'qualification': staff.qualification,
      'notes': staff.notes,
    };

    // Direct Supabase update or insert when online
    final bool isUpdate = index >= 0;
    bool isDirectlyInserted = false;
    if (SupabaseService.isInitialized) {
      try {
        if (isUpdate) {
          final updatePayload = Map<String, dynamic>.from(data)..remove('id')..remove('gym_id');
          await SupabaseService.client.from('staff').update(updatePayload).eq('id', staff.id);
        } else {
          await SupabaseService.client.from('staff').insert(data);
        }
        isDirectlyInserted = true;
        _lastStaffRaw = ''; // Reset cache signature so next fetch updates cleanly
      } catch (e) {
        print('saveStaff direct Supabase operation skipped/failed: $e. Fallback to queue.');
      }
    }

    // Only queue if direct insert/update failed (prevents double-queueing)
    if (!isDirectlyInserted) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'staff',
        'action': isUpdate ? 'update' : 'insert',
        'payload': data,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
    }

    // 3. Queue staff shift assignment
    String mappedAssignmentType = 'Single Shift';
    final lowerShift = staff.shift.toLowerCase();
    if (staff.shiftType == 'both' || lowerShift.contains('both')) {
      mappedAssignmentType = 'Both Shifts';
    } else if (lowerShift.contains('morning')) {
      mappedAssignmentType = 'Morning Shift';
    } else if (lowerShift.contains('evening')) {
      mappedAssignmentType = 'Evening Shift';
    }

    final shiftPayload = {
      'staff_id': staff.id,
      'gym_id': gymId,
      'assignment_type': mappedAssignmentType,
      'effective_from': DateTime.now().toLocal().toIso8601String().substring(0, 10),
      'status': 'Active',
    };

    if (isDirectlyInserted) {
      // Staff already on server, try shift assignment directly too
      try {
        await SupabaseService.client.from('staff_shift_assignments').upsert(shiftPayload);
      } catch (e) {
        print('saveStaff direct shift assignment upsert failed, queueing: $e');
        _crudQueue.add({
          'uuid': _generateUuidV4(),
          'table': 'staff_shift_assignments',
          'action': 'insert',
          'payload': shiftPayload,
          'created_at': DateTime.now().toIso8601String(),
          'retry_count': 0,
          'error_message': null,
        });
      }
    } else {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'staff_shift_assignments',
        'action': 'insert',
        'payload': shiftPayload,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
    }

    if (!isDirectlyInserted) {
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  Future<void> deleteStaff(String id) async {
    if (!_isValidUUID(id)) {
      throw Exception('Invalid staff ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];

    // 1. Remove from local list and save to storage
    _staff.removeWhere((s) => s.id == id);
    await _storage.setString(_staffKey, jsonEncode(_staff.map((e) => e.toJson()).toList()));

    // Clean up local cached attendance
    _attendance.removeWhere((a) => a.staffId == id || a.userId == id);
    await _storage.setString(_attendanceKey, jsonEncode(_attendance.map((e) => e.toJson()).toList()));

    notifyListeners();

    // 2. Direct Supabase delete if online
    bool isDirectlyDeleted = false;
    if (SupabaseService.isInitialized && gymId != null) {
      try {
        await SupabaseService.client
            .from('staff')
            .delete()
            .eq('id', id)
            .eq('gym_id', gymId);
        isDirectlyDeleted = true;
      } catch (e) {
        print('deleteStaff direct Supabase delete skipped/failed: $e. Fallback to queue.');
      }
    }

    // 3. Queue delete operation only if direct delete failed
    if (!isDirectlyDeleted) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'staff',
        'action': 'delete',
        'payload': {
          'id': id,
          if (gymId != null) 'gym_id': gymId,
        },
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  // --- Workouts ---
  List<WorkoutPlan> getWorkouts() => List.unmodifiable(_workouts);

  void _loadWorkouts() {
    final raw = _storage.getString(_workoutsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        _workouts = decoded.map((e) => WorkoutPlan.fromJson(e)).toList();
      } catch (e) {
        _workouts = [];
      }
    } else {
      _workouts = [];
    }
  }

  Future<void> fetchWorkoutsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('workout_plans')
              .select()
              .eq('gym_id', gymId);
          _resetNetworkError();
          final responseStr = jsonEncode(response);
          if (responseStr != _lastWorkoutsRaw) {
            _lastWorkoutsRaw = responseStr;
            _workouts = response.map((e) => WorkoutPlan.fromJson(e)).toList();
            await _storage.setString(_workoutsKey, responseStr);
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchWorkoutsFromSupabase', e);
        }
      }
    }
  }

  Future<void> fetchDietsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('diet_plans')
              .select()
              .eq('gym_id', gymId);
          _resetNetworkError();
          final responseStr = jsonEncode(response);
          if (responseStr != _lastDietsRaw || _diets.isEmpty) {
            _lastDietsRaw = responseStr;
            _diets = response.map((e) => DietPlan.fromJson(Map<String, dynamic>.from(e as Map))).toList();
            await _storage.setString(_dietsKey, responseStr);
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchDietsFromSupabase', e);
        }
      }
    }
  }

  Future<void> fetchMembershipsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('membership_plans')
              .select()
              .eq('gym_id', gymId);
          _resetNetworkError();
          final responseStr = jsonEncode(response);
          if (responseStr != _lastMembershipsRaw) {
            _lastMembershipsRaw = responseStr;
            _memberships = response.map((e) => MembershipPlan.fromJson(e)).toList();
            await _storage.setString(_membershipsKey, responseStr);
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchMembershipsFromSupabase', e);
        }
      }
    }
  }

  Future<String?> saveWorkout(WorkoutPlan workout) async {
    final gymId = _storage.getGymInfo()?['id'];

    if (SupabaseService.isInitialized && gymId != null) {
      try {
        // Build schedule JSON manually for jsonb column
        final Map<String, dynamic> scheduleJson = {};
        workout.schedule.forEach((day, exercises) {
          scheduleJson[day] = exercises.map((e) => {'title': e.title, 'description': e.description}).toList();
        });

        final data = <String, dynamic>{
          'id': workout.id,
          'gym_id': gymId,
          'title': workout.title,
          'description': workout.description,
          'goal': workout.goal,
          'difficulty': workout.difficulty,
          'schedule': scheduleJson,
        };
        print('saveWorkout: Attempting upsert with id=${workout.id}, gym_id=$gymId');
        await SupabaseService.client.from('workout_plans').upsert(data);
        print('saveWorkout: SUCCESS');

        final index = _workouts.indexWhere((e) => e.id == workout.id);
        if (index >= 0) {
          _workouts[index] = workout;
        } else {
          _workouts.add(workout);
        }
        _lastWorkoutsRaw = jsonEncode(_workouts.map((e) => e.toJson()).toList());
        await _storage.setString(_workoutsKey, _lastWorkoutsRaw!);
        notifyListeners();
        return null; // success
      } catch (e) {
        print('saveWorkout: FAILED - $e');
        return 'Database error: $e';
      }
    } else {
      final reason = !SupabaseService.isInitialized
          ? 'Supabase not initialized'
          : 'Gym ID is null (not connected to a gym)';
      print('saveWorkout: SKIPPED - $reason');
      return 'Failed to save: $reason';
    }
  }

  Future<void> deleteWorkout(String id) async {
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('workout_plans').delete().eq('id', id);
        _workouts.removeWhere((e) => e.id == id);
        _lastWorkoutsRaw = jsonEncode(_workouts.map((e) => e.toJson()).toList());
        await _storage.setString(_workoutsKey, _lastWorkoutsRaw!);
        notifyListeners();
      } catch (e) {
        print('Supabase deleteWorkout error: $e');
      }
    }
  }

  // --- Diets ---
  List<DietPlan> getDiets() => List.unmodifiable(_diets);

  void _loadDiets() {
    final raw = _storage.getString(_dietsKey);
    if (raw != null) {
      try {
        final List decoded = jsonDecode(raw);
        _diets = decoded.map((e) => DietPlan.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (e) {
        print('Error loading diets from cache: $e');
        _diets = [];
      }
    } else {
      _diets = [];
    }
  }

  Future<String?> saveDiet(DietPlan diet) async {
    final gymId = _storage.getGymInfo()?['id'];

    if (SupabaseService.isInitialized && gymId != null) {
      try {
        final mealsJson = diet.meals.map((m) => m.toJson()).toList();
        final data = <String, dynamic>{
          'id': diet.id,
          'gym_id': gymId,
          'title': diet.title,
          'goal': diet.goal,
          'calories': diet.calories,
          'meals': mealsJson,
          'notes': diet.notes,
          'status': diet.status,
        };
        print('saveDiet: Attempting upsert with id=${diet.id}, gym_id=$gymId');
        await SupabaseService.client.from('diet_plans').upsert(data);
        print('saveDiet: SUCCESS');

        final index = _diets.indexWhere((e) => e.id == diet.id);
        if (index >= 0) {
          _diets[index] = diet;
        } else {
          _diets.add(diet);
        }
        _lastDietsRaw = jsonEncode(_diets.map((e) => e.toJson()).toList());
        await _storage.setString(_dietsKey, _lastDietsRaw);
        notifyListeners();
        return null;
      } catch (e) {
        print('saveDiet: FAILED - $e');
        // Still save locally so user doesn't lose data
        final index = _diets.indexWhere((e) => e.id == diet.id);
        if (index >= 0) {
          _diets[index] = diet;
        } else {
          _diets.add(diet);
        }
        _lastDietsRaw = jsonEncode(_diets.map((e) => e.toJson()).toList());
        await _storage.setString(_dietsKey, _lastDietsRaw);
        notifyListeners();
        return 'Database error: $e';
      }
    } else {
      final index = _diets.indexWhere((e) => e.id == diet.id);
      if (index >= 0) {
        _diets[index] = diet;
      } else {
        _diets.add(diet);
      }
      _lastDietsRaw = jsonEncode(_diets.map((e) => e.toJson()).toList());
      await _storage.setString(_dietsKey, _lastDietsRaw);
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteDiet(String id) async {
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('diet_plans').delete().eq('id', id);
        _diets.removeWhere((e) => e.id == id);
        _lastDietsRaw = jsonEncode(_diets.map((e) => e.toJson()).toList());
        await _storage.setString(_dietsKey, _lastDietsRaw);
        notifyListeners();
      } catch (e) {
        print('Supabase deleteDiet error: $e');
        _diets.removeWhere((e) => e.id == id);
        _lastDietsRaw = jsonEncode(_diets.map((e) => e.toJson()).toList());
        await _storage.setString(_dietsKey, _lastDietsRaw);
        notifyListeners();
      }
    } else {
      _diets.removeWhere((e) => e.id == id);
      _lastDietsRaw = jsonEncode(_diets.map((e) => e.toJson()).toList());
      await _storage.setString(_dietsKey, _lastDietsRaw);
      notifyListeners();
    }
  }

  // --- Memberships ---
  List<MembershipPlan> getMemberships() => List.unmodifiable(_memberships);

  void _loadMemberships() {
    final raw = _storage.getString(_membershipsKey);
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      _memberships = decoded.map((e) => MembershipPlan.fromJson(e)).toList();
    } else {
      _memberships = [];
    }
  }

  void updateMembershipsCache(List<MembershipPlan> newPlans) {
    _memberships = List.from(newPlans);
    _storage.setString(_membershipsKey, jsonEncode(_memberships.map((e) => e.toJson()).toList()));
  }

  Future<void> saveMembership(MembershipPlan plan) async {
    final index = _memberships.indexWhere((e) => e.id == plan.id);
    if (index >= 0) {
      _memberships[index] = plan;
    } else {
      _memberships.add(plan);
    }
    await _storage.setString(_membershipsKey, jsonEncode(_memberships.map((e) => e.toJson()).toList()));
  }

  Future<void> deleteMembership(String id) async {
    _memberships.removeWhere((e) => e.id == id);
    await _storage.setString(_membershipsKey, jsonEncode(_memberships.map((e) => e.toJson()).toList()));
  }

  // --- Finance Transactions ---
  List<FinanceTransaction> getTransactions() => List.unmodifiable(_transactions);

  void _loadTransactions() {
    final raw = _storage.getString(_transactionsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        _transactions = decoded.map((e) => FinanceTransaction.fromJson(e)).toList();
        _lastTransactionsRaw = raw;
      } catch (e) {
        _transactions = [];
      }
    } else {
      _transactions = [];
    }
  }

  Future<void> saveTransaction(FinanceTransaction tx) async {
    final gymId = _storage.getGymInfo()?['id'] ?? (tx.gymId.isNotEmpty ? tx.gymId : null);
    if (gymId == null || gymId.isEmpty) {
      throw Exception('Active Gym ID not found.');
    }

    final String resolvedId = _isValidUUID(tx.id) ? tx.id : _generateUuidV4();
    final updatedTx = tx.copyWith(
      id: resolvedId,
      gymId: gymId,
      transactionDate: tx.transactionDate.isNotEmpty ? tx.transactionDate : DateTime.now().toIso8601String(),
    );

    // 1. Update local cache & notify UI immediately
    final index = _transactions.indexWhere((t) => t.id == resolvedId);
    if (index >= 0) {
      _transactions[index] = updatedTx;
    } else {
      _transactions.insert(0, updatedTx);
    }
    await _storage.setString(_transactionsKey, jsonEncode(_transactions.map((e) => e.toJson()).toList()));
    notifyListeners();

    // 2. Perform SINGLE database upsert with explicit ID & sanitized category
    final safeCategory = _sanitizeCategory(updatedTx.category);
    bool isDirectlyInserted = false;
    if (SupabaseService.isInitialized) {
      try {
        final Map<String, dynamic> data = {
          'id': resolvedId,
          'gym_id': gymId,
          'amount': updatedTx.amount,
          'type': updatedTx.type,
          'category': safeCategory,
          'payment_method': updatedTx.paymentMethod,
          'reference_id': updatedTx.referenceId,
          'created_by_info': updatedTx.createdByInfo.isNotEmpty ? updatedTx.createdByInfo : 'Staff',
          'notes': updatedTx.notes,
        };

        if (updatedTx.createdBy.isNotEmpty && _isValidUUID(updatedTx.createdBy)) {
          data['created_by'] = updatedTx.createdBy;
        } else {
          final currentUserId = SupabaseService.client.auth.currentUser?.id;
          if (currentUserId != null && currentUserId.isNotEmpty) {
            data['created_by'] = currentUserId;
          }
        }

        if (updatedTx.transactionDate.isNotEmpty) {
          data['transaction_date'] = updatedTx.transactionDate;
        }
        if (updatedTx.expenseDate.isNotEmpty) {
          data['expense_date'] = updatedTx.expenseDate;
        }
        if (updatedTx.revenueDate.isNotEmpty) {
          data['revenue_date'] = updatedTx.revenueDate;
        }
        if (updatedTx.entryDate.isNotEmpty) {
          data['entry_date'] = updatedTx.entryDate;
        }

        await SupabaseService.client
            .from('finance_transactions')
            .upsert(data, onConflict: 'id')
            .timeout(const Duration(seconds: 4));
        isDirectlyInserted = true;
      } catch (e) {
        print('Direct transaction upsert failed, queueing for background sync: $e');
      }
    }

    // 3. Queue ONLY if offline or direct upsert failed to prevent duplicates
    if (!isDirectlyInserted) {
      final Map<String, dynamic> data = {
        'id': resolvedId,
        'gym_id': gymId,
        'amount': updatedTx.amount,
        'type': updatedTx.type,
        'category': safeCategory,
        'payment_method': updatedTx.paymentMethod,
        'reference_id': updatedTx.referenceId,
        'created_by_info': updatedTx.createdByInfo.isNotEmpty ? updatedTx.createdByInfo : 'Staff',
        'notes': updatedTx.notes,
      };
      if (updatedTx.transactionDate.isNotEmpty) {
        data['transaction_date'] = updatedTx.transactionDate;
      }
      if (updatedTx.expenseDate.isNotEmpty) {
        data['expense_date'] = updatedTx.expenseDate;
      }
      if (updatedTx.revenueDate.isNotEmpty) {
        data['revenue_date'] = updatedTx.revenueDate;
      }
      if (updatedTx.entryDate.isNotEmpty) {
        data['entry_date'] = updatedTx.entryDate;
      }

      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'finance_transactions',
        'action': 'insert',
        'payload': data,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  Future<List<FinanceTransaction>> fetchMemberTransactionsFromBackend(String memberId) async {
    if (SupabaseService.isInitialized) {
      try {
        final List response = await SupabaseService.client.rpc(
          'get_member_payment_transactions',
          params: {'p_member_id': memberId},
        );
        return response.map((e) => FinanceTransaction.fromJson(e)).toList();
      } catch (e) {
        print('Backend RPC get_member_payment_transactions error, falling back to local list: $e');
      }
    }
    return [];
  }

  Future<void> deleteTransaction(String id) async {
    if (_isValidUUID(id)) {
      _transactions.removeWhere((t) => t.id == id);
      await _storage.setString(_transactionsKey, jsonEncode(_transactions.map((e) => e.toJson()).toList()));
      notifyListeners();

      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'finance_transactions',
        'action': 'delete',
        'payload': {'id': id},
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  // --- Attendance ---
  List<AttendanceRecord> getAttendance() => List.unmodifiable(_attendance);
  GymAttendanceSettings? getAttendanceSettings() => _attendanceSettings;
  List<AttendanceDisplaySession> getDisplaySessions() => List.unmodifiable(_displaySessions);

  void _loadAttendance() {
    final raw = _storage.getString(_attendanceKey);
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      _attendance = decoded.map((e) => AttendanceRecord.fromJson(e)).toList();
    } else {
      _attendance = [];
    }
  }

  Future<void> saveAttendance(AttendanceRecord record) async {
    final index = _attendance.indexWhere((e) => e.id == record.id);
    if (index >= 0) {
      _attendance[index] = record;
    } else {
      _attendance.add(record);
    }
    await _storage.setString(_attendanceKey, jsonEncode(_attendance.map((e) => e.toJson()).toList()));
  }

  Future<void> saveMemberAttendanceLog({
    required String memberId,
    required String memberName,
    required String date,
    required String status,
    required String checkInTime,
    required String? checkOutTime,
  }) async {
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) return;

    final existingIndex = _attendance.indexWhere((a) => a.userId == memberId && a.date == date);
    final uuid = existingIndex >= 0 ? _attendance[existingIndex].id : _generateUuidV4();
    
    String? formatToIso(String? timeStr) {
      if (timeStr == null || timeStr.isEmpty) return null;
      try {
        final parsed = DateFormat('hh:mm a').parse(timeStr);
        final dateObj = DateFormat('dd-MM-yyyy').parse(date);
        final fullDt = DateTime(dateObj.year, dateObj.month, dateObj.day, parsed.hour, parsed.minute);
        return fullDt.toUtc().toIso8601String();
      } catch (_) {
        return null;
      }
    }

    final checkInIso = formatToIso(checkInTime) ?? DateTime.now().toUtc().toIso8601String();
    final checkOutIso = formatToIso(checkOutTime);

    final newRecord = AttendanceRecord(
      id: uuid,
      userId: memberId,
      userName: memberName,
      userType: 'Member',
      date: date,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime ?? '',
      status: status,
      shiftStatus: '',
      workingMinutes: 0,
      lateMinutes: 0,
      earlyExitMinutes: 0,
      overtimeMinutes: 0,
      ruleVersion: 1,
    );

    if (existingIndex >= 0) {
      _attendance[existingIndex] = newRecord;
    } else {
      _attendance.add(newRecord);
    }

    await _storage.setString(_attendanceKey, jsonEncode(_attendance.map((e) => e.toJson()).toList()));
    notifyListeners();

    final payload = {
      'id': uuid,
      'gym_id': gymId,
      'user_id': memberId,
      'member_id': memberId,
      'user_type': 'Member',
      'role': 'Member',
      'date': date,
      'check_in': checkInIso,
      'check_out': checkOutIso,
      'status': status,
      'method': 'Manual',
    };

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('attendance_logs').upsert(payload);
      } catch (e) {
        print('saveMemberAttendanceLog Supabase upsert skipped/failed: $e. Fallback to queue.');
      }
    }

    _crudQueue.add({
      'uuid': _generateUuidV4(),
      'table': 'attendance_logs',
      'action': 'insert',
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
      'error_message': null,
    });

    await _saveQueuesToStorage();
    triggerBackgroundSync();
  }

  // --- Reset/Clear ---
  Future<void> clearAll() async {
    await _storage.clearAll();
    _loadAllFromStorage();
  }

  // --- Fitness Goals ---
  List<FitnessGoal> getGoals() => List.unmodifiable(_goals);

  void _loadGoals() {
    final raw = _storage.getString(_goalsKey);
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      _goals = decoded.map((e) => FitnessGoal.fromJson(e)).toList();
    } else {
      _goals = [
        FitnessGoal(id: 'g_1', name: 'Weight Loss', icon: '📉', color: '0xFFEF4444', description: 'Lose weight and burn fat'),
        FitnessGoal(id: 'g_2', name: 'Weight Gain', icon: '📈', color: '0xFF10B981', description: 'Gain healthy mass and muscle'),
        FitnessGoal(id: 'g_3', name: 'Lean Muscle Gain', icon: '💪', color: '0xFF7C3AED', description: 'Build lean body mass'),
        FitnessGoal(id: 'g_4', name: 'General Fitness', icon: '🧘', color: '0xFF3B82F6', description: 'Stay fit and healthy'),
      ];
      _saveGoalsToStorage();
    }
  }

  Future<void> _saveGoalsToStorage() async {
    await _storage.setString(_goalsKey, jsonEncode(_goals.map((e) => e.toJson()).toList()));
  }

  Future<void> saveGoal(FitnessGoal goal) async {
    final index = _goals.indexWhere((e) => e.id == goal.id);
    if (index >= 0) {
      _goals[index] = goal;
    } else {
      _goals.add(goal);
    }
    await _saveGoalsToStorage();

    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          await SupabaseService.client.from('fitness_goals').upsert({
            'id': goal.id,
            'gym_id': gymId,
            'name': goal.name,
            'icon': goal.icon,
            'color': goal.color,
            'description': goal.description,
          });
        } catch (e) {
          print('Supabase saveGoal error: $e');
        }
      }
    }
  }

  Future<void> deleteGoal(String id) async {
    _goals.removeWhere((e) => e.id == id);
    await _saveGoalsToStorage();

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('fitness_goals').delete().eq('id', id);
      } catch (e) {
        print('Supabase deleteGoal error: $e');
      }
    }
  }

  // --- Custom Fields ---
  List<CustomField> getCustomFields() => List.unmodifiable(_customFields);
  List<RecentActivity> getRecentActivities() {
    if (_recentActivities.isNotEmpty) {
      return List.unmodifiable(_recentActivities);
    }
    final List<RecentActivity> fallback = [];
    for (final tx in _transactions.take(5)) {
      DateTime txTime;
      try {
        txTime = DateTime.parse(tx.transactionDate);
      } catch (_) {
        txTime = DateTime.now();
      }
      fallback.add(RecentActivity(
        id: tx.id,
        gymId: tx.gymId,
        title: tx.title.isNotEmpty ? tx.title : 'Payment Received ₹${tx.amount.toInt()}',
        description: '${tx.category} (${tx.paymentMethod})',
        activityType: 'Payment',
        createdAt: txTime,
      ));
    }
    for (final m in _members.take(5)) {
      DateTime mTime;
      try {
        mTime = DateTime.parse(m.createdAt ?? '');
      } catch (_) {
        mTime = DateTime.now();
      }
      fallback.add(RecentActivity(
        id: m.id,
        gymId: '',
        title: 'New Member: ${m.name}',
        description: 'Joined on ${m.joinDate}',
        activityType: 'Membership',
        createdAt: mTime,
      ));
    }
    fallback.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(fallback.take(8).toList());
  }

  void _loadCustomFields() {
    final raw = _storage.getString(_customFieldsKey);
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      _customFields = decoded.map((e) => CustomField.fromJson(e)).toList();
    } else {
      _customFields = [
        CustomField(id: 'cf_1', label: 'Blood Group', fieldType: 'Dropdown', options: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'], required: false, visible: true),
        CustomField(id: 'cf_2', label: 'Medical History', fieldType: 'Dropdown', options: ['None', 'Heart Issue', 'Asthma', 'Diabetes', 'High BP'], required: false, visible: true),
        CustomField(id: 'cf_3', label: 'Notes', fieldType: 'Paragraph', options: [], required: false, visible: true),
      ];
      _saveCustomFieldsToStorage();
    }
  }

  Future<void> _saveCustomFieldsToStorage() async {
    await _storage.setString(_customFieldsKey, jsonEncode(_customFields.map((e) => e.toJson()).toList()));
  }

  Future<void> saveCustomField(CustomField field) async {
    final index = _customFields.indexWhere((e) => e.id == field.id);
    if (index >= 0) {
      _customFields[index] = field;
    } else {
      _customFields.add(field);
    }
    await _saveCustomFieldsToStorage();

    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          await SupabaseService.client.from('custom_member_fields').upsert({
            'id': field.id,
            'gym_id': gymId,
            'label': field.label,
            'field_type': field.fieldType,
            'options': field.options,
            'required': field.required,
            'visible': field.visible,
          });
        } catch (e) {
          print('Supabase saveCustomField error: $e');
        }
      }
    }
  }

  Future<void> deleteCustomField(String id) async {
    _customFields.removeWhere((e) => e.id == id);
    await _saveCustomFieldsToStorage();

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('custom_member_fields').delete().eq('id', id);
      } catch (e) {
        print('Supabase deleteCustomField error: $e');
      }
    }
  }

  // --- Invitations & Activation System ---
  Future<Map<String, dynamic>?> getLatestInvitation(String id, bool isStaff) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final response = await SupabaseService.client
          .from('invitations')
          .select()
          .eq(isStaff ? 'staff_id' : 'member_id', id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (response != null) return response;

      // Auto-fallback: If no invitation exists yet for this member, auto-generate one immediately
      if (!isStaff) {
        final member = _members.firstWhere(
          (m) => m.id == id,
          orElse: () => Member(
            id: id,
            name: '',
            email: '',
            phone: '',
            avatar: '',
            joinDate: '',
            status: 'Active',
            membershipPlanId: '',
            ptMember: false,
            ptTrainer: '',
            assignedWorkoutId: '',
            assignedDietId: '',
            medicalDetails: '',
            notes: '',
            pendingAmount: 0,
          ),
        );
        if (member.name.isNotEmpty || member.phone.isNotEmpty) {
          final code = await generateInvitation(
            recordId: id,
            name: member.name,
            phone: member.phone,
            isStaff: false,
          );
          return {
            'invitation_code': code,
            'status': 'Pending',
            'code_used': false,
            'member_id': id,
          };
        }
      }
      return null;
    } catch (e) {
      print('getLatestInvitation error: $e');
      return null;
    }
  }

  Future<String> generateInvitation({
    required String recordId,
    required String name,
    required String phone,
    required bool isStaff,
  }) async {
    final code = _generateRandomCode();
    if (!SupabaseService.isInitialized) {
      throw Exception('Supabase client is not initialized.');
    }
    if (!_isValidUUID(recordId)) {
      throw Exception('Invalid member/staff ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];
    final ownerId = SupabaseService.client.auth.currentUser?.id;

    if (gymId == null) {
      throw Exception('Active Gym ID not found.');
    }
    if (ownerId == null) {
      throw Exception('Logged in Owner user ID not found.');
    }

    try {
      if (SupabaseService.isInitialized) {
        final table = isStaff ? 'staff' : 'members';
        final checkRes = await SupabaseService.client.from(table).select('id').eq('id', recordId).maybeSingle();
        if (checkRes == null) {
          if (isStaff) {
            final staffRecord = _staff.firstWhere(
              (s) => s.id == recordId,
              orElse: () => Staff(
                id: recordId,
                name: name,
                email: '',
                phone: phone,
                role: 'Staff',
                department: 'Administration',
                status: 'Pending Activation',
                joinDate: DateTime.now().toString().split(' ')[0],
                shift: 'General',
                experience: 'N/A',
                rating: 5.0,
                sessionsCount: 0,
                membersTrained: 0,
                salary: 0.0,
                salaryDue: 0.0,
                avatar: '',
              ),
            );
            final Map<String, dynamic> staffData = {
              'id': staffRecord.id,
              'gym_id': gymId,
              'name': staffRecord.name,
              'email': staffRecord.email,
              'phone': staffRecord.phone,
              'role': staffRecord.role,
              'department': staffRecord.department,
              'status': staffRecord.status,
              'avatar': staffRecord.avatar,
              'join_date': staffRecord.joinDate,
              'shift': staffRecord.shift,
              'experience': staffRecord.experience,
              'rating': staffRecord.rating,
              'sessions_count': staffRecord.sessionsCount,
              'members_trained_count': staffRecord.membersTrained,
              'salary': staffRecord.salary,
              'salary_due': staffRecord.salaryDue,
              'gender': staffRecord.gender,
              'dob': staffRecord.dob,
              'aadhaar': staffRecord.aadhaar,
              'emergency_name': staffRecord.emergencyName,
              'emergency_phone': staffRecord.emergencyPhone,
              'address': staffRecord.address,
              'employment_type': staffRecord.employmentType,
              'salary_type': staffRecord.salaryType,
              'commission_percentage': staffRecord.commissionPercentage,
              'qualification': staffRecord.qualification,
              'notes': staffRecord.notes,
            };
            await SupabaseService.client.from('staff').upsert(staffData);
          } else {
            final memberRecord = _members.firstWhere(
              (m) => m.id == recordId,
              orElse: () => Member(
                id: recordId,
                name: name,
                email: '',
                phone: phone,
                avatar: '',
                joinDate: DateTime.now().toString().split(' ')[0],
                status: 'Active',
                membershipPlanId: '',
                ptMember: false,
                ptTrainer: '',
                assignedWorkoutId: '',
                assignedDietId: '',
                medicalDetails: 'None',
                notes: '',
                pendingAmount: 0.0,
              ),
            );
            final Map<String, dynamic> memberData = {
              'id': memberRecord.id,
              'gym_id': gymId,
              'name': memberRecord.name,
              'phone': memberRecord.phone,
              'status': memberRecord.status,
              'join_date': memberRecord.joinDate,
              'avatar': memberRecord.avatar,
              'membership_plan_id': memberRecord.membershipPlanId.isNotEmpty ? memberRecord.membershipPlanId : null,
              'pt_member': memberRecord.ptMember,
              'pt_trainer': _isValidUUID(memberRecord.ptTrainer) ? memberRecord.ptTrainer : null,
              'assigned_workout_id': _isValidUUID(memberRecord.assignedWorkoutId) ? memberRecord.assignedWorkoutId : null,
              'assigned_diet_id': _isValidUUID(memberRecord.assignedDietId) ? memberRecord.assignedDietId : null,
              'medical_details': memberRecord.medicalDetails,
              'notes': memberRecord.notes,
              'pending_amount': memberRecord.pendingAmount,
              'discount_amount': memberRecord.discountAmount,
              'total_received_amount': memberRecord.totalReceivedAmount,
              'payment_status': memberRecord.paymentStatus,
              'extra_fields': memberRecord.extraFields,
            };
            await SupabaseService.client.from('members').upsert(memberData);
          }
        }
      }

      await SupabaseService.client.from('invitations').insert({
        'gym_id': gymId,
        isStaff ? 'staff_id' : 'member_id': recordId,
        'invitation_code': code,
        'registered_mobile': phone,
        'status': 'Pending',
        'code_used': false,
        'expires_at': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'created_by': ownerId,
      });

      if (isStaff) {
        await SupabaseService.client
            .from('staff')
            .update({'status': 'Pending Activation'})
            .eq('id', recordId);
      }
    } catch (e) {
      print('generateInvitation Supabase warning/error: $e. Returning generated code.');
    }
    return code;
  }

  Future<String> unlinkAccount(String recordId, bool isStaff) async {
    final gymId = _storage.getGymInfo()?['id'];
    String name = '';
    String phone = '';

    if (SupabaseService.isInitialized && gymId != null) {
      try {
        // Prefer atomic RPC so association + user_id both get cleared
        await SupabaseService.client.rpc(
          'unlink_gym_account',
          params: {
            'p_record_id': recordId,
            'p_is_staff': isStaff,
          },
        );

        final record = await SupabaseService.client
            .from(isStaff ? 'staff' : 'members')
            .select('name, phone')
            .eq('id', recordId)
            .maybeSingle();

        if (record != null) {
          name = record['name'] ?? '';
          phone = record['phone'] ?? '';
        }
      } catch (e) {
        print('unlink_gym_account RPC failed, falling back to direct update: $e');
        try {
          final record = await SupabaseService.client
              .from(isStaff ? 'staff' : 'members')
              .select('user_id, name, phone')
              .eq('id', recordId)
              .maybeSingle();

          if (record != null) {
            name = record['name'] ?? '';
            phone = record['phone'] ?? '';
            final linkedUserId = record['user_id'];

            if (linkedUserId != null) {
              await SupabaseService.client
                  .from('user_gym_associations')
                  .delete()
                  .eq('user_id', linkedUserId)
                  .eq('gym_id', gymId)
                  .eq('role', isStaff ? 'staff' : 'member');
            }
          }

          await SupabaseService.client
              .from(isStaff ? 'staff' : 'members')
              .update({
                'user_id': null,
                'status': 'Pending Activation',
              })
              .eq('id', recordId);
        } catch (e2) {
          print('unlinkAccount Supabase error: $e2');
        }
      }
    }

    // 4. Generate new invitation
    return await generateInvitation(
      recordId: recordId,
      name: name,
      phone: phone,
      isStaff: isStaff,
    );
  }

  List<Member> _mergeMembersList(List<Member> serverList) {
    // Keep any member that is in local queue and not marked for deletion, regardless of retry count or failure
    final pendingIds = _crudQueue
        .where((q) => q['table'] == 'members' && q['action'] != 'delete')
        .map((q) {
          final payload = q['payload'] as Map<String, dynamic>;
          return payload['id']?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toSet();

    final Map<String, Member> merged = {};
    for (var m in serverList) {
      merged[m.id] = m;
    }
    for (var m in _members) {
      if (pendingIds.contains(m.id) || !merged.containsKey(m.id)) {
        // If it's pending in queue or locally created and not in serverList, preserve local record
        if (pendingIds.contains(m.id)) {
          merged[m.id] = m;
        }
      }
    }
    return merged.values.toList();
  }

  List<Staff> _mergeStaffList(List<Staff> serverList) {
    final pendingIds = _crudQueue
        .where((q) => q['table'] == 'staff' && q['action'] != 'delete')
        .map((q) {
          final payload = q['payload'] as Map<String, dynamic>;
          return payload['id']?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toSet();

    final Map<String, Staff> merged = {};
    for (var s in serverList) {
      merged[s.id] = s;
    }
    for (var s in _staff) {
      if (pendingIds.contains(s.id)) {
        merged[s.id] = s;
      }
    }
    return merged.values.toList();
  }

  List<FinanceTransaction> _mergeTransactionsList(List<FinanceTransaction> serverList) {
    final pendingIds = _crudQueue
        .where((q) => q['table'] == 'finance_transactions' && q['action'] != 'delete')
        .map((q) {
          final payload = q['payload'] as Map<String, dynamic>;
          return payload['id']?.toString() ?? '';
        })
        .where((id) => id.isNotEmpty)
        .toSet();

    final Map<String, FinanceTransaction> merged = {};
    for (var t in serverList) {
      merged[t.id] = t;
    }
    for (var t in _transactions) {
      if (pendingIds.contains(t.id)) {
        merged[t.id] = t;
      }
    }
    return merged.values.toList();
  }

  List<AttendanceRecord> _mergeAttendanceList(List<AttendanceRecord> serverList) {
    final pendingUuids = _attendanceQueue
        .map((q) => q['attendance_uuid'] as String)
        .toSet();

    final Map<String, AttendanceRecord> merged = {};
    for (var a in serverList) {
      merged[a.id] = a;
    }
    for (var a in _attendance) {
      if (pendingUuids.contains(a.id)) {
        merged[a.id] = a;
      }
    }
    return merged.values.toList();
  }

  String _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(8, (index) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> fetchMembersFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('members')
              .select()
              .eq('gym_id', gymId);
          _resetNetworkError();
          final responseStr = jsonEncode(response);
          if (responseStr != _lastMembersRaw) {
            _lastMembersRaw = responseStr;
            final serverList = response.map((e) => Member.fromJson(e)).toList();
            _members = _mergeMembersList(serverList);
            await _storage.setString(_membersKey, jsonEncode(_members.map((e) => e.toJson()).toList()));
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchMembersFromSupabase', e);
        }
      }
    }
  }

  Future<void> fetchStaffFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('staff')
              .select()
              .eq('gym_id', gymId);

          // Fetch all active shift assignments for this gym
          final List assignments = await SupabaseService.client
              .from('staff_shift_assignments')
              .select('staff_id, assignment_type')
              .eq('gym_id', gymId)
              .eq('status', 'Active');
              
          final Map<String, String> staffShifts = {
            for (var a in assignments) a['staff_id'].toString(): a['assignment_type'].toString()
          };

          _resetNetworkError();
          
          final List<Staff> loadedStaff = [];
          for (var e in response) {
            final staffId = e['id'].toString();
            final dbShift = staffShifts[staffId] ?? e['shift'] ?? 'Single Shift';
            
            final modifiedJson = Map<String, dynamic>.from(e);
            modifiedJson['shift'] = dbShift;
            loadedStaff.add(Staff.fromJson(modifiedJson));
          }

          final responseStr = jsonEncode(response);
          if (responseStr != _lastStaffRaw) {
            _lastStaffRaw = responseStr;
            _staff = _mergeStaffList(loadedStaff);
            await _storage.setString(_staffKey, jsonEncode(_staff.map((e) => e.toJson()).toList()));
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchStaffFromSupabase', e);
        }
      }
    }
  }

  Future<void> fetchTransactionsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('finance_transactions')
              .select()
              .eq('gym_id', gymId)
              .order('transaction_date', ascending: false);
          _resetNetworkError();
          final responseStr = jsonEncode(response);
          if (responseStr != _lastTransactionsRaw) {
            _lastTransactionsRaw = responseStr;
            final serverList = response.map((e) => FinanceTransaction.fromJson(e)).toList();
            _transactions = _mergeTransactionsList(serverList);
            await _storage.setString(_transactionsKey, jsonEncode(_transactions.map((e) => e.toJson()).toList()));
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchTransactionsFromSupabase', e);
        }
      }
    }
  }

  // --- Offline Fetchers ---
  Future<void> fetchSalaryAdvancesFromSupabase(String staffId) async {
    if (SupabaseService.isInitialized) {
      try {
        final List response = await SupabaseService.client
            .from('salary_advance_ledger')
            .select()
            .eq('staff_id', staffId)
            .order('given_date', ascending: false);
        _resetNetworkError();
        final remoteList = List<Map<String, dynamic>>.from(response);
        final remoteIds = remoteList.map((e) => e['id']?.toString()).toSet();
        final localOnly = _salaryAdvances.where((l) => l['staff_id'] == staffId && !remoteIds.contains(l['id']?.toString())).toList();
        _salaryAdvances = [...localOnly, ...remoteList];
        await _storage.setString(LocalStorageService.keySalaryAdvances, jsonEncode(_salaryAdvances));
        notifyListeners();
      } catch (e) {
        print('fetchSalaryAdvancesFromSupabase error: $e');
      }
    }
  }

  Future<void> fetchSalaryDraftsFromSupabase(String gymId) async {
    if (SupabaseService.isInitialized) {
      try {
        final List response = await SupabaseService.client
            .from('salary_drafts')
            .select()
            .eq('gym_id', gymId)
            .order('salary_month', ascending: false);
        _resetNetworkError();
        _salaryDrafts = List<Map<String, dynamic>>.from(response);
        await _storage.setString(LocalStorageService.keySalaryDrafts, jsonEncode(_salaryDrafts));
        notifyListeners();
      } catch (e) {
        print('fetchSalaryDraftsFromSupabase error: $e');
      }
    }
  }

  Future<void> fetchLeaveRequestsFromSupabase(String staffId) async {
    if (SupabaseService.isInitialized) {
      try {
        final List response = await SupabaseService.client
            .from('leave_requests')
            .select()
            .eq('staff_id', staffId)
            .order('created_at', ascending: false);
        _resetNetworkError();
        final remoteList = List<Map<String, dynamic>>.from(response);
        final remoteIds = remoteList.map((e) => e['id']?.toString()).toSet();
        final localOnly = _leaveRequests.where((l) => l['staff_id'] == staffId && !remoteIds.contains(l['id']?.toString())).toList();
        _leaveRequests = [...localOnly, ...remoteList];
        await _storage.setString(LocalStorageService.keyLeaveRequests, jsonEncode(_leaveRequests));
        notifyListeners();
      } catch (e) {
        print('fetchLeaveRequestsFromSupabase error: $e');
      }
    }
  }

  Future<void> fetchGymLeaveRequestsFromSupabase(String gymId) async {
    if (SupabaseService.isInitialized) {
      try {
        final List response = await SupabaseService.client
            .from('leave_requests')
            .select()
            .eq('gym_id', gymId)
            .order('created_at', ascending: false);
        _resetNetworkError();
        final remoteList = List<Map<String, dynamic>>.from(response);
        final remoteIds = remoteList.map((e) => e['id']?.toString()).toSet();
        final localOnly = _leaveRequests.where((l) => l['gym_id'] == gymId && !remoteIds.contains(l['id']?.toString())).toList();
        _leaveRequests = [...localOnly, ...remoteList];
        await _storage.setString(LocalStorageService.keyLeaveRequests, jsonEncode(_leaveRequests));
        notifyListeners();
      } catch (e) {
        print('fetchGymLeaveRequestsFromSupabase error: $e');
      }
    }
  }

  Future<void> fetchGymSalaryAdvancesFromSupabase(String gymId) async {
    if (SupabaseService.isInitialized) {
      try {
        final List response = await SupabaseService.client
            .from('salary_advance_ledger')
            .select()
            .eq('gym_id', gymId)
            .order('given_date', ascending: false);
        _resetNetworkError();
        final remoteList = List<Map<String, dynamic>>.from(response);
        final remoteIds = remoteList.map((e) => e['id']?.toString()).toSet();
        final localOnly = _salaryAdvances.where((l) => l['gym_id'] == gymId && !remoteIds.contains(l['id']?.toString())).toList();
        _salaryAdvances = [...localOnly, ...remoteList];
        await _storage.setString(_salaryAdvancesKey, jsonEncode(_salaryAdvances));
        notifyListeners();
      } catch (e) {
        print('fetchGymSalaryAdvancesFromSupabase error: $e');
      }
    }
  }

  // --- Offline Creators & Updates ---
  Future<void> saveSalaryAdvanceOffline({
    required String gymId,
    required String staffId,
    required double amount,
    required String reason,
    required String date,
    String status = 'Approved',
  }) async {
    final uuid = _generateUuidV4();
    final parsedDate = DateTime.tryParse(date) ?? DateTime.now();
    final salaryMonth = DateFormat('MMMM yyyy').format(parsedDate);

    final Map<String, dynamic> item = {
      'id': uuid,
      'gym_id': gymId,
      'staff_id': staffId,
      'advance_amount': amount,
      'reason': reason,
      'status': status,
      'given_date': date,
      'salary_month': salaryMonth,
      'created_at': DateTime.now().toIso8601String(),
    };

    _salaryAdvances.insert(0, item);
    await _storage.setString(_salaryAdvancesKey, jsonEncode(_salaryAdvances));
    notifyListeners();

    // Try direct Supabase insert first
    bool isDirectlyInserted = false;
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('salary_advance_ledger').upsert(item);
        isDirectlyInserted = true;
      } catch (e) {
        print('saveSalaryAdvanceOffline direct insert failed, queueing: $e');
      }
    }

    if (!isDirectlyInserted) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'salary_advance_ledger',
        'action': 'insert',
        'payload': item,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  Future<void> paySalaryDraftOffline({
    required String draftId,
    required String paymentMode,
    required String notes,
  }) async {
    final index = _salaryDrafts.indexWhere((d) => d['id'] == draftId);
    if (index >= 0) {
      final updatedDraft = Map<String, dynamic>.from(_salaryDrafts[index]);
      updatedDraft['status'] = 'Paid';
      _salaryDrafts[index] = updatedDraft;
      await _storage.setString(_salaryDraftsKey, jsonEncode(_salaryDrafts));
      notifyListeners();
    }

    // Try direct RPC call first
    final rpcPayload = {
      'p_draft_id': draftId,
      'p_payment_mode': paymentMode,
      'p_notes': notes,
    };
    bool isDirectlyDone = false;
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.rpc('pay_salary_draft_v2', params: rpcPayload);
        isDirectlyDone = true;
      } catch (e) {
        print('paySalaryDraftOffline direct RPC failed, queueing: $e');
      }
    }

    if (!isDirectlyDone) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'rpc_pay_salary_draft',
        'action': 'rpc',
        'payload': rpcPayload,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  Future<void> createLeaveRequestOffline({
    required String gymId,
    required String staffId,
    required String startDate,
    required String endDate,
    required String reason,
    required String leaveType,
    bool isHalfDay = false,
    String? halfDayShift,
  }) async {
    final uuid = _generateUuidV4();
    final Map<String, dynamic> item = {
      'id': uuid,
      'gym_id': gymId,
      'staff_id': staffId,
      'start_date': startDate,
      'end_date': endDate,
      'reason': reason,
      'leave_type': leaveType,
      'is_half_day': isHalfDay,
      if (halfDayShift != null) 'half_day_shift': halfDayShift,
      'status': 'Pending',
      'created_at': DateTime.now().toIso8601String(),
    };

    _leaveRequests.insert(0, item);
    await _storage.setString(_leaveRequestsKey, jsonEncode(_leaveRequests));
    notifyListeners();

    // Try direct Supabase insert first
    bool isDirectlyInserted = false;
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('leave_requests').upsert(item);
        isDirectlyInserted = true;
      } catch (e) {
        print('createLeaveRequestOffline direct insert failed, queueing: $e');
      }
    }

    if (!isDirectlyInserted) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'leave_requests',
        'action': 'insert',
        'payload': item,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  Future<void> updateLeaveStatusOffline({
    required String requestId,
    required String status,
  }) async {
    String? gymId;
    final index = _leaveRequests.indexWhere((l) => l['id'] == requestId);
    if (index >= 0) {
      final updated = Map<String, dynamic>.from(_leaveRequests[index]);
      updated['status'] = status;
      _leaveRequests[index] = updated;
      gymId = updated['gym_id'];
      await _storage.setString(_leaveRequestsKey, jsonEncode(_leaveRequests));
      
      // Update local dashboard alerts count
      if (_dashboardAlertsData['staff_leave_requests'] != null) {
        final currentCount = (_dashboardAlertsData['staff_leave_requests']['count'] as num?)?.toInt() ?? 0;
        if (currentCount > 0) {
          _dashboardAlertsData['staff_leave_requests']['count'] = currentCount - 1;
        }
      }
      if (_dbPendingLeaves > 0) _dbPendingLeaves--;
      
      notifyListeners();
    }

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client
            .from('leave_requests')
            .update({'status': status})
            .eq('id', requestId);
        _resetNetworkError();
        return;
      } catch (e) {
        print('Direct leave status update error: $e');
      }
    }

    _crudQueue.add({
      'uuid': _generateUuidV4(),
      'table': 'leave_requests',
      'action': 'update',
      'payload': {
        'id': requestId,
        'status': status,
        if (gymId != null) 'gym_id': gymId,
      },
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
      'error_message': null,
    });
    await _saveQueuesToStorage();
    triggerBackgroundSync();
  }

  Future<void> updateSalaryAdvanceStatusOffline({
    required String requestId,
    required String status,
  }) async {
    String? gymId;
    final index = _salaryAdvances.indexWhere((a) => a['id'] == requestId);
    if (index >= 0) {
      final updated = Map<String, dynamic>.from(_salaryAdvances[index]);
      updated['status'] = status;
      _salaryAdvances[index] = updated;
      gymId = updated['gym_id'];
      await _storage.setString(_salaryAdvancesKey, jsonEncode(_salaryAdvances));
      
      // Update local dashboard alerts count
      if (_dashboardAlertsData['staff_advance_requests'] != null) {
        final currentCount = (_dashboardAlertsData['staff_advance_requests']['count'] as num?)?.toInt() ?? 0;
        if (currentCount > 0) {
          _dashboardAlertsData['staff_advance_requests']['count'] = currentCount - 1;
        }
      }
      if (_dbPendingAdvances > 0) _dbPendingAdvances--;

      notifyListeners();
    }

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client
            .from('salary_advance_ledger')
            .update({'status': status})
            .eq('id', requestId);
        _resetNetworkError();
        return;
      } catch (e) {
        print('Direct advance status update error: $e');
      }
    }

    _crudQueue.add({
      'uuid': _generateUuidV4(),
      'table': 'salary_advance_ledger',
      'action': 'update',
      'payload': {
        'id': requestId,
        'status': status,
        if (gymId != null) 'gym_id': gymId,
      },
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
      'error_message': null,
    });
    await _saveQueuesToStorage();
    triggerBackgroundSync();
  }

  Future<void> fetchGymShiftSettingsFromSupabase(String gymId) async {
    if (SupabaseService.isInitialized) {
      try {
        final settingsRes = await SupabaseService.client
            .from('gym_shift_settings')
            .select('mode')
            .eq('gym_id', gymId)
            .maybeSingle();

        if (settingsRes != null) {
          _shiftMode = settingsRes['mode'] ?? 'Single Shift';
          await _storage.setString(_gymShiftSettingsKey, _shiftMode);
        }

        final shiftsRes = await SupabaseService.client
            .from('gym_shifts')
            .select('*')
            .eq('gym_id', gymId);

        _shiftsList = List<Map<String, dynamic>>.from(shiftsRes);
        await _storage.setString(_gymShiftsListKey, jsonEncode(_shiftsList));
        notifyListeners();
      } catch (e) {
        print('fetchGymShiftSettingsFromSupabase error: $e');
      }
    }
  }

  Future<bool> saveOperatingHoursOffline(String gymId, String mode, List<Map<String, dynamic>> shiftsList) async {
    _shiftMode = mode;
    _shiftsList = shiftsList;
    await _storage.setString(_gymShiftSettingsKey, mode);
    await _storage.setString(_gymShiftsListKey, jsonEncode(shiftsList));
    notifyListeners();

    // Try direct RPC call first
    final rpcPayload = {
      'p_gym_id': gymId,
      'p_mode': mode,
      'p_shifts': shiftsList,
    };
    bool isDirectlyDone = false;
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.rpc('save_gym_operating_hours', params: rpcPayload);
        isDirectlyDone = true;
      } catch (e) {
        print('saveOperatingHoursOffline direct RPC failed, queueing: $e');
      }
    }

    if (!isDirectlyDone) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'rpc_save_gym_operating_hours',
        'action': 'rpc',
        'payload': rpcPayload,
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
    return true;
  }

  Future<void> fetchGoalsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('fitness_goals')
              .select()
              .eq('gym_id', gymId);
          if (response.isNotEmpty) {
            _goals = response.map((e) => FitnessGoal.fromJson(e)).toList();
            await _saveGoalsToStorage();
            notifyListeners();
          } else {
            _loadGoals();
            for (var goal in _goals) {
              await SupabaseService.client.from('fitness_goals').upsert({
                'id': goal.id,
                'gym_id': gymId,
                'name': goal.name,
                'icon': goal.icon,
                'color': goal.color,
                'description': goal.description,
              });
            }
          }
        } catch (e) {
          _handleNetworkError('fetchGoalsFromSupabase', e);
        }
      }
    }
  }

  Future<void> fetchCustomFieldsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('custom_member_fields')
              .select()
              .eq('gym_id', gymId);
          if (response.isNotEmpty) {
            _customFields = response.map((e) => CustomField.fromJson(e)).toList();
            await _saveCustomFieldsToStorage();
            notifyListeners();
          } else {
            _loadCustomFields();
            for (var field in _customFields) {
              await SupabaseService.client.from('custom_member_fields').upsert({
                'id': field.id,
                'gym_id': gymId,
                'label': field.label,
                'field_type': field.fieldType,
                'options': field.options,
                'required': field.required,
                'visible': field.visible,
              });
            }
          }
        } catch (e) {
          _handleNetworkError('fetchCustomFieldsFromSupabase', e);
        }
      }
    }
  }

  Future<void> fetchRecentActivitiesFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('vw_recent_activities')
              .select()
              .eq('gym_id', gymId)
              .order('created_at', ascending: false)
              .limit(10);
          _recentActivities = response.map((e) => RecentActivity.fromJson(e)).toList();
          await _saveRecentActivitiesToStorage();
          notifyListeners();
        } catch (e) {
          _handleNetworkError('fetchRecentActivitiesFromSupabase', e);
        }
      }
    }
  }

  Future<void> fetchAttendanceSettingsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final response = await SupabaseService.client
              .from('attendance_settings')
              .select()
              .eq('gym_id', gymId)
              .maybeSingle();
          if (response != null) {
            _attendanceSettings = GymAttendanceSettings.fromJson(response);
            await _storage.setString(_attendanceSettingsKey, jsonEncode(response));
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchAttendanceSettingsFromSupabase', e);
        }
      }
    }
  }

  Future<void> saveAttendanceSettingsToSupabase(GymAttendanceSettings settings) async {
    // 1. Save locally instantly
    _attendanceSettings = settings;
    await _storage.setString(LocalStorageService.keyAttendanceSettings, jsonEncode(settings.toJson()));
    notifyListeners();

    // 2. Try direct Supabase upsert first
    bool isDirectlyInserted = false;
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('attendance_settings').upsert(settings.toJson());
        isDirectlyInserted = true;
      } catch (e) {
        print('saveAttendanceSettingsToSupabase direct upsert failed, queueing: $e');
      }
    }

    if (!isDirectlyInserted) {
      _crudQueue.add({
        'uuid': _generateUuidV4(),
        'table': 'attendance_settings',
        'action': 'insert',
        'payload': settings.toJson(),
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
        'error_message': null,
      });
      await _saveQueuesToStorage();
      triggerBackgroundSync();
    }
  }

  Future<void> fetchDisplaySessionsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final List response = await SupabaseService.client
              .from('attendance_displays')
              .select()
              .eq('gym_id', gymId)
              .order('created_at', ascending: false);
          _displaySessions = response.map((e) => AttendanceDisplaySession.fromJson(e)).toList();
          notifyListeners();
        } catch (e) {
          _handleNetworkError('fetchDisplaySessionsFromSupabase', e);
        }
      }
    }
  }

  Future<void> verifyDisplayDeviceInSupabase(String token) async {
    if (SupabaseService.isInitialized) {
      final currentUserId = SupabaseService.client.auth.currentUser?.id;
      if (currentUserId != null) {
        try {
          final res = await SupabaseService.client.rpc('verify_display_token', params: {
            'p_token': token,
            'p_user_id': currentUserId,
          });
          if (res['success'] != true) {
            throw Exception(res['reason'] ?? 'Failed to verify display');
          }
          await fetchDisplaySessionsFromSupabase();
        } catch (e) {
          _handleNetworkError('verifyDisplayDeviceInSupabase', e);
          throw Exception(e.toString().replaceAll('Exception: ', ''));
        }
      }
    }
  }

  Future<String> getOrGenerateDisplayLink() async {
    if (!SupabaseService.isInitialized) return "";
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId != null) {
      try {
        final res = await SupabaseService.client.rpc('get_or_create_gym_display', params: {
          'p_gym_id': gymId,
        });
        if (res['success'] == true) {
          final publicId = res['display_public_id'] as String;
          await fetchDisplaySessionsFromSupabase();
          return "https://gymos.tech/attendance?display_id=$publicId";
        }
      } catch (e) {
        _handleNetworkError('getOrGenerateDisplayLink', e);
      }
    }
    return "";
  }

  Future<void> manageDisplayDevice(String displayId, String action, {String? name}) async {
    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client.rpc('manage_display_device', params: {
          'p_display_id': displayId,
          'p_action': action,
          'p_name': name,
        });
        if (res['success'] != true) {
          throw Exception(res['reason'] ?? 'Failed to manage display device');
        }
        await fetchDisplaySessionsFromSupabase();
      } catch (e) {
        _handleNetworkError('manageDisplayDevice', e);
        throw Exception(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> fetchAttendanceLogsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      final gymId = _storage.getGymInfo()?['id'];
      if (gymId != null) {
        try {
          final currentUser = SupabaseService.client.auth.currentUser;
          if (currentUser == null) return;

          var query = SupabaseService.client
              .from('attendance_logs')
              .select('*, profiles(full_name)');

          final role = _storage.getUserRole();
          if (role == 'member') {
            query = query.eq('user_id', currentUser.id);
          } else {
            query = query.eq('gym_id', gymId);
          }

          final List response = await query.order('check_in', ascending: false);
          _resetNetworkError();
          final serverList = response.map((e) => AttendanceRecord.fromJson(e)).toList();
          _attendance = _mergeAttendanceList(serverList);
          await _storage.setString(_attendanceKey, jsonEncode(_attendance.map((e) => e.toJson()).toList()));
          notifyListeners();
        } catch (e) {
          _handleNetworkError('fetchAttendanceLogsFromSupabase', e);
        }
      }
    }
  }

  void _saveTodayDetailsToStorage(String userId, String gymId) {
    if (_todayAttendanceDetails != null && userId.isNotEmpty && gymId.isNotEmpty) {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final key = 'today_att_details_${gymId}_${userId}_$todayStr';
      _storage.setString(key, jsonEncode(_todayAttendanceDetails));
    }
  }

  void _loadTodayDetailsFromStorage(String userId, String gymId) {
    if (userId.isEmpty || gymId.isEmpty) {
      _todayAttendanceDetails = null;
      return;
    }
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final key = 'today_att_details_${gymId}_${userId}_$todayStr';
    final raw = _storage.getString(key);
    if (raw != null) {
      try {
        _todayAttendanceDetails = Map<String, dynamic>.from(jsonDecode(raw));
        notifyListeners();
      } catch (_) {}
    } else {
      _todayAttendanceDetails = null;
    }
  }

  bool _isValidUuid(String? id) {
    if (id == null) return false;
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return uuidRegex.hasMatch(id);
  }

  String _generateUuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<Map<String, dynamic>> processScanAttendanceInSupabase({
    required String token,
    String? userId,
    String? gymId,
    String? userType,
    String? method,
    String? ssid,
    String? bssid,
  }) async {
    if (!SupabaseService.isInitialized) {
      return {'success': false, 'reason': 'Supabase not initialized'};
    }
    
    // Resolve Gym ID robustly (MUST be a valid UUID for PostgreSQL)
    String? effectiveGymId = gymId ?? _storage.getGymInfo()?['id'];
    if (!_isValidUuid(effectiveGymId)) {
      try {
        final gymRes = await SupabaseService.client.from('gyms').select('id').limit(1).maybeSingle();
        if (gymRes != null && _isValidUuid(gymRes['id']?.toString())) {
          effectiveGymId = gymRes['id'].toString();
        } else {
          try {
            final newGym = await SupabaseService.client.from('gyms').insert({}).select('id').maybeSingle();
            if (newGym != null && _isValidUuid(newGym['id']?.toString())) {
              effectiveGymId = newGym['id'].toString();
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
    if (!_isValidUuid(effectiveGymId)) {
      effectiveGymId = _generateUuidV4();
    }

    // Resolve User ID robustly (MUST be a valid UUID for PostgreSQL)
    String? validUserId;
    if (_isValidUuid(userId)) {
      validUserId = userId;
    } else if (_isValidUuid(SupabaseService.client.auth.currentUser?.id)) {
      validUserId = SupabaseService.client.auth.currentUser?.id;
    }
    if (!_isValidUuid(validUserId)) {
      try {
        final pRes = await SupabaseService.client.from('profiles').select('id').limit(1).maybeSingle();
        if (pRes != null && _isValidUuid(pRes['id']?.toString())) {
          validUserId = pRes['id'].toString();
        } else {
          final newProf = await SupabaseService.client.from('profiles').insert({'full_name': 'Gym Staff User'}).select('id').maybeSingle();
          if (newProf != null && _isValidUuid(newProf['id']?.toString())) {
            validUserId = newProf['id'].toString();
          }
        }
      } catch (_) {}
    }
    if (!_isValidUuid(validUserId)) {
      validUserId = _generateUuidV4();
    }

    String? resolvedStaffId;
    try {
      final staffQuery = await SupabaseService.client
          .from('staff')
          .select('id, user_id')
          .eq('user_id', validUserId ?? '')
          .limit(1)
          .maybeSingle();
      if (staffQuery != null && _isValidUuid(staffQuery['id']?.toString())) {
        resolvedStaffId = staffQuery['id'].toString();
      }
    } catch (_) {}

    final String finalGymId = (effectiveGymId != null && effectiveGymId.isNotEmpty) ? effectiveGymId : _generateUuidV4();
    final String finalUserId = (validUserId != null && validUserId.isNotEmpty) ? validUserId : _generateUuidV4();

    // Try RPC first
    try {
      final response = await SupabaseService.client.rpc('process_qr_attendance', params: {
        'p_token': token,
        'p_user_type': userType,
      });
      if (response != null && response is Map) {
        final Map<String, dynamic> result = Map<String, dynamic>.from(response as Map);
        if (result['success'] == true) {
          await fetchAttendanceLogsFromSupabase();
          await fetchTodayAttendanceDetails(finalUserId, finalGymId);
          await fetchOwnerDashboardStats(finalGymId);
          await fetchAttendanceAlerts(finalGymId);
        }
        return result;
      }
      return {
        'success': false,
        'reason': 'Unexpected response from server.',
        'message': 'Failed to process check-in request.',
      };
    } catch (e) {
      print('processScanAttendanceInSupabase RPC error: $e');
      return {
        'success': false,
        'reason': e.toString().replaceAll('Exception: ', ''),
        'message': 'Failed to mark attendance: $e',
      };
    }
  }

  Future<void> fetchOwnerDashboardStats(String gymId) async {
    if (SupabaseService.isInitialized) {
      try {
        final response = await SupabaseService.client.rpc('get_owner_attendance_dashboard', params: {
          'p_gym_id': gymId,
        });
        if (response != null) {
          _dashboardStats = Map<String, dynamic>.from(response as Map);
          await _storage.setString(_dashboardStatsKey, jsonEncode(_dashboardStats));
          notifyListeners();
        }
      } catch (e) {
        _handleNetworkError('fetchOwnerDashboardStats', e);
      }
    }
  }

  Future<void> fetchAttendanceAlerts(String gymId) async {
    if (SupabaseService.isInitialized) {
      try {
        final List response = await SupabaseService.client
            .from('attendance_alerts')
            .select()
            .eq('gym_id', gymId)
            .order('created_at', ascending: false);
        _alerts = response.map((e) => AttendanceAlert.fromJson(e)).toList();
        await _storage.setString(_alertsKey, jsonEncode(response));
        notifyListeners();
      } catch (e) {
        _handleNetworkError('fetchAttendanceAlerts', e);
      }
    }
  }

  Future<void> fetchAttendanceCorrections(String gymId) async {
    if (SupabaseService.isInitialized) {
      try {
        final List response = await SupabaseService.client
            .from('attendance_correction_requests')
            .select('*')
            .eq('gym_id', gymId)
            .order('created_at', ascending: false);
        _corrections = response.map((e) => AttendanceCorrectionRequest.fromJson(e)).toList();
        await _storage.setString(_correctionsKey, jsonEncode(response));
        notifyListeners();
      } catch (e) {
        _handleNetworkError('fetchAttendanceCorrections', e);
      }
    }
  }

  Future<Map<String, dynamic>?> fetchStaffWorkSchedule(String staffId, String gymId) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final response = await SupabaseService.client.rpc(
        'get_staff_work_schedule',
        params: {
          'p_staff_id': staffId,
          'p_gym_id': gymId,
        },
      );
      if (response != null && response is Map) {
        return Map<String, dynamic>.from(response as Map);
      }
    } catch (e) {
      print('fetchStaffWorkSchedule RPC error: $e');
    }
    return null;
  }

  Future<void> fetchTodayAttendanceDetails(String userId, String gymId) async {
    _loadTodayDetailsFromStorage(userId, gymId);
    if (!SupabaseService.isInitialized) return;

    // Try RPC first (which calculates all shift statuses and hours in the database backend)
    try {
      final response = await SupabaseService.client.rpc(
        'get_staff_today_attendance_details_v2',
        params: {
          'p_user_id': userId,
          'p_gym_id': gymId,
        },
      );
      if (response != null && response is Map) {
        _todayAttendanceDetails = Map<String, dynamic>.from(response as Map);
        _saveTodayDetailsToStorage(userId, gymId);
        notifyListeners();
        return;
      }
    } catch (e) {
      print('fetchTodayAttendanceDetails RPC error: $e');
    }

    // Default template if backend RPC is not reachable or fails
    _todayAttendanceDetails = {
      'assigned_shift': 'Single Shift',
      'working_hours_today': '0h 00m',
      'can_check_in': true,
      'can_check_out': false,
      'first_shift_name': 'Shift 1',
      'first_shift_check_in': null,
      'first_shift_check_out': null,
      'first_shift_status': 'Not Checked In',
      'second_shift_name': 'Shift 2',
      'second_shift_check_in': null,
      'second_shift_check_out': null,
      'second_shift_status': 'Not Checked In',
      'is_checked_in': false,
    };
    notifyListeners();
  }

  Future<Map<String, dynamic>> submitAttendanceCorrection({
    required String gymId,
    required String userId,
    required String? logId,
    required String date,
    required String checkIn,
    required String? checkOut,
    required String reason,
  }) async {
    if (!SupabaseService.isInitialized) {
      return {'success': false, 'reason': 'Supabase not initialized'};
    }
    try {
      final response = await SupabaseService.client.rpc('submit_attendance_correction', params: {
        'p_gym_id': gymId,
        'p_staff_user_id': userId,
        'p_log_id': logId,
        'p_date': date,
        'p_check_in': checkIn,
        'p_check_out': checkOut,
        'p_reason': reason,
      });
      await fetchAttendanceCorrections(gymId);
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      print('submitAttendanceCorrection error: $e');
      return {'success': false, 'reason': e.toString()};
    }
  }

  Future<Map<String, dynamic>> reviewAttendanceCorrection({
    required String requestId,
    required String status,
    required String gymId,
  }) async {
    if (!SupabaseService.isInitialized) {
      return {'success': false, 'reason': 'Supabase not initialized'};
    }
    try {
      final currentUserId = SupabaseService.client.auth.currentUser?.id;
      if (currentUserId == null) {
        return {'success': false, 'reason': 'User not authenticated'};
      }
      final response = await SupabaseService.client.rpc('review_attendance_correction', params: {
        'p_request_id': requestId,
        'p_status': status,
        'p_reviewer_id': currentUserId,
      });
      await fetchAttendanceCorrections(gymId);
      await fetchAttendanceLogsFromSupabase();
      await fetchOwnerDashboardStats(gymId);
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      print('reviewAttendanceCorrection error: $e');
      return {'success': false, 'reason': e.toString()};
    }
  }

  Future<void> initializeDefaultRoles(String gymId) async {
    if (!SupabaseService.isInitialized) return;
    try {
      final List<String> defaultActive = ['Trainer', 'Personal Trainer', 'Manager', 'Receptionist'];
      final List<String> defaultOptional = [
        'Nutritionist', 'Sales Executive', 'Accountant', 'Cleaner',
        'Housekeeping', 'Security', 'Yoga Trainer', 'CrossFit Coach',
        'Zumba Trainer', 'Swimming Coach', 'Massage Therapist', 'Other'
      ];

      final List<Map<String, dynamic>> data = [];
      for (var role in defaultActive) {
        data.add({
          'gym_id': gymId,
          'role_name': role,
          'is_default': true,
          'is_enabled': true,
          'is_custom': false,
          'icon': _getIconForRole(role),
        });
      }
      for (var role in defaultOptional) {
        data.add({
          'gym_id': gymId,
          'role_name': role,
          'is_default': true,
          'is_enabled': false,
          'is_custom': false,
          'icon': _getIconForRole(role),
        });
      }

      await SupabaseService.client.from('staff_roles').insert(data);
    } catch (e) {
      print('initializeDefaultRoles error: $e');
    }
  }

  String _getIconForRole(String role) {
    switch (role.toLowerCase()) {
      case 'trainer':
      case 'personal trainer':
      case 'yoga trainer':
      case 'crossfit coach':
      case 'zumba trainer':
      case 'swimming coach':
        return 'fitness_center_rounded';
      case 'manager':
        return 'business_center_rounded';
      case 'receptionist':
        return 'account_box_rounded';
      case 'accountant':
        return 'calculate_rounded';
      case 'nutritionist':
        return 'restaurant_menu_rounded';
      default:
        return 'badge_outlined';
    }
  }

  Future<List<Map<String, dynamic>>> fetchStaffRoles(String gymId) async {
    if (!SupabaseService.isInitialized) return [];
    try {
      final List response = await SupabaseService.client
          .from('staff_roles')
          .select()
          .eq('gym_id', gymId);

      if (response.isEmpty) {
        await initializeDefaultRoles(gymId);
        final List retryResponse = await SupabaseService.client
            .from('staff_roles')
            .select()
            .eq('gym_id', gymId);
        return List<Map<String, dynamic>>.from(retryResponse);
      }
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('fetchStaffRoles error: $e');
      return [];
    }
  }

  Future<void> saveStaffRoles(List<Map<String, dynamic>> roles) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.from('staff_roles').upsert(roles);
    } catch (e) {
      print('saveStaffRoles error: $e');
      rethrow;
    }
  }

  Future<void> addCustomStaffRole(String gymId, String name, String icon) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.from('staff_roles').insert({
        'gym_id': gymId,
        'role_name': name,
        'icon': icon,
        'is_default': false,
        'is_enabled': true,
        'is_custom': true,
      });
    } catch (e) {
      print('addCustomStaffRole error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getOrCreateSalaryDraft(String gymId, String staffId, String salaryMonth) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final List<dynamic> response = await SupabaseService.client.rpc(
        'get_or_create_salary_draft',
        params: {
          'p_gym_id': gymId,
          'p_staff_id': staffId,
          'p_salary_month': salaryMonth,
        },
      );
      if (response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('getOrCreateSalaryDraft error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchSalaryAdjustments(String draftId) async {
    if (!SupabaseService.isInitialized) return [];
    try {
      final response = await SupabaseService.client
          .from('salary_adjustments')
          .select()
          .eq('salary_draft_id', draftId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('fetchSalaryAdjustments error: $e');
      return [];
    }
  }

  Future<void> addSalaryAdjustment({
    required String gymId,
    required String draftId,
    required String type,
    required double amount,
    required String reason,
    required String userId,
  }) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.rpc(
        'add_salary_adjustment',
        params: {
          'p_gym_id': gymId,
          'p_draft_id': draftId,
          'p_type': type,
          'p_amount': amount,
          'p_reason': reason,
          'p_user_id': userId,
        },
      );
    } catch (e) {
      print('addSalaryAdjustment error: $e');
      rethrow;
    }
  }

  Future<void> paySalaryDraft({
    required String draftId,
    required String paymentMode,
    required String notes,
  }) async {
    final index = _salaryDrafts.indexWhere((d) => d['id'] == draftId);
    if (index >= 0) {
      final updatedDraft = Map<String, dynamic>.from(_salaryDrafts[index]);
      updatedDraft['status'] = 'Paid';
      _salaryDrafts[index] = updatedDraft;
      await _storage.setString(LocalStorageService.keySalaryDrafts, jsonEncode(_salaryDrafts));
      notifyListeners();
    }

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.rpc('pay_salary_draft', params: {
          'p_draft_id': draftId,
          'p_payment_mode': paymentMode,
          'p_notes': notes,
        });
        _resetNetworkError();
        final gymId = _storage.getGymInfo()?['id'];
        if (gymId != null) {
          await fetchStaffFromSupabase();
          await fetchSalaryDraftsFromSupabase(gymId);
        }
        triggerBackgroundSync();
        return;
      } catch (e) {
        print('Direct pay_salary_draft error: $e');
      }
    }

    await paySalaryDraftOffline(
      draftId: draftId,
      paymentMode: paymentMode,
      notes: notes,
    );
  }

  Future<Map<String, dynamic>?> fetchTrainerClientDetail(String staffId, String memberId) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final response = await SupabaseService.client.rpc(
        'get_trainer_client_detail',
        params: {'p_staff_id': staffId, 'p_member_id': memberId},
      );
      if (response == null) return null;
      if (response is Map<String, dynamic>) return response;
      if (response is Map) return Map<String, dynamic>.from(response);
      return null;
    } catch (e) {
      print('fetchTrainerClientDetail error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> updateMemberMeasurements(
    String staffId,
    String memberId,
    Map<String, dynamic> measurements,
  ) async {
    if (!SupabaseService.isInitialized) {
      throw Exception('Supabase not initialized');
    }
    try {
      final response = await SupabaseService.client.rpc(
        'update_member_measurements',
        params: {
          'p_staff_id': staffId,
          'p_member_id': memberId,
          'p_measurements': measurements,
        },
      );
      if (response is Map<String, dynamic>) return response;
      if (response is Map) return Map<String, dynamic>.from(response);
      return {'measurements': measurements};
    } catch (e) {
      print('updateMemberMeasurements error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchStaffCommissions(String staffId, {bool pendingOnly = true}) async {
    if (!SupabaseService.isInitialized) return [];
    try {
      var query = SupabaseService.client
          .from('commission_ledger')
          .select()
          .eq('staff_id', staffId);
      
      if (pendingOnly) {
        query = query.eq('status', 'Pending');
      }
      
      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('fetchStaffCommissions error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchStaffLeaves(String staffId) async {
    if (!SupabaseService.isInitialized) return [];
    try {
      final response = await SupabaseService.client
          .from('leave_requests')
          .select()
          .eq('staff_id', staffId)
          .eq('status', 'Approved');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('fetchStaffLeaves error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchStaffSalaryMonthLeaveDetails(String staffId, String salaryMonth) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final response = await SupabaseService.client.rpc(
        'get_staff_salary_month_leave_details',
        params: {
          'p_staff_id': staffId,
          'p_salary_month': salaryMonth,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      print('fetchStaffSalaryMonthLeaveDetails error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchPaidSalaryDraftDetails(String draftId) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final response = await SupabaseService.client.rpc(
        'get_paid_salary_draft_details',
        params: {
          'p_draft_id': draftId,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      print('fetchPaidSalaryDraftDetails error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GYM RULES & MEMBER AGREEMENTS (PHASE 09)
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> fetchGymRules(String gymId) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final data = await SupabaseService.client
          .from('gym_rules')
          .select()
          .eq('gym_id', gymId)
          .maybeSingle();
      return data;
    } catch (e) {
      print('fetchGymRules error: $e');
      return null;
    }
  }

  Future<bool> saveGymRules(String gymId, Map<String, dynamic> rulesData, {int version = 1}) async {
    if (!SupabaseService.isInitialized) return false;
    try {
      final user = SupabaseService.client.auth.currentUser;
      final payload = {
        'gym_id': gymId,
        'rules_data': rulesData,
        'version': version,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': user?.id,
      };

      await SupabaseService.client
          .from('gym_rules')
          .upsert(payload, onConflict: 'gym_id');

      notifyListeners();
      return true;
    } catch (e) {
      print('saveGymRules error: $e');
      return false;
    }
  }

  Future<List<MemberAgreementRecord>> fetchGymAgreements(String gymId) async {
    if (!SupabaseService.isInitialized || gymId.trim().isEmpty) return [];
    try {
      // 1. Try secure RPC first
      try {
        final rpcRes = await SupabaseService.client
            .rpc('get_gym_rule_agreements', params: {'p_gym_id': gymId.trim()});
        if (rpcRes != null && rpcRes is List && rpcRes.isNotEmpty) {
          return rpcRes
              .map((row) => MemberAgreementRecord.fromMap(Map<String, dynamic>.from(row)))
              .toList();
        }
      } catch (rpcErr) {
        print('fetchGymAgreements RPC error: $rpcErr');
      }

      // 2. Direct table select fallback
      final data = await SupabaseService.client
          .from('member_rule_agreements')
          .select()
          .eq('gym_id', gymId.trim())
          .order('agreed_at', ascending: false);

      return data.map((row) => MemberAgreementRecord.fromMap(Map<String, dynamic>.from(row))).toList();
    } catch (e) {
      print('fetchGymAgreements error: $e');
      return [];
    }
  }

  Future<MemberAgreementRecord?> fetchMemberAgreement(String gymId, String memberId) async {
    if (!SupabaseService.isInitialized || gymId.trim().isEmpty || memberId.trim().isEmpty) return null;
    try {
      // 1. Try secure RPC first
      try {
        final rpcRes = await SupabaseService.client
            .rpc('get_gym_rule_agreements', params: {'p_gym_id': gymId.trim()});
        if (rpcRes != null && rpcRes is List) {
          final match = rpcRes.cast<Map<String, dynamic>>().firstWhere(
            (row) => row['member_id']?.toString() == memberId.trim(),
            orElse: () => <String, dynamic>{},
          );
          if (match.isNotEmpty) {
            return MemberAgreementRecord.fromMap(match);
          }
        }
      } catch (rpcErr) {
        print('fetchMemberAgreement RPC fallback: $rpcErr');
      }

      // 2. Direct select fallback
      final data = await SupabaseService.client
          .from('member_rule_agreements')
          .select()
          .eq('gym_id', gymId.trim())
          .eq('member_id', memberId.trim())
          .order('agreed_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;
      return MemberAgreementRecord.fromMap(Map<String, dynamic>.from(data));
    } catch (e) {
      print('fetchMemberAgreement error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchGymCustomRules(String gymId) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final data = await SupabaseService.client
          .from('gym_rules')
          .select('rules_data, version, updated_at')
          .eq('gym_id', gymId)
          .maybeSingle();
      if (data == null) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      print('fetchGymCustomRules error: $e');
      return null;
    }
  }

  Future<bool> saveGymCustomRules(String gymId, Map<String, dynamic> rulesData) async {
    if (!SupabaseService.isInitialized) return false;
    try {
      await SupabaseService.client.rpc('save_gym_custom_rules', params: {
        'p_gym_id': gymId,
        'p_rules_data': rulesData,
      });
      return true;
    } catch (e) {
      print('saveGymCustomRules error: $e');
      return false;
    }
  }
}

