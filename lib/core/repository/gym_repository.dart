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
  bool _loadingDashboardStats = false;

  Map<String, dynamic>? _todayAttendanceDetails;
  Map<String, dynamic>? get todayAttendanceDetails => _todayAttendanceDetails;

  bool get loadingDashboardStats => _loadingDashboardStats;

  int get activeMembersCount {
    final localActive = _members.where((m) => m.status == 'Active').length;
    return _dbActiveMembers > 0 ? _dbActiveMembers : localActive;
  }

  int get totalMembersCount {
    final localTotal = _members.length;
    return _dbTotalMembers > 0 ? _dbTotalMembers : localTotal;
  }

  double get monthlyRevenue {
    final localRevenue = _transactions
        .where((t) => t.type == 'Revenue')
        .fold(0.0, (sum, t) => sum + t.amount);
    return _dbMonthlyRevenue > 0 ? _dbMonthlyRevenue : localRevenue;
  }

  int get todayAttendanceCount => _dbTodayAttendance;

  int get expiringTodayCount => _dbExpiringToday;
  int get expiring15DaysCount => _dbExpiring15Days;
  int get pendingLeavesCount => _dbPendingLeaves;
  int get pendingHolidaysCount => _dbPendingHolidays;

  double get attendancePercentage {
    final active = activeMembersCount;
    return active > 0 ? (_dbTodayAttendance / active) * 100 : 0.0;
  }

  // Raw JSON caches to prevent redundant notifyListeners calls
  String _lastMembersRaw = '';
  String _lastStaffRaw = '';
  String _lastTransactionsRaw = '';

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

  List<AttendanceAlert> get alerts => _alerts;
  List<AttendanceCorrectionRequest> get corrections => _corrections;
  Map<String, dynamic> get dashboardStats => _dashboardStats;

  String get _workoutsKey => 'gymos_workouts_${_storage.getGymInfo()?['id'] ?? 'default'}';
  String get _dietsKey => 'gymos_diets_${_storage.getGymInfo()?['id'] ?? 'default'}';
  String get _membershipsKey => 'gymos_memberships_${_storage.getGymInfo()?['id'] ?? 'default'}';
  String get _attendanceKey => 'gymos_attendance_${_storage.getGymInfo()?['id'] ?? 'default'}';
  String get _goalsKey => 'gymos_fitness_goals_${_storage.getGymInfo()?['id'] ?? 'default'}';
  String get _customFieldsKey => 'gymos_custom_fields_${_storage.getGymInfo()?['id'] ?? 'default'}';

  GymRepository(this._storage) {
    _loadAllFromStorage();
    _startSyncTimer();
    if (SupabaseService.isInitialized) {
      _authStateSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        final session = data.session;
        if (event == AuthChangeEvent.signedOut || session == null) {
          clearAllData();
        } else if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.tokenRefreshed) {
          reloadForActiveGym();
        }
      });
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      await syncAllFromSupabase();
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
              print('Supabase Realtime Event Received: ${payload.eventType}');
              
              if (payload.eventType == PostgresChangeEvent.insert &&
                  payload.table == 'attendance_logs') {
                final newRecord = payload.newRecord;
                final userType = newRecord['user_type'] as String?;
                final checkIn = newRecord['check_in'] as String?;

                if (userType == 'Staff' && checkIn != null) {
                  final userId = newRecord['user_id'] as String?;
                  
                  // Match staff name
                  final matchingStaff = _staff.where((s) => s.userId == userId).toList();
                  final staffName = matchingStaff.isNotEmpty ? matchingStaff.first.name : 'Staff';
                  
                  final parsedTime = DateTime.tryParse(checkIn)?.toLocal() ?? DateTime.now();
                  final formattedTime = DateFormat('hh:mm a').format(parsedTime);

                  NotificationService.showNotification(
                    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    title: 'Staff Checked In',
                    body: '$staffName checked in, time is $formattedTime.',
                  );
                }
              }
              
              syncAllFromSupabase();
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
      }
    } catch (e) {
      _handleNetworkError('fetchDashboardStatsFromSupabase', e);
    } finally {
      _loadingDashboardStats = false;
      notifyListeners();
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

    _lastMembersRaw = '';
    _lastStaffRaw = '';
    _lastTransactionsRaw = '';
    _lastWorkoutsRaw = null;

    _hasNetworkConnectionError = false;

    notifyListeners();
  }

  LocalStorageService get storage => _storage;

  Future<void> reloadForActiveGym() async {
    _loadAllFromStorage();
    await fetchMembersFromSupabase();
    await fetchStaffFromSupabase();
    await fetchTransactionsFromSupabase();
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
  }

  // --- Members ---
  List<Member> getMembers() => List.unmodifiable(_members);

  void _loadMembers() {
    _members = []; // Only load from Supabase database
  }

  Future<void> saveMember(Member member) async {
    if (!SupabaseService.isInitialized) {
      throw Exception('Supabase client is not initialized. Please connect to the database first.');
    }
    if (!_isValidUUID(member.id)) {
      throw Exception('Invalid member ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) {
      throw Exception('Active Gym ID not found. Please select or create a gym.');
    }
    try {
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
      await SupabaseService.client.from('members').upsert(data);

      // Handle PT assignment registration automatically when trainer is selected
      if (member.ptMember && _isValidUUID(member.ptTrainer)) {
        // Fetch current active assignment if any to see if trainer changed
        final activeAssignments = await SupabaseService.client
            .from('pt_assignments')
            .select()
            .eq('member_id', member.id)
            .eq('assignment_status', 'Active');
        
        bool isNewAssignmentNeeded = true;
        
        if (activeAssignments.isNotEmpty) {
          final existing = activeAssignments.first;
          if (existing['staff_id'] == member.ptTrainer) {
            isNewAssignmentNeeded = false;
          } else {
            // Deactivate old assignment
            await SupabaseService.client
                .from('pt_assignments')
                .update({'assignment_status': 'Inactive', 'deleted_at': DateTime.now().toIso8601String()})
                .eq('id', existing['id']);
          }
        }
        
        if (isNewAssignmentNeeded) {
          // Fetch snapshotted commission rate from Staff details
          final staffRes = await SupabaseService.client
              .from('staff')
              .select('commission_percentage')
              .eq('id', member.ptTrainer)
              .maybeSingle();
              
          final double commissionPercentage = (staffRes?['commission_percentage'] as num?)?.toDouble() ?? 0.0;
          
          await SupabaseService.client.from('pt_assignments').insert({
            'gym_id': gymId,
            'member_id': member.id,
            'staff_id': member.ptTrainer,
            'commission_percentage': commissionPercentage,
            'assignment_status': 'Active',
            'pt_start_date': DateTime.now().toIso8601String().substring(0, 10),
            'created_by': SupabaseService.client.auth.currentUser?.id,
          });
        }
      } else {
        // Deactivate active assignments if PT toggled off
        await SupabaseService.client
            .from('pt_assignments')
            .update({'assignment_status': 'Inactive', 'deleted_at': DateTime.now().toIso8601String()})
            .eq('member_id', member.id)
            .eq('assignment_status', 'Active');
      }

      await fetchMembersFromSupabase();
    } catch (e) {
      print('Supabase saveMember error: $e');
      throw Exception('Failed to save member: $e');
    }
  }

  bool _isValidUUID(String? str) {
    if (str == null || str.isEmpty) return false;
    final regExp = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return regExp.hasMatch(str);
  }

  Future<void> deleteMember(String id) async {
    if (SupabaseService.isInitialized && _isValidUUID(id)) {
      try {
        await SupabaseService.client.from('members').delete().eq('id', id);
        await fetchMembersFromSupabase();
      } catch (e) {
        print('Supabase deleteMember error: $e');
      }
    }
  }

  // --- Staff ---
  List<Staff> getStaff() => List.unmodifiable(_staff);

  void _loadStaff() {
    _staff = []; // Only load from Supabase database
  }

  Future<void> saveStaff(Staff staff) async {
    if (!SupabaseService.isInitialized) {
      throw Exception('Supabase client is not initialized. Please connect to the database first.');
    }
    if (!_isValidUUID(staff.id)) {
      throw Exception('Invalid staff ID format.');
    }
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) {
      throw Exception('Active Gym ID not found. Please select or create a gym.');
    }
    try {
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
      await SupabaseService.client.from('staff').upsert(data);

      // Save staff shift assignment only if it has changed from current active assignment
      try {
        final activeRes = await SupabaseService.client
            .from('staff_shift_assignments')
            .select('assignment_type')
            .eq('staff_id', staff.id)
            .eq('status', 'Active')
            .maybeSingle();
            
        final currentActiveShift = activeRes?['assignment_type'];
        if (currentActiveShift != staff.shift) {
          String? shiftId;
          if (staff.shift != 'Both Shifts') {
            final shiftRes = await SupabaseService.client
                .from('gym_shifts')
                .select('id')
                .eq('gym_id', gymId)
                .eq('shift_type', staff.shift)
                .maybeSingle();
            if (shiftRes != null) {
              shiftId = shiftRes['id'];
            }
          }
          
          // Deactivate old active shift assignments for this staff
          await SupabaseService.client
              .from('staff_shift_assignments')
              .update({'status': 'Inactive'})
              .eq('staff_id', staff.id)
              .eq('status', 'Active');

          await SupabaseService.client.from('staff_shift_assignments').insert({
            'staff_id': staff.id,
            'gym_id': gymId,
            'shift_id': shiftId,
            'assignment_type': staff.shift,
            'effective_from': DateTime.now().toLocal().toIso8601String().substring(0, 10), // YYYY-MM-DD
            'status': 'Active'
          });
        }
      } catch (e) {
        print('Error handling staff shift assignment: $e');
      }

      await fetchStaffFromSupabase();
    } catch (e) {
      print('Supabase saveStaff error: $e');
      throw Exception('Failed to save staff: $e');
    }
  }

  Future<void> deleteStaff(String id) async {
    if (SupabaseService.isInitialized && _isValidUUID(id)) {
      try {
        await SupabaseService.client.from('staff').delete().eq('id', id);
        await fetchStaffFromSupabase();
      } catch (e) {
        print('Supabase deleteStaff error: $e');
      }
    }
  }

  // --- Workouts ---
  List<WorkoutPlan> getWorkouts() => List.unmodifiable(_workouts);

  void _loadWorkouts() {
    _workouts = [];
  }

  String? _lastWorkoutsRaw;

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
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchWorkoutsFromSupabase', e);
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
      final List decoded = jsonDecode(raw);
      _diets = decoded.map((e) => DietPlan.fromJson(e)).toList();
    } else {
      _diets = [];
    }
  }

  Future<void> saveDiet(DietPlan diet) async {
    final index = _diets.indexWhere((e) => e.id == diet.id);
    if (index >= 0) {
      _diets[index] = diet;
    } else {
      _diets.add(diet);
    }
    await _storage.setString(_dietsKey, jsonEncode(_diets.map((e) => e.toJson()).toList()));
  }

  Future<void> deleteDiet(String id) async {
    _diets.removeWhere((e) => e.id == id);
    await _storage.setString(_dietsKey, jsonEncode(_diets.map((e) => e.toJson()).toList()));
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
    _transactions = []; // Loaded dynamically from Supabase
  }

  Future<void> saveTransaction(FinanceTransaction tx) async {
    if (!SupabaseService.isInitialized) {
      throw Exception('Supabase client is not initialized.');
    }
    final gymId = _storage.getGymInfo()?['id'];
    if (gymId == null) {
      throw Exception('Active Gym ID not found.');
    }
    final user = SupabaseService.client.auth.currentUser;
    try {
      final Map<String, dynamic> data = {
        'gym_id': gymId,
        'amount': tx.amount,
        'type': tx.type,
        'category': tx.category,
        'payment_method': tx.paymentMethod,
        'reference_id': tx.referenceId,
        'created_by': user?.id,
        'created_by_info': tx.createdByInfo.isNotEmpty ? tx.createdByInfo : 'Owner',
        'notes': tx.notes,
      };
      if (tx.transactionDate.isNotEmpty) {
        data['transaction_date'] = tx.transactionDate;
      }
      if (tx.expenseDate.isNotEmpty) {
        data['expense_date'] = tx.expenseDate;
      }
      if (tx.revenueDate.isNotEmpty) {
        data['revenue_date'] = tx.revenueDate;
      }
      if (tx.entryDate.isNotEmpty) {
        data['entry_date'] = tx.entryDate;
      }
      if (_isValidUUID(tx.id)) {
        data['id'] = tx.id;
      }
      await SupabaseService.client.from('finance_transactions').upsert(data);
      await fetchTransactionsFromSupabase();
      notifyListeners();
    } catch (e) {
      print('Supabase saveTransaction error: $e');
      throw Exception('Failed to save transaction: $e');
    }
  }

  Future<void> deleteTransaction(String id) async {
    if (SupabaseService.isInitialized && _isValidUUID(id)) {
      try {
        await SupabaseService.client.from('finance_transactions').delete().eq('id', id);
        await fetchTransactionsFromSupabase();
      } catch (e) {
        print('Supabase deleteTransaction error: $e');
      }
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
  List<RecentActivity> getRecentActivities() => List.unmodifiable(_recentActivities);

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
      return response;
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

      await SupabaseService.client
          .from(isStaff ? 'staff' : 'members')
          .update({'status': 'Pending Activation'})
          .eq('id', recordId);
    } catch (e) {
      print('generateInvitation Supabase error: $e');
      throw Exception('Failed to generate invitation: $e');
    }
    return code;
  }

  Future<String> unlinkAccount(String recordId, bool isStaff) async {
    final gymId = _storage.getGymInfo()?['id'];
    String name = '';
    String phone = '';

    if (SupabaseService.isInitialized && gymId != null) {
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
      } catch (e) {
        print('unlinkAccount Supabase error: $e');
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
            _members = response.map((e) => Member.fromJson(e)).toList();
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
            _staff = loadedStaff;
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
            _transactions = response.map((e) => FinanceTransaction.fromJson(e)).toList();
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchTransactionsFromSupabase', e);
        }
      }
    }
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
            notifyListeners();
          }
        } catch (e) {
          _handleNetworkError('fetchAttendanceSettingsFromSupabase', e);
        }
      }
    }
  }

  Future<void> saveAttendanceSettingsToSupabase(GymAttendanceSettings settings) async {
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('attendance_settings').upsert(settings.toJson());
        _attendanceSettings = settings;
        notifyListeners();
      } catch (e) {
        _handleNetworkError('saveAttendanceSettingsToSupabase', e);
        throw Exception('Failed to save settings: $e');
      }
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
          return "http://localhost:3000/?display_id=$publicId";
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
          _attendance = response.map((e) => AttendanceRecord.fromJson(e)).toList();
          await _storage.setString(_attendanceKey, jsonEncode(_attendance.map((e) => e.toJson()).toList()));
          notifyListeners();
        } catch (e) {
          _handleNetworkError('fetchAttendanceLogsFromSupabase', e);
        }
      }
    }
  }

  void _saveTodayDetailsToStorage() {
    if (_todayAttendanceDetails != null) {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final key = 'today_att_details_$todayStr';
      _storage.setString(key, jsonEncode(_todayAttendanceDetails));
    }
  }

  void _loadTodayDetailsFromStorage() {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final key = 'today_att_details_$todayStr';
    final raw = _storage.getString(key);
    if (raw != null) {
      try {
        _todayAttendanceDetails = Map<String, dynamic>.from(jsonDecode(raw));
        notifyListeners();
      } catch (_) {}
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
        notifyListeners();
      } catch (e) {
        _handleNetworkError('fetchAttendanceCorrections', e);
      }
    }
  }

  Future<void> fetchTodayAttendanceDetails(String userId, String gymId) async {
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
        _saveTodayDetailsToStorage();
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
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.rpc(
        'pay_salary_draft_v2',
        params: {
          'p_draft_id': draftId,
          'p_payment_mode': paymentMode,
          'p_notes': notes,
        },
      );
    } catch (e) {
      print('paySalaryDraft error: $e');
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
}
