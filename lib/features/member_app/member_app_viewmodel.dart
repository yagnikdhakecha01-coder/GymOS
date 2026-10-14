import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/diet_plan.dart';
import '../../core/models/gym_rules_model.dart';

class MemberAppViewModel extends ChangeNotifier {
  // ── Auth State ──
  bool _isLoggedIn = false;
  bool _isMemberCodeVerified = false;
  bool _isLoading = false;
  RealtimeChannel? _memberSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;

  // ── Gym Rules & Agreement (Phase 09) ──
  bool _hasAgreedRules = false;
  bool _isCheckingAgreement = false;
  bool _isSubmittingAgreement = false;
  MemberAgreementRecord? _agreementRecord;

  bool get hasAgreedRules => _hasAgreedRules;
  bool get isCheckingAgreement => _isCheckingAgreement;
  bool get isSubmittingAgreement => _isSubmittingAgreement;
  MemberAgreementRecord? get agreementRecord => _agreementRecord;
  bool get isLoadingMemberData => _isLoadingMemberData;

  // ── Member Profile ──
  String _memberName = '';
  String _memberId = '';
  String _gymName = '';
  String _gymLogoUrl = '';
  List<dynamic>? _customRulesData;
  int _currentRulesVersion = 1;
  String _memberAvatar = 'assets/images/member/avatar_default.png';
  String _joinDate = '';
  int _notificationCount = 0;

  // Body Stats & Fitness Goals (remain blank until entered)
  String _weight = '';
  String _height = '';
  String _bodyFat = '';
  String _fitnessGoal = '';

  // ── Streak Data ──
  int _currentStreak = 0;
  int _lastStreak = 0;
  List<bool> _weekAttendance = [false, false, false, false, false, false, false];
  List<String> _weekDays = ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon'];
  List<int> _weekDates = [22, 23, 24, 25, 26, 27, 28];

  // ── Statistics ──
  int _attendancePercentage = 0;
  int _membershipDaysLeft = 0;
  double _pendingAmount = 0.0;
  List<String> _declaredHolidays = [];

  // ── Today's Training ──
  String _todayMuscleGroup = 'Chest Day'; // Chest, Back, Leg, Shoulder, Arm, Rest, Cardio
  List<String> _todaySplits = ['Chest Day'];
  Map<String, dynamic> _weeklyWorkoutSchedule = {};
  String _gymId = '';
  bool _isTrainingCompleted = false;

  // Training History List
  final List<Map<String, dynamic>> _trainingHistory = [];

  // ── Diet ──
  bool _isDietAvailable = true;
  double _waterIntake = 2.5; // in Liters
  double _waterGoal = 4.0;
  int _caloriesIntake = 1850;
  int _caloriesGoal = 2500;
  int _proteinIntake = 120;
  int _proteinGoal = 160;

  // ── Membership ──
  String _membershipPlan = 'Gold Plan';
  String _membershipStatus = 'Active';
  String _membershipStartDate = '01 Jan 2026';
  String _membershipEndDate = '29 May 2026';
  String _rawMembershipStartDate = '';
  String _rawMembershipEndDate = '';
  int _membershipTimeRemaining = 48;
  String _planDuration = '6 Months';
  String _amountPaid = '₹12,000';
  String _nextDue = '30 May 2026';

  // Payment History
  final List<Map<String, dynamic>> _paymentHistory = [];

  // ── Achievements & Milestones ──
  int _currentLevel = 1;
  int _currentXP = 0;
  int _nextLevelXP = 100;
  int _nextMilestoneTarget = 30;
  int _currentMilestoneProgress = 28;
  String _currentTitle = '🌱 New Member';

  // Achievements
  final List<Map<String, dynamic>> _achievements = [];

  // ── Attendance Details ──
  int _presentDays = 0;
  int _absentDays = 0;
  int _lateDays = 0;
  List<int> _attendedDaysOfCurrentMonth = [];
  Map<String, String> _attendanceMapByIsoDate = {};

  final List<Map<String, dynamic>> _attendanceHistory = [
    {'date': '17 May 2026', 'checkIn': '07:32 AM', 'checkOut': '09:00 AM', 'status': 'Present'},
    {'date': '16 May 2026', 'checkIn': '07:45 AM', 'checkOut': '09:15 AM', 'status': 'Present'},
    {'date': '15 May 2026', 'checkIn': '08:05 AM', 'checkOut': '09:30 AM', 'status': 'Late'},
    {'date': '14 May 2026', 'checkIn': '07:30 AM', 'checkOut': '08:45 AM', 'status': 'Present'},
    {'date': '13 May 2026', 'checkIn': '07:35 AM', 'checkOut': '09:00 AM', 'status': 'Present'},
  ];

  String _attendanceMethod = 'Static QR';
  bool _isAttendanceEnabled = true;

  // ── Motivational Quotes ──
  final List<String> _quotes = [
    'Consistency is what transforms average into excellence.',
    'The only bad workout is the one that didn\'t happen.',
    'Your body can stand almost anything. It\'s your mind you have to convince.',
    'Don\'t stop when you\'re tired. Stop when you\'re done.',
    'Strength does not come from the body. It comes from the will.',
    'The pain you feel today will be the strength you feel tomorrow.',
    'Success starts with self-discipline.',
    'Push yourself because no one else is going to do it for you.',
  ];

  String _currentQuote = '';

  // ── Check-in ──
  String _checkInTime = '';
  String _checkInDate = '';
  String _checkInDateIso = '';
  bool _checkedInToday = false;
  bool _isCheckingIn = false;

  MemberAppViewModel() {
    _generateCurrentWeek();
    _currentQuote = _quotes[Random().nextInt(_quotes.length)];
    _loadPersistedState();
    if (SupabaseService.isInitialized) {
      _authStateSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) async {
        final event = data.event;
        final session = data.session;
        if (event == AuthChangeEvent.signedOut) {
          clearAllDataInMemory();
        } else if ((event == AuthChangeEvent.signedIn ||
                    event == AuthChangeEvent.tokenRefreshed ||
                    event == AuthChangeEvent.initialSession) &&
                   session != null) {
          final prefs = await SharedPreferences.getInstance();
          final activeRole = prefs.getString('gymos_user_role');
          // CRITICAL: Never automatically hijack session or reload member data if user is an active Owner or Staff!
          if (activeRole == 'member') {
            loadMemberDataFromSupabase();
          }
        }
      });
    }
  }

  // ── Getters ──
  bool get isLoggedIn => _isLoggedIn;
  bool get isMemberCodeVerified => _isMemberCodeVerified;
  bool get isLoading => _isLoading;

  String _assignedWorkoutId = '';
  String _assignedDietId = '';
  String _assignedWorkoutTitle = '';
  String _assignedDietTitle = '';
  DietPlan? _assignedDietPlan;

  String get assignedWorkoutId => _assignedWorkoutId;
  String get assignedDietId => _assignedDietId;
  String get assignedWorkoutTitle => _assignedWorkoutTitle;
  String get assignedDietTitle => _assignedDietTitle;
  DietPlan? get assignedDietPlan => _assignedDietPlan;

  String get memberName => _memberName;
  String get memberId => _memberId;
  String get gymId => _gymId;
  String get gymName => _gymName;
  String get gymLogoUrl => _gymLogoUrl;
  List<dynamic>? get customRulesData => _customRulesData;
  int get currentRulesVersion => _currentRulesVersion;
  String get memberAvatar => _memberAvatar;
  String get joinDate => _joinDate;
  int get notificationCount => _notificationCount;

  String get weight => _weight;
  String get height => _height;
  String get bodyFat => _bodyFat;
  String get fitnessGoal => _fitnessGoal;

  int get currentStreak => _currentStreak;
  int get lastStreak => _lastStreak;
  List<bool> get weekAttendance => _weekAttendance;
  List<String> get weekDays => _weekDays;
  List<int> get weekDates => _weekDates;

  int get attendancePercentage => _attendancePercentage;
  int get membershipDaysLeft => _membershipDaysLeft;
  double get pendingAmount => _pendingAmount;
  List<String> get declaredHolidays => _declaredHolidays;
  String get attendanceMethod => _attendanceMethod;
  bool get isAttendanceEnabled => _isAttendanceEnabled;
  bool get isBiometricAttendanceOnly => _attendanceMethod == 'Biometric';
  bool get hasBiometricAttendance => _attendanceMethod == 'Biometric' || _attendanceMethod == 'QR + Biometric';

  int get totalGymDays {
    final now = DateTime.now();
    int total = 0;
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    for (int i = 1; i <= lastDay; i++) {
      if (DateTime(now.year, now.month, i).weekday != DateTime.sunday) {
        total++;
      }
    }
    return total;
  }

  String get todayMuscleGroup => _todayMuscleGroup;
  List<String> get todaySplits => _todaySplits;
  Map<String, dynamic> get weeklyWorkoutSchedule => _weeklyWorkoutSchedule;
  bool get hasAssignedWorkout => _assignedWorkoutId.isNotEmpty && (_weeklyWorkoutSchedule.isNotEmpty || _assignedWorkoutTitle.isNotEmpty);
  bool get isRestDay {
    if (!hasAssignedWorkout) return false;
    final normalized = _todayMuscleGroup.toLowerCase();
    if (normalized == 'rest day' || normalized.contains('rest & recovery')) return true;
    if (_todaySplits.length == 1 && _todaySplits.first.toLowerCase().contains('rest')) return true;
    return false;
  }

  String get todayWorkoutImage {
    if (!hasAssignedWorkout || _todayMuscleGroup == 'No Plan Assigned') {
      return 'assets/images/member/rest_day.png';
    }
    final firstSplit = _todaySplits.isNotEmpty ? _todaySplits.first : _todayMuscleGroup;
    final group = firstSplit.toLowerCase();
    if (group.contains('chest')) return 'assets/images/member/chest_day.png';
    if (group.contains('leg')) return 'assets/images/member/leg_day.png';
    if (group.contains('shoulder')) return 'assets/images/member/shoulder_day.png';
    if (group.contains('back')) return 'assets/images/member/back_day.png';
    if (group.contains('arm') || group.contains('tricep') || group.contains('bicep') || group.contains('trisep')) return 'assets/images/member/arm_day.png';
    if (group.contains('cardio') || group.contains('aerobic') || group.contains('arobix') || group.contains('steam')) return 'assets/images/member/cardio_day.png';
    return 'assets/images/member/rest_day.png';
  }
  bool get isTrainingCompleted => _isTrainingCompleted;
  List<Map<String, dynamic>> get trainingHistory => _trainingHistory;

  bool get isDietAvailable => _isDietAvailable;
  double get waterIntake => _waterIntake;
  double get waterGoal => _waterGoal;
  int get caloriesIntake => _caloriesIntake;
  int get caloriesGoal => _caloriesGoal;
  int get proteinIntake => _proteinIntake;
  int get proteinGoal => _proteinGoal;

  String get membershipPlan => _membershipPlan;
  String get membershipStatus => _membershipStatus;
  String get membershipStartDate => _membershipStartDate;
  String get membershipEndDate => _membershipEndDate;
  DateTime? get membershipStartDateTime {
    if (_rawMembershipStartDate.isNotEmpty) {
      final dt = DateTime.tryParse(_rawMembershipStartDate);
      if (dt != null) return dt;
    }
    if (_membershipStartDate.isNotEmpty) {
      try {
        return DateFormat('dd MMM yyyy').parse(_membershipStartDate);
      } catch (_) {}
      return DateTime.tryParse(_membershipStartDate);
    }
    return null;
  }
  DateTime? get membershipEndDateTime {
    if (_rawMembershipEndDate.isNotEmpty) {
      final dt = DateTime.tryParse(_rawMembershipEndDate);
      if (dt != null) return dt;
    }
    if (_membershipEndDate.isNotEmpty) {
      try {
        return DateFormat('dd MMM yyyy').parse(_membershipEndDate);
      } catch (_) {}
      return DateTime.tryParse(_membershipEndDate);
    }
    return null;
  }
  DateTime? get joinDateTime {
    if (_joinDate.isNotEmpty) {
      final dt = DateTime.tryParse(_joinDate);
      if (dt != null) return dt;
      try {
        return DateFormat('dd MMM yyyy').parse(_joinDate);
      } catch (_) {}
      try {
        return DateFormat('dd-MM-yyyy').parse(_joinDate);
      } catch (_) {}
    }
    return null;
  }
  int get membershipTimeRemaining => _membershipTimeRemaining;
  String get planDuration => _planDuration;
  String get amountPaid => _amountPaid;
  String get nextDue => _nextDue;
  List<Map<String, dynamic>> get paymentHistory => _paymentHistory;

  int get currentLevel => _currentLevel;
  int get currentXP => _currentXP;
  int get nextLevelXP => _nextLevelXP;
  int get nextMilestoneTarget => _nextMilestoneTarget;
  int get currentMilestoneProgress => _currentMilestoneProgress;
  String get currentTitle => _currentTitle;

  List<Map<String, dynamic>> get achievements => _achievements;

  int get presentDays => _presentDays;
  int get absentDays => _absentDays;
  int get lateDays => _lateDays;
  List<int> get attendedDaysOfCurrentMonth => _attendedDaysOfCurrentMonth;
  Map<String, String> get attendanceMapByIsoDate => _attendanceMapByIsoDate;
  List<Map<String, dynamic>> get attendanceHistory => _attendanceHistory;

  String get currentQuote => _currentQuote;

  String get checkInTime => _checkInTime;
  String get checkInDate => _checkInDate;
  bool get checkedInToday => _checkedInToday;
  bool get isCheckingIn => _isCheckingIn;

  String get greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  // Setters for dynamic interactions
  void setTodayMuscleGroup(String muscle) {
    _todayMuscleGroup = muscle;
    notifyListeners();
  }

  void addWater(double amount) {
    _waterIntake = min(_waterGoal, _waterIntake + amount);
    notifyListeners();
    _saveWellnessLocallyAndSync();
  }

  void addCalories(int amount) {
    _caloriesIntake = min(_caloriesGoal, _caloriesIntake + amount);
    notifyListeners();
    _saveWellnessLocallyAndSync();
  }

  void addProtein(int amount) {
    _proteinIntake = min(_proteinGoal, _proteinIntake + amount);
    notifyListeners();
    _saveWellnessLocallyAndSync();
  }

  Future<void> _saveWellnessLocallyAndSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('member_cached_water_intake', _waterIntake);
      await prefs.setDouble('member_cached_water_goal', _waterGoal);
      await prefs.setInt('member_cached_calories_intake', _caloriesIntake);
      await prefs.setInt('member_cached_calories_goal', _caloriesGoal);
      await prefs.setInt('member_cached_protein_intake', _proteinIntake);
      await prefs.setInt('member_cached_protein_goal', _proteinGoal);
      
      _saveDailyLogToSupabase();
    } catch (_) {}
  }

  Future<void> _saveDailyLogToSupabase() async {
    if (!SupabaseService.isInitialized || _memberId.isEmpty) return;
    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final prefs = await SharedPreferences.getInstance();
      final gymInfoStr = prefs.getString('gymos_gym_info');
      String? gymId;
      if (gymInfoStr != null) {
        final gymInfo = jsonDecode(gymInfoStr) as Map<String, dynamic>;
        gymId = gymInfo['id'];
      }
      
      if (gymId == null) return;

      await SupabaseService.client.from('member_daily_logs').upsert({
        'member_id': _memberId,
        'gym_id': gymId,
        'date': todayStr,
        'water_intake': _waterIntake,
        'water_goal': _waterGoal,
        'calories_intake': _caloriesIntake,
        'calories_goal': _caloriesGoal,
        'protein_intake': _proteinIntake,
        'protein_goal': _proteinGoal,
      }, onConflict: 'member_id, date');
    } catch (e) {
      print('Failed to save daily log to database: $e');
    }
  }

  // ── Helper to verify if a date string represents today ──
  bool _isDateFromToday(String? dateStr, String? isoStr) {
    final now = DateTime.now();
    final todayIso = DateFormat('yyyy-MM-dd').format(now);
    if (isoStr != null && isoStr.trim() == todayIso) return true;
    if (dateStr == null || dateStr.trim().isEmpty) return false;

    final trimmed = dateStr.trim();
    if (trimmed.startsWith(todayIso)) return true;

    for (final fmt in ['yyyy-MM-dd', 'dd MMM yyyy', 'dd-MM-yyyy', 'd MMM yyyy', 'yyyy/MM/dd']) {
      try {
        final parsed = DateFormat(fmt).parse(trimmed);
        if (parsed.year == now.year && parsed.month == now.month && parsed.day == now.day) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Verifies if _checkedInToday is actually from today. If date changed across midnight, resets state.
  void validateTodayAttendanceDate() {
    if (!_checkedInToday) return;
    if (!_isDateFromToday(_checkInDate, _checkInDateIso)) {
      _checkedInToday = false;
      _checkInTime = '';
      _checkInDate = '';
      _checkInDateIso = '';
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool('member_checked_in_today', false);
        prefs.remove('member_check_in_time');
        prefs.remove('member_check_in_date');
        prefs.remove('member_check_in_date_iso');
      });
      notifyListeners();
    }
  }

  // ── Persistence ──
  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    _isMemberCodeVerified = prefs.getBool('member_code_verified') ?? false;
    _isLoggedIn = prefs.getBool('member_logged_in') ?? false;
    
    final savedCheckedIn = prefs.getBool('member_checked_in_today') ?? false;
    final savedTime = prefs.getString('member_check_in_time') ?? '';
    final savedDate = prefs.getString('member_check_in_date') ?? '';
    final savedIso = prefs.getString('member_check_in_date_iso') ?? '';

    if (savedCheckedIn && _isDateFromToday(savedDate, savedIso)) {
      _checkedInToday = true;
      _checkInTime = savedTime;
      _checkInDate = savedDate;
      _checkInDateIso = savedIso;
    } else {
      _checkedInToday = false;
      _checkInTime = '';
      _checkInDate = '';
      _checkInDateIso = '';
      await prefs.setBool('member_checked_in_today', false);
      await prefs.remove('member_check_in_time');
      await prefs.remove('member_check_in_date');
      await prefs.remove('member_check_in_date_iso');
    }

    // Load cached workout plan, diet plan & attendance history for instant UI rendering
    _memberId = prefs.getString('member_cached_id') ?? _memberId;
    _memberName = prefs.getString('member_cached_name') ?? _memberName;
    _gymName = prefs.getString('member_cached_gym_name') ?? _gymName;
    _gymLogoUrl = prefs.getString('member_cached_gym_logo') ?? _gymLogoUrl;
    _gymId = prefs.getString('member_cached_gym_id') ?? _gymId;
    _joinDate = prefs.getString('member_cached_join_date') ?? _joinDate;
    _attendanceMethod = prefs.getString('member_cached_attendance_method') ?? 'Static QR';
    _isAttendanceEnabled = prefs.getBool('member_cached_attendance_enabled') ?? true;

    // Instantly restore cached rules agreement state on startup
    bool localAgreed = false;
    if (_gymId.isNotEmpty && _memberId.isNotEmpty) {
      localAgreed = prefs.getBool('gymos_rule_agreed_${_gymId}_$_memberId') ?? false;
    }
    if (!localAgreed && _memberId.isNotEmpty) {
      localAgreed = prefs.getBool('gymos_rule_agreed_member_$_memberId') ?? false;
    }
    if (!localAgreed) {
      localAgreed = prefs.getBool('gymos_rule_agreed_global') ?? false;
    }
    if (localAgreed) {
      _hasAgreedRules = true;
    }
    final cachedRecordStr = prefs.getString('gymos_rule_agreed_${_gymId}_${_memberId}_record') ??
        prefs.getString('gymos_rule_agreed_record_global');

    if (cachedRecordStr != null) {
      try {
        _agreementRecord = MemberAgreementRecord.fromMap(jsonDecode(cachedRecordStr));
      } catch (_) {}
    }

    _assignedWorkoutId = prefs.getString('member_cached_workout_id') ?? _assignedWorkoutId;
    _assignedWorkoutTitle = prefs.getString('member_cached_workout_title') ?? _assignedWorkoutTitle;

    final cachedScheduleStr = prefs.getString('member_cached_workout_schedule_$_memberId') ??
        prefs.getString('member_cached_workout_schedule');
    if (cachedScheduleStr != null && cachedScheduleStr.isNotEmpty) {
      try {
        _weeklyWorkoutSchedule = Map<String, dynamic>.from(jsonDecode(cachedScheduleStr));
      } catch (_) {}
    }

    _computeTodayWorkoutFromSchedule(prefs);
    _assignedDietTitle = prefs.getString('member_cached_diet_title') ?? _assignedDietTitle;

    final cachedDietPlanJson = prefs.getString('member_cached_diet_plan_json');
    if (cachedDietPlanJson != null && cachedDietPlanJson.isNotEmpty) {
      try {
        _assignedDietPlan = DietPlan.fromJson(jsonDecode(cachedDietPlanJson));
        _assignedDietTitle = _assignedDietPlan!.title;
      } catch (_) {}
    }

    final cachedDaysStr = prefs.getString('member_cached_attendance_days');
    if (cachedDaysStr != null) {
      try {
        final List decoded = jsonDecode(cachedDaysStr);
        _attendedDaysOfCurrentMonth = decoded.map((e) => (e as num).toInt()).toList();
        _presentDays = _attendedDaysOfCurrentMonth.length;
        final lastDay = DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
        int totalGymDays = 0;
        for (int i = 1; i <= lastDay; i++) {
          if (DateTime(DateTime.now().year, DateTime.now().month, i).weekday != DateTime.sunday) {
            totalGymDays++;
          }
        }
        _attendancePercentage = totalGymDays > 0 ? ((_presentDays / totalGymDays) * 100).round() : 0;
      } catch (_) {}
    }

    // Calculate days left offline automatically
    final cachedDaysLeft = prefs.getInt('member_cached_days_left');
    final cachedDaysTs = prefs.getString('member_cached_days_timestamp');
    if (cachedDaysLeft != null && cachedDaysTs != null) {
      try {
        final cachedDate = DateTime.parse(cachedDaysTs);
        final elapsed = DateTime.now().difference(DateTime(cachedDate.year, cachedDate.month, cachedDate.day)).inDays;
        _membershipDaysLeft = max(0, cachedDaysLeft - elapsed);
      } catch (_) {
        _membershipDaysLeft = cachedDaysLeft;
      }
    }

    final cachedHolidays = prefs.getStringList('member_declared_holidays');
    if (cachedHolidays != null) {
      _declaredHolidays = cachedHolidays;
    }

    _waterIntake = prefs.getDouble('member_cached_water_intake') ?? 2.5;
    _waterGoal = prefs.getDouble('member_cached_water_goal') ?? 4.0;
    _caloriesIntake = prefs.getInt('member_cached_calories_intake') ?? 1850;
    _caloriesGoal = prefs.getInt('member_cached_calories_goal') ?? 2500;
    _proteinIntake = prefs.getInt('member_cached_protein_intake') ?? 120;
    _proteinGoal = prefs.getInt('member_cached_protein_goal') ?? 160;

    final cachedAttendance = prefs.getString('member_cached_attendance_history');
    if (cachedAttendance != null) {
      try {
        final decoded = jsonDecode(cachedAttendance) as List;
        _attendanceHistory.clear();
        _attendanceHistory.addAll(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
      } catch (_) {}
    }
    final cachedAttMap = prefs.getString('member_cached_attendance_map');
    if (cachedAttMap != null) {
      try {
        _attendanceMapByIsoDate = Map<String, String>.from(jsonDecode(cachedAttMap));
      } catch (_) {}
    }

    final cachedMonthDays = prefs.getStringList('member_cached_attended_days_curr_month');
    if (cachedMonthDays != null) {
      _attendedDaysOfCurrentMonth = cachedMonthDays.map((e) => int.parse(e)).toList();
    }
    
    // Present days is strictly the number of attended days in current month (never out-of-bounds)
    _presentDays = _attendedDaysOfCurrentMonth.length;
    _absentDays = prefs.getInt('member_cached_absent_days') ?? 0;
    _lateDays = prefs.getInt('member_cached_late_days') ?? 0;
    
    // Calculate attendance percentage based on active present days
    final lastDay = DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
    int totalGymDays = 0;
    for (int i = 1; i <= lastDay; i++) {
      if (DateTime(DateTime.now().year, DateTime.now().month, i).weekday != DateTime.sunday) {
        totalGymDays++;
      }
    }
    _attendancePercentage = totalGymDays > 0 ? ((_presentDays / totalGymDays) * 100).round() : 0;

    final todayIsoStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastWorkoutDate = prefs.getString('member_last_workout_completed_date');
    _isTrainingCompleted = (lastWorkoutDate == todayIsoStr);

    final cachedHistoryStr = prefs.getString('member_training_history');
    if (cachedHistoryStr != null) {
      try {
        final List decoded = jsonDecode(cachedHistoryStr);
        _trainingHistory.clear();
        _trainingHistory.addAll(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
      } catch (_) {}
    }

    _generateCurrentWeek();
    notifyListeners();
    await loadMemberDataFromSupabase();
  }

  /// Evaluates today's splits and muscle group from the 7-day schedule offline.
  /// Guarantees that:
  /// 1. Unassigned members are marked 'No Plan Assigned' (never falsely labeled 'Rest Day').
  /// 2. Multi-splits (e.g. Chest Day & Bicep Day) are cleanly parsed and combined.
  /// 3. Genuine Rest Days set by the owner are respected.
  void _computeTodayWorkoutFromSchedule([SharedPreferences? prefs]) {
    if (_assignedWorkoutId.isEmpty || _weeklyWorkoutSchedule.isEmpty) {
      _todaySplits = [];
      _todayMuscleGroup = 'No Plan Assigned';
      if (prefs != null) {
        prefs.setString('member_cached_today_muscle', _todayMuscleGroup);
        prefs.setStringList('member_cached_today_splits', _todaySplits);
      }
      return;
    }

    final todayFull = DateFormat('EEEE').format(DateTime.now()); // e.g. "Wednesday"
    final todayShort = DateFormat('E').format(DateTime.now());   // e.g. "Wed"

    dynamic todayList;
    for (final entry in _weeklyWorkoutSchedule.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      if (key == todayFull.toLowerCase() || key == todayShort.toLowerCase()) {
        todayList = entry.value;
        break;
      }
    }

    final List<String> splits = [];
    if (todayList is List) {
      for (final item in todayList) {
        String splitTitle = '';
        if (item is Map) {
          splitTitle = item['title']?.toString() ?? '';
        } else if (item is String) {
          splitTitle = item;
        }
        if (splitTitle.trim().isNotEmpty) {
          splits.add(splitTitle.trim());
        }
      }
    } else if (todayList is Map) {
      final t = todayList['title']?.toString() ?? '';
      if (t.trim().isNotEmpty) splits.add(t.trim());
    } else if (todayList is String && todayList.trim().isNotEmpty) {
      splits.add(todayList.trim());
    }

    if (splits.isEmpty) {
      _todaySplits = ['Rest Day'];
      _todayMuscleGroup = 'Rest Day';
    } else {
      final realSplits = splits.where((s) => !s.toLowerCase().contains('rest')).toList();
      if (realSplits.isEmpty) {
        _todaySplits = ['Rest Day'];
        _todayMuscleGroup = 'Rest Day';
      } else {
        _todaySplits = realSplits;
        _todayMuscleGroup = realSplits.join(' & ');
      }
    }

    if (prefs != null) {
      prefs.setString('member_cached_today_muscle', _todayMuscleGroup);
      prefs.setStringList('member_cached_today_splits', _todaySplits);
    }
  }

  Future<Map<String, dynamic>> completeTodayWorkout(BuildContext context) async {
    final now = DateTime.now();
    final todayDateStr = DateFormat('dd MMM yyyy').format(now);
    final todayIsoStr = DateFormat('yyyy-MM-dd').format(now);

    // 1. Attendance Check: verify if member checked in today
    bool isAttendanceMarked = _checkedInToday;
    if (!isAttendanceMarked) {
      final todayFormatted = DateFormat('dd-MM-yyyy').format(now);
      if (_checkInDate == todayFormatted || _attendedDaysOfCurrentMonth.contains(now.day)) {
        isAttendanceMarked = true;
      }
    }

    // If attendance is NOT marked and network is initialized, block workout completion
    if (!isAttendanceMarked && SupabaseService.isInitialized) {
      return {
        'success': false,
        'message': 'You haven\'t marked attendance today! Please check-in first to complete your workout.',
      };
    }

    // 2. Mark workout completed
    _isTrainingCompleted = true;
    final newLog = {
      'date': todayDateStr,
      'muscle': _todayMuscleGroup,
      'status': 'Completed',
      'time': DateFormat('hh:mm a').format(now),
    };

    _trainingHistory.removeWhere((item) => item['date'] == todayDateStr);
    _trainingHistory.insert(0, newLog);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('member_last_workout_completed_date', todayIsoStr);
    await prefs.setString('member_training_history', jsonEncode(_trainingHistory));

    // 3. Save to Supabase if connected
    if (SupabaseService.isInitialized) {
      try {
        final user = SupabaseService.client.auth.currentUser;
        if (user != null) {
          await SupabaseService.client.from('attendance_logs').update({
            'shift_status': 'Workout Completed',
          }).eq('user_id', user.id).gte('check_in', DateTime(now.year, now.month, now.day).toIso8601String());

          // Also save in member_workout_logs
          final gymInfoStr = prefs.getString('gymos_gym_info');
          String? gymId;
          if (gymInfoStr != null) {
            final gymInfo = jsonDecode(gymInfoStr) as Map<String, dynamic>;
            gymId = gymInfo['id'];
          }
          if (gymId != null && _memberId.isNotEmpty) {
            await SupabaseService.client.from('member_workout_logs').upsert({
              'gym_id': gymId,
              'member_id': _memberId,
              'date': todayIsoStr,
              'muscle': _todayMuscleGroup,
              'status': 'Completed',
            });
          }
        }
      } catch (e) {
        print('Error updating workout log in Supabase: $e');
      }
    }

    notifyListeners();
    return {
      'success': true,
      'message': '🎉 Workout completed for today! Great job staying consistent.',
    };
  }

  void _generateCurrentWeek() {
    final now = DateTime.now();
    final currentWeekday = now.weekday; // Monday is 1, Sunday is 7
    final monday = now.subtract(Duration(days: currentWeekday - 1));

    _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    _weekDates = List.generate(7, (index) {
      return monday.add(Duration(days: index)).day;
    });
  }

  bool _isLoadingMemberData = false;
  Completer<void>? _loadingMemberDataCompleter;
  DateTime? _lastMemberDataFetchTime;

  Future<void> loadMemberDataFromSupabase({bool forceRefresh = false}) async {
    if (!forceRefresh && _memberId.isNotEmpty && _lastMemberDataFetchTime != null) {
      final diff = DateTime.now().difference(_lastMemberDataFetchTime!);
      if (diff < const Duration(seconds: 30)) {
        return;
      }
    }
    if (_loadingMemberDataCompleter != null) {
      return _loadingMemberDataCompleter!.future;
    }
    _loadingMemberDataCompleter = Completer<void>();
    _isLoadingMemberData = true;
    _lastMemberDataFetchTime = DateTime.now();

    if (_memberName.isEmpty) {
      notifyListeners();
    }
    final prefs = await SharedPreferences.getInstance();
    try {
      if (!SupabaseService.isInitialized) return;
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;

      final gymInfoStr = prefs.getString('gymos_gym_info');
      String? cachedGymId;
      if (gymInfoStr != null) {
        try {
          final gymInfo = jsonDecode(gymInfoStr) as Map<String, dynamic>;
          cachedGymId = gymInfo['id'];
        } catch (_) {}
      }
      cachedGymId ??= _gymId.isNotEmpty ? _gymId : null;

      var query = SupabaseService.client
          .from('members')
          .select()
          .eq('user_id', user.id);
      
      if (cachedGymId != null) {
        query = query.eq('gym_id', cachedGymId);
      }

      Map<String, dynamic>? fetchedMemberData = await query.maybeSingle();
      if (fetchedMemberData == null && cachedGymId != null) {
        // Fallback: search without gym_id restriction in case cachedGymId was stale/mismatched
        fetchedMemberData = await SupabaseService.client
            .from('members')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
      }

      if (fetchedMemberData != null) {
        final memberData = fetchedMemberData;
        _memberName = memberData['name'] ?? _memberName;
        _memberId = memberData['id'] ?? _memberId;
        _gymId = memberData['gym_id']?.toString() ?? cachedGymId ?? _gymId;
        prefs.setString('member_cached_id', _memberId);
        prefs.setString('member_cached_name', _memberName);
        prefs.setString('member_cached_gym_id', _gymId);
        _memberAvatar = (memberData['avatar'] != null && memberData['avatar'].toString().isNotEmpty) 
            ? memberData['avatar'] 
            : _memberAvatar;
        final rawJoin = memberData['join_date']?.toString() ?? memberData['created_at']?.toString() ?? '';
        if (rawJoin.isNotEmpty) {
          _joinDate = rawJoin;
          prefs.setString('member_cached_join_date', rawJoin);
        }
        _membershipStatus = memberData['status'] ?? _membershipStatus;
        _assignedWorkoutId = memberData['assigned_workout_id'] ?? '';
        _assignedDietId = memberData['assigned_diet_id'] ?? '';
        _pendingAmount = (memberData['pending_amount'] as num?)?.toDouble() ?? 0.0;

        final currentRole = prefs.getString('gymos_user_role');
        if (currentRole == null || currentRole.isEmpty || currentRole == 'member') {
          prefs.setString('gymos_user_role', 'member');
          if (_gymId.isNotEmpty) {
            prefs.setString('gymos_gym_info', jsonEncode({
              'id': _gymId,
              'name': _gymName,
            }));
          }
        }

        // Subtask 1: Assigned Workout Plan
        Future<void> fetchWorkoutPlanTask() async {
          if (_assignedWorkoutId.isNotEmpty) {
            try {
              final wData = await SupabaseService.client
                  .from('workout_plans')
                  .select('title, schedule')
                  .eq('id', _assignedWorkoutId)
                  .maybeSingle();
              if (wData != null) {
                _assignedWorkoutTitle = wData['title'] ?? '';
                dynamic rawSchedule = wData['schedule'];
                if (rawSchedule is String && rawSchedule.isNotEmpty) {
                  try {
                    rawSchedule = jsonDecode(rawSchedule);
                  } catch (_) {}
                }
                if (rawSchedule is Map) {
                  _weeklyWorkoutSchedule = Map<String, dynamic>.from(rawSchedule);
                } else {
                  _weeklyWorkoutSchedule = {};
                }
                await prefs.setString('member_cached_workout_id', _assignedWorkoutId);
                await prefs.setString('member_cached_workout_title', _assignedWorkoutTitle);
                await prefs.setString('member_cached_workout_schedule_$_memberId', jsonEncode(_weeklyWorkoutSchedule));
                await prefs.setString('member_cached_workout_schedule', jsonEncode(_weeklyWorkoutSchedule));

                _computeTodayWorkoutFromSchedule(prefs);
              } else {
                _assignedWorkoutTitle = '';
                _weeklyWorkoutSchedule = {};
                _todaySplits = [];
                _todayMuscleGroup = 'No Plan Assigned';
                await prefs.setString('member_cached_today_muscle', _todayMuscleGroup);
                await prefs.setStringList('member_cached_today_splits', _todaySplits);
              }
            } catch (_) {}
          } else {
            _assignedWorkoutTitle = '';
            _weeklyWorkoutSchedule = {};
            _todaySplits = [];
            _todayMuscleGroup = 'No Plan Assigned';
            await prefs.setString('member_cached_today_muscle', _todayMuscleGroup);
            await prefs.setStringList('member_cached_today_splits', _todaySplits);
          }
        }

        // Subtask 2: Gym Details & Settings
        Future<void> fetchGymDetailsTask() async {
          final memberGymId = memberData['gym_id'];
          if (memberGymId != null) {
            _gymId = memberGymId.toString();
            prefs.setString('member_cached_gym_id', _gymId);
            try {
              final gymData = await SupabaseService.client
                  .from('gyms')
                  .select('name, logo_url')
                  .eq('id', memberGymId)
                  .maybeSingle();
              if (gymData != null) {
                if (gymData['name'] != null && gymData['name'].toString().isNotEmpty) {
                  _gymName = gymData['name'].toString();
                  prefs.setString('member_cached_gym_name', _gymName);
                }
                if (gymData['logo_url'] != null && gymData['logo_url'].toString().isNotEmpty) {
                  _gymLogoUrl = gymData['logo_url'].toString();
                  prefs.setString('member_cached_gym_logo', _gymLogoUrl);
                }
              }
            } catch (_) {}

            try {
              final attSettings = await SupabaseService.client
                  .from('attendance_settings')
                  .select('method, is_enabled')
                  .eq('gym_id', memberGymId)
                  .maybeSingle();
              if (attSettings != null) {
                _attendanceMethod = attSettings['method']?.toString() ?? 'Static QR';
                _isAttendanceEnabled = attSettings['is_enabled'] != false;
                prefs.setString('member_cached_attendance_method', _attendanceMethod);
                prefs.setBool('member_cached_attendance_enabled', _isAttendanceEnabled);
              }
            } catch (_) {}

            try {
              final rulesData = await SupabaseService.client
                  .from('gym_rules')
                  .select('version, rules_data, is_active')
                  .eq('gym_id', memberGymId)
                  .maybeSingle();
              if (rulesData != null && rulesData['is_active'] == true) {
                _currentRulesVersion = rulesData['version'] is int ? rulesData['version'] : 1;
                if (rulesData['rules_data'] is List) {
                  _customRulesData = rulesData['rules_data'] as List<dynamic>;
                } else if (rulesData['rules_data'] is String) {
                  try {
                    _customRulesData = jsonDecode(rulesData['rules_data']);
                  } catch (_) {}
                }
              }
            } catch (_) {}
          }
        }

        // Subtask 3: Diet Plan
        Future<void> fetchDietPlanTask() async {
          if (_assignedDietId.isNotEmpty) {
            try {
              final dData = await SupabaseService.client
                  .from('diet_plans')
                  .select()
                  .eq('id', _assignedDietId)
                  .maybeSingle();
              if (dData != null) {
                _assignedDietPlan = DietPlan.fromJson(Map<String, dynamic>.from(dData));
                _assignedDietTitle = _assignedDietPlan!.title;
                prefs.setString('member_cached_diet_plan_json', jsonEncode(dData));
                prefs.setString('member_cached_diet_title', _assignedDietTitle);
              }
            } catch (_) {}
          }

          final currentGymId = memberData['gym_id']?.toString() ?? cachedGymId;
          if (_assignedDietPlan == null && currentGymId != null) {
            try {
              final List gymDiets = await SupabaseService.client
                  .from('diet_plans')
                  .select()
                  .eq('gym_id', currentGymId)
                  .limit(1);
              if (gymDiets.isNotEmpty) {
                final firstDiet = Map<String, dynamic>.from(gymDiets.first as Map);
                _assignedDietPlan = DietPlan.fromJson(firstDiet);
                _assignedDietTitle = _assignedDietPlan!.title;
                prefs.setString('member_cached_diet_plan_json', jsonEncode(firstDiet));
                prefs.setString('member_cached_diet_title', _assignedDietTitle);
              }
            } catch (_) {}
          }

          if (_assignedDietPlan == null) {
            _assignedDietTitle = '';
          }
        }

        // Subtask 4: Memberships & Payments
        Future<void> fetchMembershipAndPaymentsTask() async {
          try {
            final membershipData = await SupabaseService.client
                .from('member_memberships')
                .select('*, membership_plans(title, duration_months)')
                .eq('member_id', _memberId)
                .order('end_date', ascending: false)
                .limit(1)
                .maybeSingle();

            if (membershipData != null) {
              final planData = membershipData['membership_plans'];
              if (planData != null) {
                _membershipPlan = planData['title'] ?? _membershipPlan;
                final durationMonths = planData['duration_months'] ?? 1;
                _planDuration = '$durationMonths Month${durationMonths > 1 ? 's' : ''}';
              }
              _rawMembershipStartDate = membershipData['start_date']?.toString() ?? '';
              _rawMembershipEndDate = membershipData['end_date']?.toString() ?? '';
              try {
                final startDate = DateTime.parse(membershipData['start_date']);
                _membershipStartDate = DateFormat('dd MMM yyyy').format(startDate);
              } catch (_) {
                _membershipStartDate = membershipData['start_date'] ?? _membershipStartDate;
              }
              _membershipEndDate = membershipData['end_date'] ?? _membershipEndDate;
              final paidAmount = membershipData['paid_amount'] ?? 0;
              _amountPaid = '₹$paidAmount';
              try {
                final endDate = DateTime.parse(_membershipEndDate);
                final today = DateTime.now();
                final difference = DateTime(endDate.year, endDate.month, endDate.day)
                    .difference(DateTime(today.year, today.month, today.day))
                    .inDays;
                _membershipDaysLeft = difference > 0 ? difference : 0;
                prefs.setInt('member_cached_days_left', _membershipDaysLeft);
                prefs.setString('member_cached_days_timestamp', DateTime.now().toIso8601String());
              } catch (_) {
                _membershipDaysLeft = 0;
              }
              try {
                final endDate = DateTime.parse(_membershipEndDate);
                final nextDue = endDate.add(const Duration(days: 1));
                _nextDue = DateFormat('dd MMM yyyy').format(nextDue);
                _membershipEndDate = DateFormat('dd MMM yyyy').format(endDate);
              } catch (_) {
                _nextDue = _membershipEndDate;
              }
              _membershipStatus = _membershipDaysLeft > 0 ? 'Active' : 'Expired';
            } else {
              final planId = memberData['membership_plan_id'];
              if (planId != null && planId.toString().isNotEmpty) {
                final planData = await SupabaseService.client
                    .from('membership_plans')
                    .select('title, price, duration_months')
                    .eq('id', planId)
                    .maybeSingle();
                if (planData != null) {
                  _membershipPlan = planData['title'] ?? _membershipPlan;
                  final durationMonths = planData['duration_months'] ?? 1;
                  _planDuration = '$durationMonths Month${durationMonths > 1 ? 's' : ''}';
                  final price = planData['price'] ?? 0;
                  _amountPaid = '₹$price';
                }
              }
            }
          } catch (_) {}

          // Payments deduping
          try {
            final Map<String, Map<String, dynamic>> dedupedPaymentsMap = {};
            final Set<String> processedMembershipIds = {};

            List<dynamic>? membershipsList;
            try {
              membershipsList = await SupabaseService.client
                  .from('member_memberships')
                  .select('id, start_date, total_amount, paid_amount, payment_status, membership_plans(title)')
                  .eq('member_id', _memberId)
                  .order('start_date', ascending: false);
            } catch (_) {}

            try {
              final financeData = await SupabaseService.client
                  .from('finance_transactions')
                  .select('id, amount, transaction_date, revenue_date, created_at, notes')
                  .eq('reference_id', _memberId)
                  .eq('type', 'Revenue')
                  .order('created_at', ascending: false);

              if (financeData != null && financeData.isNotEmpty) {
                for (var tx in financeData) {
                  final amtVal = tx['amount'];
                  if (amtVal == null || (amtVal is num && amtVal <= 0)) continue;
                  final rawDate = tx['revenue_date'] ?? tx['transaction_date'] ?? tx['created_at'];
                  final pDate = DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
                  final formattedDate = DateFormat('dd MMM yyyy').format(pDate);
                  final amtNum = (amtVal is num) ? amtVal.toDouble() : double.tryParse(amtVal.toString()) ?? 0.0;
                  final amtStr = '₹${amtNum.toStringAsFixed(0)}';
                  final txId = tx['id']?.toString() ?? '';
                  final shortCode = txId.replaceAll('-', '').substring(0, 4).toUpperCase();
                  final invoiceNum = 'INV-${pDate.year}-$shortCode';
                  final uniqueKey = '${pDate.year}-${pDate.month}-${pDate.day}_${amtNum.toStringAsFixed(0)}_$shortCode';

                  if (!dedupedPaymentsMap.containsKey(uniqueKey) && !dedupedPaymentsMap.containsKey(invoiceNum)) {
                    dedupedPaymentsMap[invoiceNum] = {
                      'invoice': invoiceNum,
                      'date': formattedDate,
                      'amount': amtStr,
                      'status': 'Paid',
                      'raw_date': pDate,
                      'tx_id': txId,
                    };
                  }
                }
              }
            } catch (_) {}

            if (membershipsList != null && membershipsList.isNotEmpty) {
              final membershipIds = membershipsList.map((m) => m['id'].toString()).toList();
              try {
                final paymentsData = await SupabaseService.client
                    .from('membership_payments')
                    .select('id, amount, payment_date, member_membership_id')
                    .inFilter('member_membership_id', membershipIds)
                    .order('payment_date', ascending: false);

                if (paymentsData != null && paymentsData.isNotEmpty) {
                  for (var pay in paymentsData) {
                    final mId = pay['member_membership_id']?.toString() ?? '';
                    processedMembershipIds.add(mId);
                    final amtVal = pay['amount'];
                    if (amtVal == null || (amtVal is num && amtVal <= 0)) continue;
                    final pDate = DateTime.tryParse(pay['payment_date'] ?? '') ?? DateTime.now();
                    final formattedDate = DateFormat('dd MMM yyyy').format(pDate);
                    final amtNum = (amtVal is num) ? amtVal.toDouble() : double.tryParse(amtVal.toString()) ?? 0.0;
                    final amtStr = '₹${amtNum.toStringAsFixed(0)}';
                    final payId = pay['id']?.toString() ?? '';
                    final shortCode = payId.replaceAll('-', '').substring(0, 4).toUpperCase();
                    final invoiceNum = 'INV-${pDate.year}-$shortCode';

                    bool alreadyInFinance = dedupedPaymentsMap.values.any((item) =>
                        item['amount'] == amtStr && item['date'] == formattedDate);

                    if (!alreadyInFinance && !dedupedPaymentsMap.containsKey(invoiceNum)) {
                      dedupedPaymentsMap[invoiceNum] = {
                        'invoice': invoiceNum,
                        'date': formattedDate,
                        'amount': amtStr,
                        'status': 'Paid',
                        'raw_date': pDate,
                        'tx_id': payId,
                      };
                    }
                  }
                }
              } catch (_) {}
            }

            if (membershipsList != null) {
              for (var mship in membershipsList) {
                final mId = mship['id'].toString();
                final paidAmount = (mship['paid_amount'] as num?)?.toDouble() ?? 0.0;
                if (!processedMembershipIds.contains(mId) && paidAmount > 0) {
                  final pDate = DateTime.tryParse(mship['start_date'] ?? '') ?? DateTime.now();
                  final formattedDate = DateFormat('dd MMM yyyy').format(pDate);
                  final amtStr = '₹${paidAmount.toStringAsFixed(0)}';
                  final shortCode = mId.replaceAll('-', '').substring(0, 4).toUpperCase();
                  final invoiceNum = 'INV-${pDate.year}-$shortCode';

                  bool alreadyCaptured = dedupedPaymentsMap.values.any((item) =>
                      item['amount'] == amtStr && item['date'] == formattedDate);

                  if (!alreadyCaptured && !dedupedPaymentsMap.containsKey(invoiceNum)) {
                    final statusStr = mship['payment_status']?.toString() ?? 'Paid';
                    dedupedPaymentsMap[invoiceNum] = {
                      'invoice': invoiceNum,
                      'date': formattedDate,
                      'amount': amtStr,
                      'status': statusStr == 'Fully Paid' ? 'Paid' : statusStr,
                      'raw_date': pDate,
                      'tx_id': mId,
                    };
                  }
                }
              }
            }

            final sortedList = dedupedPaymentsMap.values.toList()
              ..sort((a, b) {
                final da = a['raw_date'] as DateTime? ?? DateTime(2000);
                final db = b['raw_date'] as DateTime? ?? DateTime(2000);
                return db.compareTo(da);
              });
            _paymentHistory.clear();
            _paymentHistory.addAll(sortedList);
          } catch (_) {}
        }

        // Subtask 5: Workout Logs (Last 30 Days)
        Future<void> fetchWorkoutLogsTask() async {
          try {
            final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
            final cutoffDateIso = DateFormat('yyyy-MM-dd').format(thirtyDaysAgo);

            final dbLogs = await SupabaseService.client
                .from('member_workout_logs')
                .select('date, muscle, status')
                .eq('member_id', _memberId)
                .gte('date', cutoffDateIso)
                .order('date', ascending: false);

            if (dbLogs != null) {
              final Map<String, Map<String, dynamic>> dbLogsMap = {};
              for (var log in dbLogs) {
                dbLogsMap[log['date']] = log;
              }

              dynamic rawSchedule;
              if (_assignedWorkoutId.isNotEmpty) {
                try {
                  final wPlan = await SupabaseService.client
                      .from('workout_plans')
                      .select('schedule')
                      .eq('id', _assignedWorkoutId)
                      .maybeSingle();
                  if (wPlan != null) {
                    rawSchedule = wPlan['schedule'];
                    if (rawSchedule is String && rawSchedule.isNotEmpty) {
                      try {
                        rawSchedule = jsonDecode(rawSchedule);
                      } catch (_) {}
                    }
                  }
                } catch (_) {}
              }

              final List<Map<String, dynamic>> newHistory = [];
              for (int i = 1; i <= 30; i++) {
                final pastDate = DateTime.now().subtract(Duration(days: i));
                final pastDateIso = DateFormat('yyyy-MM-dd').format(pastDate);
                final pastDateFormatted = DateFormat('dd MMM yyyy').format(pastDate);

                final dayName = DateFormat('EEEE').format(pastDate);
                dynamic dayList;
                if (rawSchedule is Map) {
                  dayList = rawSchedule[dayName];
                }
                String muscle = 'Rest Day';
                if (dayList is List && dayList.isNotEmpty) {
                  final firstVal = dayList.first;
                  if (firstVal is Map) {
                    muscle = firstVal['title']?.toString() ?? 'Rest Day';
                  } else {
                    muscle = firstVal?.toString() ?? 'Rest Day';
                  }
                }

                if (dbLogsMap.containsKey(pastDateIso)) {
                  final dbLog = dbLogsMap[pastDateIso]!;
                  newHistory.add({
                    'date': pastDateFormatted,
                    'muscle': dbLog['muscle'] ?? muscle,
                    'status': dbLog['status'] ?? 'Completed',
                  });
                } else {
                  newHistory.add({
                    'date': pastDateFormatted,
                    'muscle': muscle,
                    'status': 'Not Done',
                  });
                }
              }

              _trainingHistory.clear();
              _trainingHistory.addAll(newHistory);
              prefs.setString('member_training_history', jsonEncode(_trainingHistory));
            }
          } catch (_) {}
        }

        // Subtask 6: Body Stats
        Future<void> fetchBodyStatsTask() async {
          final extra = memberData['extra_fields'] as Map<String, dynamic>? ?? {};
          if (extra['weight'] != null && extra['weight'].toString().trim().isNotEmpty) {
            final w = extra['weight'].toString().trim();
            _weight = w.endsWith('kg') ? w : '$w kg';
          } else {
            _weight = '';
          }
          if (extra['height'] != null && extra['height'].toString().trim().isNotEmpty) {
            final h = extra['height'].toString().trim();
            _height = h.endsWith('cm') ? h : '$h cm';
          } else {
            _height = '';
          }
          if ((extra['body_fat'] != null && extra['body_fat'].toString().trim().isNotEmpty) ||
              (extra['bodyFat'] != null && extra['bodyFat'].toString().trim().isNotEmpty)) {
            final bf = (extra['body_fat'] ?? extra['bodyFat']).toString().trim();
            _bodyFat = bf.endsWith('%') ? bf : '$bf%';
          } else {
            _bodyFat = '';
          }
          if (extra['fitness_goal'] != null && extra['fitness_goal'].toString().trim().isNotEmpty) {
            _fitnessGoal = extra['fitness_goal'].toString().trim();
          } else if (extra['fitnessGoal'] != null && extra['fitnessGoal'].toString().trim().isNotEmpty) {
            _fitnessGoal = extra['fitnessGoal'].toString().trim();
          } else {
            _fitnessGoal = '';
          }

          try {
            final latestBodyLog = await SupabaseService.client
                .from('member_body_logs')
                .select('weight_kg, body_fat_pct')
                .eq('member_id', _memberId)
                .order('logged_date', ascending: false)
                .limit(1)
                .maybeSingle();
            if (latestBodyLog != null) {
              if (latestBodyLog['weight_kg'] != null && latestBodyLog['weight_kg'].toString().trim().isNotEmpty) {
                _weight = '${latestBodyLog['weight_kg']} kg';
              }
              if (latestBodyLog['body_fat_pct'] != null && latestBodyLog['body_fat_pct'].toString().trim().isNotEmpty) {
                _bodyFat = '${latestBodyLog['body_fat_pct']}%';
              }
            }
          } catch (_) {}
        }

        // Subtask 7: Attendance Streak RPC
        Future<void> fetchStreakTask() async {
          try {
            final streakRes = await SupabaseService.client.rpc(
              'get_member_attendance_streak_v1',
              params: {
                'p_user_id': user.id,
                'p_gym_id': memberData['gym_id'] ?? '',
              },
            );

            if (streakRes != null && streakRes is Map) {
              _currentStreak = streakRes['current_streak'] ?? 0;
              _lastStreak = streakRes['last_streak'] ?? 0;
              final weekAtt = streakRes['week_attendance'] as List?;
              if (weekAtt != null) {
                _weekAttendance = weekAtt.map((val) => val == true).toList();
              }
              final weekDts = streakRes['week_dates'] as List?;
              if (weekDts != null) {
                _weekDates = weekDts.map((val) => (val as num).toInt()).toList();
              }
            }
            prefs.setInt('member_current_streak', _currentStreak);
          } catch (_) {}
        }

        // Subtask 8: Gamification Profile RPC
        Future<void> fetchGamificationTask() async {
          try {
            final gamificationRes = await SupabaseService.client.rpc(
              'get_member_gamification_profile',
              params: {'p_user_id': user.id},
            );
            if (gamificationRes != null && gamificationRes is Map) {
              final profile = Map<String, dynamic>.from(gamificationRes as Map);
              _currentLevel = profile['current_level'] ?? 1;
              _currentTitle = profile['current_title'] ?? '🌱 New Member';
              _currentXP = profile['current_xp'] ?? 0;
              _nextLevelXP = profile['required_xp'] ?? 100;

              final badgesList = profile['badges'] as List?;
              if (badgesList != null) {
                _achievements.clear();
                for (var badge in badgesList) {
                  final Map<String, dynamic> bMap = Map<String, dynamic>.from(badge as Map);
                  final key = bMap['key']?.toString() ?? '';
                  final isUnlocked = bMap['is_unlocked'] == true;
                  final progress = bMap['current_progress'] ?? 0;
                  final target = bMap['target_value'] ?? 1;
                  final reward = bMap['xp_reward'] ?? 100;
                  final details = _badgeDisplayDetails(key);
                  _achievements.add({
                    'key': key,
                    'title': details['title'],
                    'description': details['description'],
                    'requirement': details['requirement'],
                    'icon': details['icon'],
                    'color': details['color'],
                    'unlocked': isUnlocked,
                    'progress': progress,
                    'target': target,
                    'xp_reward': reward,
                  });
                }
                _achievements.sort((a, b) {
                  final aUnlocked = a['unlocked'] == true ? 0 : 1;
                  final bUnlocked = b['unlocked'] == true ? 0 : 1;
                  return aUnlocked.compareTo(bUnlocked);
                });
              }
            }
          } catch (_) {}
        }

        // Subtask 9: Holidays
        Future<void> fetchHolidaysTask() async {
          try {
            final gymIdVal = memberData['gym_id'];
            if (gymIdVal != null) {
              final holidaysRes = await SupabaseService.client
                  .from('holidays')
                  .select('holiday_date, date')
                  .eq('gym_id', gymIdVal);
              final Set<String> hDates = {};
              for (var h in holidaysRes) {
                final dStr = h['holiday_date']?.toString() ?? h['date']?.toString() ?? '';
                if (dStr.isNotEmpty) hDates.add(dStr);
              }
              _declaredHolidays = hDates.toList();
              prefs.setStringList('member_declared_holidays', _declaredHolidays);
            }
          } catch (_) {}
        }

        // Subtask 10: Daily Wellness Logs
        Future<void> fetchDailyWellnessTask() async {
          try {
            final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
            final logData = await SupabaseService.client
                .from('member_daily_logs')
                .select()
                .eq('member_id', _memberId)
                .eq('date', todayStr)
                .maybeSingle();

            if (logData != null) {
              _waterIntake = (logData['water_intake'] as num?)?.toDouble() ?? _waterIntake;
              _waterGoal = (logData['water_goal'] as num?)?.toDouble() ?? _waterGoal;
              _caloriesIntake = (logData['calories_intake'] as num?)?.toInt() ?? _caloriesIntake;
              _caloriesGoal = (logData['calories_goal'] as num?)?.toInt() ?? _caloriesGoal;
              _proteinIntake = (logData['protein_intake'] as num?)?.toInt() ?? _proteinIntake;
              _proteinGoal = (logData['protein_goal'] as num?)?.toInt() ?? _proteinGoal;
            } else {
              _waterIntake = 0.0;
              _caloriesIntake = 0;
              _proteinIntake = 0;
              final gymIdVal = memberData['gym_id'];
              if (gymIdVal != null) {
                await SupabaseService.client.from('member_daily_logs').insert({
                  'member_id': _memberId,
                  'gym_id': gymIdVal,
                  'date': todayStr,
                  'water_intake': _waterIntake,
                  'water_goal': _waterGoal,
                  'calories_intake': _caloriesIntake,
                  'calories_goal': _caloriesGoal,
                  'protein_intake': _proteinIntake,
                  'protein_goal': _proteinGoal,
                });
              }
            }
            prefs.setDouble('member_cached_water_intake', _waterIntake);
            prefs.setDouble('member_cached_water_goal', _waterGoal);
            prefs.setInt('member_cached_calories_intake', _caloriesIntake);
            prefs.setInt('member_cached_calories_goal', _caloriesGoal);
            prefs.setInt('member_cached_protein_intake', _proteinIntake);
            prefs.setInt('member_cached_protein_goal', _proteinGoal);
          } catch (_) {}
        }

        // Subtask 11: Attendance History & Status
        Future<void> fetchAttendanceHistoryTask() async {
          try {
            final authUid = SupabaseService.client.auth.currentUser?.id ?? '';
            var attQuery = SupabaseService.client
                .from('attendance_logs')
                .select('date, check_in, check_out, status, user_type, role, member_id, user_id');
            if (_memberId.isNotEmpty && authUid.isNotEmpty) {
              attQuery = attQuery.or('member_id.eq.$_memberId,user_id.eq.$authUid');
            } else if (_memberId.isNotEmpty) {
              attQuery = attQuery.eq('member_id', _memberId);
            } else if (authUid.isNotEmpty) {
              attQuery = attQuery.eq('user_id', authUid);
            }

            // Order by check_in descending so latest records are retrieved first
            final attendanceData = await attQuery
                .order('check_in', ascending: false)
                .limit(365);

            if (attendanceData.isNotEmpty) {
              _attendanceHistory.clear();
              _attendanceMapByIsoDate.clear();
              _attendedDaysOfCurrentMonth.clear();
              int currentMonthAbsent = 0;
              int currentMonthLate = 0;

              final now = DateTime.now();
              final todayIso = DateFormat('yyyy-MM-dd').format(now);
              bool markedTodayInDb = false;
              String todayTimeInDb = '';
              String todayDateInDb = '';
              final Set<String> processedHistoryDates = {};

              for (var row in attendanceData) {
                final status = row['status']?.toString() ?? 'Present';
                final userType = row['user_type']?.toString().toLowerCase() ?? '';
                final role = row['role']?.toString().toLowerCase() ?? '';

                final isStaffDutyLog = userType == 'staff' ||
                    (role == 'staff' || role == 'head receptionist' || role == 'trainer' || role == 'receptionist');

                // An automated absence or missed shift for staff duties should NEVER mark the member as Absent in Member App!
                if (isStaffDutyLog && (status == 'Absent' || status == 'Leave' || status == 'On Leave')) {
                  continue; // Skip staff absence/leave records in Member App!
                }

                final rawDateStr = row['date']?.toString() ?? '';
                final rawCheckIn = row['check_in']?.toString() ?? '';
                final rawCheckOut = row['check_out']?.toString() ?? '';

                DateTime? parsedDate;
                if (rawCheckIn.isNotEmpty) {
                  try {
                    parsedDate = DateTime.parse(rawCheckIn).toLocal();
                  } catch (_) {}
                }
                if (parsedDate == null && rawDateStr.isNotEmpty) {
                  try {
                    parsedDate = DateTime.parse(rawDateStr);
                  } catch (_) {
                    try {
                      parsedDate = DateFormat('dd-MM-yyyy').parse(rawDateStr);
                    } catch (_) {}
                  }
                }

                if (parsedDate != null) {
                  final isoDateStr = DateFormat('yyyy-MM-dd').format(parsedDate);
                  final isPresentStatus = (status == 'Present' || status == 'Late' || status == 'Early Exit' || status == 'Overtime');
                  final existingStatus = _attendanceMapByIsoDate[isoDateStr];
                  final existingIsPresent = existingStatus != null &&
                      (existingStatus == 'Present' || existingStatus == 'Late' || existingStatus == 'Early Exit' || existingStatus == 'Overtime');

                  // Never overwrite an existing Present record with an Absent record on the same date!
                  if (isPresentStatus || !existingIsPresent) {
                    _attendanceMapByIsoDate[isoDateStr] = status;
                  }

                  if (parsedDate.month == now.month && parsedDate.year == now.year) {
                    final isSun = parsedDate.weekday == DateTime.sunday;
                    final isDecHol = _declaredHolidays.any((h) => h.startsWith(isoDateStr));
                    if (!isSun && !isDecHol && isPresentStatus) {
                      if (!_attendedDaysOfCurrentMonth.contains(parsedDate.day)) {
                        _attendedDaysOfCurrentMonth.add(parsedDate.day);
                      }
                    } else if (status == 'Absent' && !existingIsPresent) {
                      currentMonthAbsent++;
                    } else if (status == 'Late') {
                      currentMonthLate++;
                    }
                  }
                }

                bool isRowToday = false;
                if (rawDateStr.startsWith(todayIso)) {
                  isRowToday = true;
                } else if (rawCheckIn.isNotEmpty) {
                  try {
                    final dt = DateTime.parse(rawCheckIn).toLocal();
                    if (DateFormat('yyyy-MM-dd').format(dt) == todayIso) {
                      isRowToday = true;
                    }
                  } catch (_) {}
                }

                if (isRowToday && status != 'Absent' && status != 'Leave' && status != 'On Leave') {
                  markedTodayInDb = true;
                  if (rawCheckIn.isNotEmpty) {
                    try {
                      todayTimeInDb = DateFormat('hh:mm a').format(DateTime.parse(rawCheckIn).toLocal());
                    } catch (_) {
                      todayTimeInDb = rawCheckIn;
                    }
                  }
                  todayDateInDb = DateFormat('dd-MM-yyyy').format(now);
                }

                String displayDate = 'Unknown Date';
                if (parsedDate != null) {
                  displayDate = DateFormat('dd MMM yyyy').format(parsedDate);
                }

                String checkInTime = '—';
                if (rawCheckIn.isNotEmpty) {
                  try {
                    checkInTime = DateFormat('hh:mm a').format(DateTime.parse(rawCheckIn).toLocal());
                  } catch (_) {
                    checkInTime = rawCheckIn;
                  }
                }

                String checkOutTime = '—';
                if (rawCheckOut.isNotEmpty) {
                  try {
                    checkOutTime = DateFormat('hh:mm a').format(DateTime.parse(rawCheckOut).toLocal());
                  } catch (_) {
                    checkOutTime = rawCheckOut;
                  }
                }

                // Add to Check In History (avoid duplicating day if one is already present)
                final historyKey = parsedDate != null ? DateFormat('yyyy-MM-dd').format(parsedDate) : displayDate;
                if (!processedHistoryDates.contains(historyKey) || status == 'Present') {
                  if (status == 'Present' && processedHistoryDates.contains(historyKey)) {
                    _attendanceHistory.removeWhere((e) => e['isoDate'] == historyKey);
                  }
                  processedHistoryDates.add(historyKey);
                  _attendanceHistory.add({
                    'date': displayDate,
                    'isoDate': parsedDate != null ? DateFormat('yyyy-MM-dd').format(parsedDate) : '',
                    'checkIn': checkInTime,
                    'checkOut': checkOutTime,
                    'status': status,
                    'parsedDateTime': parsedDate,
                  });
                }
              }

              // Explicitly sort Check In History strictly descending by parsedDateTime (latest first)
              _attendanceHistory.sort((a, b) {
                final dtA = a['parsedDateTime'] as DateTime?;
                final dtB = b['parsedDateTime'] as DateTime?;
                if (dtA != null && dtB != null) {
                  return dtB.compareTo(dtA);
                }
                return 0;
              });

              // Present days is strictly for current month (never 50/27)
              _presentDays = _attendedDaysOfCurrentMonth.length;
              _absentDays = currentMonthAbsent;
              _lateDays = currentMonthLate;

              if (markedTodayInDb) {
                _checkedInToday = true;
                _checkInTime = todayTimeInDb.isNotEmpty ? todayTimeInDb : (_checkInTime.isNotEmpty ? _checkInTime : DateFormat('hh:mm a').format(now));
                _checkInDate = todayDateInDb.isNotEmpty ? todayDateInDb : DateFormat('dd-MM-yyyy').format(now);
                _checkInDateIso = todayIso;
                prefs.setBool('member_checked_in_today', true);
                prefs.setString('member_check_in_time', _checkInTime);
                prefs.setString('member_check_in_date', _checkInDate);
                prefs.setString('member_check_in_date_iso', todayIso);
              } else {
                _checkedInToday = false;
                _checkInTime = '';
                _checkInDate = '';
                _checkInDateIso = '';
                prefs.setBool('member_checked_in_today', false);
                prefs.remove('member_check_in_time');
                prefs.remove('member_check_in_date');
                prefs.remove('member_check_in_date_iso');
              }

              // Attendance % calculation
              int totalGymDays = 0;
              final lastDay = DateTime(now.year, now.month + 1, 0).day;
              for (int i = 1; i <= lastDay; i++) {
                if (DateTime(now.year, now.month, i).weekday != DateTime.sunday) {
                  totalGymDays++;
                }
              }
              _attendancePercentage = totalGymDays > 0 ? ((_presentDays / totalGymDays) * 100).round() : 0;

              prefs.setString('member_cached_attendance_history', jsonEncode(_attendanceHistory));
              prefs.setInt('member_cached_present_days', _presentDays);
              prefs.setInt('member_cached_absent_days', _absentDays);
              prefs.setInt('member_cached_late_days', _lateDays);
              prefs.setStringList('member_cached_attended_days_curr_month', _attendedDaysOfCurrentMonth.map((e) => e.toString()).toList());
              prefs.setString('member_cached_attendance_days', jsonEncode(_attendedDaysOfCurrentMonth));
              prefs.setString('member_cached_attendance_map', jsonEncode(_attendanceMapByIsoDate));
            }
          } catch (_) {}
        }

        // Run all independent queries in parallel via Future.wait
        await Future.wait([
          fetchWorkoutPlanTask(),
          fetchGymDetailsTask(),
          fetchDietPlanTask(),
          fetchMembershipAndPaymentsTask(),
          fetchWorkoutLogsTask(),
          fetchBodyStatsTask(),
          fetchStreakTask(),
          fetchGamificationTask(),
          fetchHolidaysTask(),
          fetchDailyWellnessTask(),
          fetchAttendanceHistoryTask(),
        ]);

        // Setup Realtime listener for member row updates
        try {
          _memberSubscription?.unsubscribe();
          _memberSubscription = SupabaseService.client
              .channel('public:members:id=eq.${memberData['id']}')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'members',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'id',
                  value: memberData['id'],
                ),
                callback: (payload) {
                  final newRecord = payload.newRecord;
                  if (newRecord != null) {
                    _pendingAmount = (newRecord['pending_amount'] as num?)?.toDouble() ?? 0.0;
                    _memberName = newRecord['name'] ?? _memberName;
                    _memberAvatar = (newRecord['avatar'] != null && newRecord['avatar'].toString().isNotEmpty) 
                        ? newRecord['avatar'] 
                        : _memberAvatar;
                    _membershipStatus = newRecord['status'] ?? _membershipStatus;

                    final newWorkoutId = newRecord['assigned_workout_id']?.toString() ?? '';
                    if (newWorkoutId != _assignedWorkoutId) {
                      _assignedWorkoutId = newWorkoutId;
                      prefs.setString('member_cached_workout_id', _assignedWorkoutId);
                      fetchWorkoutPlanTask();
                    }

                    notifyListeners();
                  }
                },
              );
          _memberSubscription?.subscribe();
        } catch (_) {}

        _isMemberCodeVerified = true;
        _isLoggedIn = true;

        await checkRulesAgreementStatus();
      } else {
        clearAllDataInMemory();
      }
    } catch (e) {
      print('loadMemberDataFromSupabase error: $e');
    } finally {
      _isLoadingMemberData = false;
      if (_loadingMemberDataCompleter != null && !_loadingMemberDataCompleter!.isCompleted) {
        _loadingMemberDataCompleter!.complete();
      }
      _loadingMemberDataCompleter = null;
      notifyListeners();
    }
  }

  /// Fast, targeted attendance refresh without reloading the entire member profile
  Future<void> fetchAttendanceOnly() async {
    final authUid = SupabaseService.client.auth.currentUser?.id ?? '';
    if (_memberId.isEmpty && authUid.isEmpty) return;

    try {
      final now = DateTime.now();

      // Refresh declared holidays if gymId available
      if (_gymId.isNotEmpty) {
        try {
          final holidaysRes = await SupabaseService.client
              .from('holidays')
              .select('holiday_date, date')
              .eq('gym_id', _gymId);
          final Set<String> hDates = {};
          for (var h in holidaysRes) {
            final dStr = h['holiday_date']?.toString() ?? h['date']?.toString() ?? '';
            if (dStr.isNotEmpty) hDates.add(dStr);
          }
          _declaredHolidays = hDates.toList();
          final prefs = await SharedPreferences.getInstance();
          prefs.setStringList('member_declared_holidays', _declaredHolidays);
        } catch (_) {}
      }

      var attQuery = SupabaseService.client
          .from('attendance_logs')
          .select('date, check_in, check_out, status, user_type, role, member_id, user_id');
      if (_memberId.isNotEmpty && authUid.isNotEmpty) {
        attQuery = attQuery.or('member_id.eq.$_memberId,user_id.eq.$authUid');
      } else if (_memberId.isNotEmpty) {
        attQuery = attQuery.eq('member_id', _memberId);
      } else if (authUid.isNotEmpty) {
        attQuery = attQuery.eq('user_id', authUid);
      }

      // Order by check_in descending so latest records are retrieved first
      final attendanceData = await attQuery
          .order('check_in', ascending: false)
          .limit(365);

      if (attendanceData.isNotEmpty) {
        _attendanceHistory.clear();
        _attendanceMapByIsoDate.clear();
        _attendedDaysOfCurrentMonth.clear();
        int currentMonthAbsent = 0;
        int currentMonthLate = 0;

        final todayIso = DateFormat('yyyy-MM-dd').format(now);
        bool markedTodayInDb = false;
        String todayTimeInDb = '';
        String todayDateInDb = '';
        final Set<String> processedHistoryDates = {};

        for (var row in attendanceData) {
          final status = row['status']?.toString() ?? 'Present';
          final userType = row['user_type']?.toString().toLowerCase() ?? '';
          final role = row['role']?.toString().toLowerCase() ?? '';

          final isStaffDutyLog = userType == 'staff' ||
              (role == 'staff' || role == 'head receptionist' || role == 'trainer' || role == 'receptionist');

          // An automated absence or missed shift for staff duties should NEVER mark the member as Absent in Member App!
          if (isStaffDutyLog && (status == 'Absent' || status == 'Leave' || status == 'On Leave')) {
            continue; // Skip staff absence/leave records in Member App!
          }

          final rawDateStr = row['date']?.toString() ?? '';
          final rawCheckIn = row['check_in']?.toString() ?? '';
          final rawCheckOut = row['check_out']?.toString() ?? '';

          DateTime? parsedDate;
          if (rawCheckIn.isNotEmpty) {
            try {
              parsedDate = DateTime.parse(rawCheckIn).toLocal();
            } catch (_) {}
          }
          if (parsedDate == null && rawDateStr.isNotEmpty) {
            try {
              parsedDate = DateTime.parse(rawDateStr);
            } catch (_) {
              try {
                parsedDate = DateFormat('dd-MM-yyyy').parse(rawDateStr);
              } catch (_) {}
            }
          }

          if (parsedDate != null) {
            final isoDateStr = DateFormat('yyyy-MM-dd').format(parsedDate);
            final isPresentStatus = (status == 'Present' || status == 'Late' || status == 'Early Exit' || status == 'Overtime');
            final existingStatus = _attendanceMapByIsoDate[isoDateStr];
            final existingIsPresent = existingStatus != null &&
                (existingStatus == 'Present' || existingStatus == 'Late' || existingStatus == 'Early Exit' || existingStatus == 'Overtime');

            // Never overwrite an existing Present record with an Absent record on the same date!
            if (isPresentStatus || !existingIsPresent) {
              _attendanceMapByIsoDate[isoDateStr] = status;
            }

            if (parsedDate.month == now.month && parsedDate.year == now.year) {
              final isSun = parsedDate.weekday == DateTime.sunday;
              final isDecHol = _declaredHolidays.any((h) => h.startsWith(isoDateStr));
              if (!isSun && !isDecHol && isPresentStatus) {
                if (!_attendedDaysOfCurrentMonth.contains(parsedDate.day)) {
                  _attendedDaysOfCurrentMonth.add(parsedDate.day);
                }
              } else if (status == 'Absent' && !existingIsPresent) {
                currentMonthAbsent++;
              } else if (status == 'Late') {
                currentMonthLate++;
              }
            }
          }

          bool isRowToday = false;
          if (rawDateStr.startsWith(todayIso)) {
            isRowToday = true;
          } else if (rawCheckIn.isNotEmpty) {
            try {
              final dt = DateTime.parse(rawCheckIn).toLocal();
              if (DateFormat('yyyy-MM-dd').format(dt) == todayIso) {
                isRowToday = true;
              }
            } catch (_) {}
          }

          if (isRowToday && status != 'Absent' && status != 'Leave' && status != 'On Leave') {
            markedTodayInDb = true;
            if (rawCheckIn.isNotEmpty) {
              try {
                todayTimeInDb = DateFormat('hh:mm a').format(DateTime.parse(rawCheckIn).toLocal());
              } catch (_) {
                todayTimeInDb = rawCheckIn;
              }
            }
            todayDateInDb = DateFormat('dd-MM-yyyy').format(now);
          }

          String displayDate = 'Unknown Date';
          if (parsedDate != null) {
            displayDate = DateFormat('dd MMM yyyy').format(parsedDate);
          }

          String checkInTime = '—';
          if (rawCheckIn.isNotEmpty) {
            try {
              checkInTime = DateFormat('hh:mm a').format(DateTime.parse(rawCheckIn).toLocal());
            } catch (_) {
              checkInTime = rawCheckIn;
            }
          }

          String checkOutTime = '—';
          if (rawCheckOut.isNotEmpty) {
            try {
              checkOutTime = DateFormat('hh:mm a').format(DateTime.parse(rawCheckOut).toLocal());
            } catch (_) {
              checkOutTime = rawCheckOut;
            }
          }

          // Add to Check In History (avoid duplicating day if one is already present)
          final historyKey = parsedDate != null ? DateFormat('yyyy-MM-dd').format(parsedDate) : displayDate;
          if (!processedHistoryDates.contains(historyKey) || status == 'Present') {
            if (status == 'Present' && processedHistoryDates.contains(historyKey)) {
              _attendanceHistory.removeWhere((e) => e['isoDate'] == historyKey);
            }
            processedHistoryDates.add(historyKey);
            _attendanceHistory.add({
              'date': displayDate,
              'isoDate': parsedDate != null ? DateFormat('yyyy-MM-dd').format(parsedDate) : '',
              'checkIn': checkInTime,
              'checkOut': checkOutTime,
              'status': status,
              'parsedDateTime': parsedDate,
            });
          }
        }

        // Explicitly sort Check In History strictly descending by parsedDateTime (latest first)
        _attendanceHistory.sort((a, b) {
          final dtA = a['parsedDateTime'] as DateTime?;
          final dtB = b['parsedDateTime'] as DateTime?;
          if (dtA != null && dtB != null) {
            return dtB.compareTo(dtA);
          }
          return 0;
        });

        // Present days is strictly for current month (never 50/27)
        _presentDays = _attendedDaysOfCurrentMonth.length;
        _absentDays = currentMonthAbsent;
        _lateDays = currentMonthLate;

        if (markedTodayInDb) {
          _checkedInToday = true;
          _checkInTime = todayTimeInDb.isNotEmpty ? todayTimeInDb : (_checkInTime.isNotEmpty ? _checkInTime : DateFormat('hh:mm a').format(now));
          _checkInDate = todayDateInDb.isNotEmpty ? todayDateInDb : DateFormat('dd-MM-yyyy').format(now);
          _checkInDateIso = todayIso;
        }

        int totalDaysCount = 0;
        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        for (int i = 1; i <= lastDay; i++) {
          if (DateTime(now.year, now.month, i).weekday != DateTime.sunday) {
            totalDaysCount++;
          }
        }
        _attendancePercentage = totalDaysCount > 0 ? ((_presentDays / totalDaysCount) * 100).round() : 0;

        final prefs = await SharedPreferences.getInstance();
        prefs.setString('member_cached_attendance_history', jsonEncode(_attendanceHistory));
        prefs.setInt('member_cached_present_days', _presentDays);
        prefs.setInt('member_cached_absent_days', _absentDays);
        prefs.setInt('member_cached_late_days', _lateDays);
        prefs.setStringList('member_cached_attended_days_curr_month', _attendedDaysOfCurrentMonth.map((e) => e.toString()).toList());
        prefs.setString('member_cached_attendance_days', jsonEncode(_attendedDaysOfCurrentMonth));
        prefs.setString('member_cached_attendance_map', jsonEncode(_attendanceMapByIsoDate));

        notifyListeners();
      }
    } catch (e) {
      print('fetchAttendanceOnly error: $e');
    }
  }

  // ── Gym Rules & Agreement Methods (Phase 09) ──
  Future<bool> checkRulesAgreementStatus() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. If memory already has true, NEVER revert to false
    if (_hasAgreedRules) {
      return true;
    }

    // 2. Restore cached IDs if empty
    if (_memberId.isEmpty || _gymId.isEmpty) {
      _memberId = prefs.getString('member_cached_id') ?? _memberId;
      _gymId = prefs.getString('member_cached_gym_id') ?? _gymId;
      _gymName = prefs.getString('member_cached_gym_name') ?? _gymName;
    }

    final cacheKey = 'gymos_rule_agreed_${_gymId}_$_memberId';
    final isAgreedLocally = (prefs.getBool(cacheKey) == true) ||
        (_memberId.isNotEmpty && (prefs.getBool('gymos_rule_agreed_member_$_memberId') == true)) ||
        (prefs.getBool('gymos_rule_agreed_global') == true);

    if (isAgreedLocally) {
      _hasAgreedRules = true;
      notifyListeners();
      return true;
    }

    if (_memberId.isEmpty || _gymId.isEmpty) {
      if (SupabaseService.isInitialized && SupabaseService.client.auth.currentUser != null) {
        await loadMemberDataFromSupabase();
      }
    }

    if (_hasAgreedRules) return true;
    if (_memberId.isEmpty || _gymId.isEmpty) return false;

    _isCheckingAgreement = true;
    notifyListeners();

    try {
      if (SupabaseService.isInitialized) {
        var query = SupabaseService.client
            .from('member_rule_agreements')
            .select();

        if (_memberId.isNotEmpty) {
          query = query.eq('member_id', _memberId);
        } else {
          final user = SupabaseService.client.auth.currentUser;
          if (user != null) {
            query = query.eq('user_id', user.id);
          }
        }

        final res = await query
            .order('agreed_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (res != null && res['agreed'] == true) {
          _agreementRecord = MemberAgreementRecord.fromMap(Map<String, dynamic>.from(res));
          _hasAgreedRules = true;
          await prefs.setBool(cacheKey, true);
          await prefs.setBool('gymos_rule_agreed_member_$_memberId', true);
          await prefs.setBool('gymos_rule_agreed_global', true);
          await prefs.setString('${cacheKey}_record', jsonEncode(_agreementRecord!.toMap()));
          await prefs.setString('gymos_rule_agreed_record_global', jsonEncode(_agreementRecord!.toMap()));

        } else {
          if (!_hasAgreedRules) {
            _hasAgreedRules = false;
            _agreementRecord = null;
          }
        }
      }
    } catch (e) {
      print('checkRulesAgreementStatus error: $e');
    } finally {
      _isCheckingAgreement = false;
      notifyListeners();
    }
    return _hasAgreedRules;
  }

  Future<bool> submitRulesAgreement({required String languageCode}) async {
    if (_memberId.isEmpty || _gymId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      _memberId = prefs.getString('member_cached_id') ?? _memberId;
      _gymId = prefs.getString('member_cached_gym_id') ?? _gymId;
      _gymName = prefs.getString('member_cached_gym_name') ?? _gymName;
      if (_memberId.isEmpty || _gymId.isEmpty) {
        await loadMemberDataFromSupabase();
      }
    }
    if (_memberId.isEmpty || _gymId.isEmpty) return false;
    _isSubmittingAgreement = true;
    notifyListeners();

    try {
      final user = SupabaseService.client.auth.currentUser;
      final now = DateTime.now();

      final payload = {
        'gym_id': _gymId,
        'member_id': _memberId,
        'user_id': user?.id,
        'member_name': _memberName.isNotEmpty ? _memberName : 'Member',
        'member_phone': user?.phone ?? '',
        'rules_version': _currentRulesVersion,
        'language': languageCode,
        'agreed': true,
        'agreed_at': now.toIso8601String(),
        'device_info': kIsWeb ? 'Web Browser' : 'Mobile App',
      };

      if (SupabaseService.isInitialized) {
        try {
          final rpcRes = await SupabaseService.client.rpc(
            'submit_member_rule_agreement',
            params: {
              'p_gym_id': _gymId,
              'p_member_id': _memberId,
              'p_user_id': user?.id,
              'p_member_name': _memberName.isNotEmpty ? _memberName : 'Member',
              'p_member_phone': user?.phone ?? '',
              'p_rules_version': _currentRulesVersion,
              'p_language': languageCode,
              'p_device_info': kIsWeb ? 'Web Browser' : 'Mobile App',
            },
          );
          if (rpcRes != null && rpcRes is Map) {
            _agreementRecord = MemberAgreementRecord.fromMap(Map<String, dynamic>.from(rpcRes));
          }
        } catch (rpcErr) {
          print('RPC submit_member_rule_agreement fallback: $rpcErr');
          try {
            final res = await SupabaseService.client
                .from('member_rule_agreements')
                .upsert(payload, onConflict: 'gym_id, member_id, rules_version')
                .select()
                .maybeSingle();

            if (res != null) {
              _agreementRecord = MemberAgreementRecord.fromMap(Map<String, dynamic>.from(res));
            }
          } catch (upsertErr) {
            print('Direct upsert fallback: $upsertErr');
          }
        }
      }

      // Guarantee local persistence so the member is NEVER trapped in the modal
      _agreementRecord ??= MemberAgreementRecord.fromMap(payload);
      _hasAgreedRules = true;
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'gymos_rule_agreed_${_gymId}_$_memberId';
      await prefs.setBool(cacheKey, true);
      await prefs.setBool('gymos_rule_agreed_member_$_memberId', true);
      if (user != null) {
        await prefs.setBool('gymos_rule_agreed_user_${user.id}', true);
      }
      await prefs.setBool('gymos_rule_agreed_global', true);
      await prefs.setString('${cacheKey}_record', jsonEncode(_agreementRecord!.toMap()));
      await prefs.setString('gymos_rule_agreed_record_global', jsonEncode(_agreementRecord!.toMap()));

      notifyListeners();
      return true;
    } catch (e) {
      print('submitRulesAgreement error: $e');
      _hasAgreedRules = true;
      notifyListeners();
      return true;
    } finally {
      _isSubmittingAgreement = false;
      notifyListeners();
    }
  }

  // ── Auth Methods ──

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (SupabaseService.isInitialized) {
        // Clean sign out of previous session
        try {
          await SupabaseService.client.auth.signOut();
        } catch (_) {}

        final response = await SupabaseService.client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );

        if (response.user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('member_logged_in', true);
          
          // Verify that this user is indeed a member
          final memberRecord = await SupabaseService.client
              .from('members')
              .select()
              .eq('user_id', response.user!.id)
              .maybeSingle();

          if (memberRecord != null) {
            _isLoggedIn = true;
            _isLoading = false;
            await loadMemberDataFromSupabase();
            notifyListeners();
            return true;
          } else {
            // Not a member! Sign out.
            await SupabaseService.client.auth.signOut();
          }
        }
      }
    } catch (e) {
      print('Member login error: $e');
    }

    _isLoading = false;
    _isLoggedIn = false;
    notifyListeners();
    return false;
  }

  Future<bool> verifyMemberCode(String code) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (SupabaseService.isInitialized) {
        final user = SupabaseService.client.auth.currentUser;
        if (user != null) {
          final memberRecord = await SupabaseService.client
              .from('members')
              .select()
              .eq('user_id', user.id)
              .maybeSingle();

          if (memberRecord != null) {
            _isMemberCodeVerified = true;
            _isLoading = false;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('member_code_verified', true);
            notifyListeners();
            return true;
          }
        }
      }
    } catch (e) {
      print('Verify code error: $e');
    }

    _isMemberCodeVerified = false;
    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteAccount() async {
    try {
      if (SupabaseService.isInitialized && _memberId.isNotEmpty) {
        try {
          await SupabaseService.client
              .from('member_body_logs')
              .delete()
              .eq('member_id', _memberId);
          await SupabaseService.client
              .from('member_workout_sets')
              .delete()
              .eq('member_id', _memberId);
          await SupabaseService.client
              .from('member_personal_records')
              .delete()
              .eq('member_id', _memberId);
          await SupabaseService.client
              .from('member_weekly_schedule')
              .delete()
              .eq('member_id', _memberId);
          await SupabaseService.client
              .from('member_fitness_goals')
              .delete()
              .eq('member_id', _memberId);
          await SupabaseService.client
              .from('members')
              .delete()
              .eq('id', _memberId);
        } catch (e) {
          debugPrint('Error deleting member rows: $e');
        }
        final uid = SupabaseService.client.auth.currentUser?.id;
        if (uid != null) {
          try {
            await SupabaseService.client
                .rpc('delete_user_account', params: {'p_user_id': uid});
          } catch (_) {}
        }
      }
      await logout();
      return true;
    } catch (e) {
      debugPrint('Error in deleteAccount: $e');
      await logout();
      return true;
    }
  }

  Future<void> logout() async {
    clearAllDataInMemory();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('member_logged_in');
    await prefs.remove('member_code_verified');
    await prefs.remove('member_checked_in_today');
    await prefs.remove('member_check_in_time');
    await prefs.remove('member_check_in_date');
    await prefs.remove('member_cached_workout_title');
    await prefs.remove('member_cached_workout_id');
    await prefs.remove('member_cached_workout_schedule');
    if (_memberId.isNotEmpty) {
      await prefs.remove('member_cached_workout_schedule_$_memberId');
    }
    await prefs.remove('member_cached_today_muscle');
    await prefs.remove('member_cached_today_splits');
    await prefs.remove('member_cached_diet_title');
    await prefs.remove('member_cached_diet_plan_json');
    _assignedDietPlan = null;
    await prefs.remove('member_cached_attendance_days');
    await prefs.remove('member_cached_days_left');
    await prefs.remove('member_cached_days_timestamp');
    try {
      if (SupabaseService.client != null) {
        await SupabaseService.client.auth.signOut();
      }
    } catch (_) {}
  }

  void clearAllDataInMemory() {
    _memberSubscription?.unsubscribe();
    _memberSubscription = null;
    _isLoggedIn = false;
    _isMemberCodeVerified = false;

    // Reset all member fields to defaults
    _memberName = '';
    _memberId = '';
    _gymName = '';
    _memberAvatar = 'assets/images/member/avatar_default.png';
    _notificationCount = 0;
    _weight = '';
    _height = '';
    _bodyFat = '';
    _fitnessGoal = '';
    _currentStreak = 0;
    _weekAttendance = [false, false, false, false, false, false, false];
    _attendancePercentage = 0;
    _membershipDaysLeft = 0;
    _pendingAmount = 0.0;
    _todayMuscleGroup = 'No Plan Assigned';
    _todaySplits = [];
    _weeklyWorkoutSchedule.clear();
    _isTrainingCompleted = false;
    _membershipPlan = '';
    _membershipStatus = 'Inactive';
    _membershipStartDate = '';
    _membershipEndDate = '';
    _rawMembershipStartDate = '';
    _rawMembershipEndDate = '';
    _membershipTimeRemaining = 0;
    _planDuration = '';
    _amountPaid = '';
    _nextDue = '';
    _currentLevel = 1;
    _currentXP = 0;
    _nextLevelXP = 100;
    _nextMilestoneTarget = 30;
    _currentMilestoneProgress = 0;
    _currentTitle = '🌱 New Member';
    _achievements.clear();
    _presentDays = 0;
    _absentDays = 0;
    _lateDays = 0;
    _attendedDaysOfCurrentMonth = [];
    _attendanceMapByIsoDate.clear();
    _checkInTime = '';
    _checkInDate = '';
    _checkedInToday = false;
    _loadingMemberDataCompleter = null;

    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('member_cached_id');
      prefs.remove('member_cached_name');
      prefs.remove('member_cached_gym_id');
      prefs.remove('member_cached_gym_name');
      prefs.remove('member_cached_gym_logo');
      prefs.remove('member_cached_join_date');
      prefs.remove('member_cached_workout_title');
      prefs.remove('member_cached_today_muscle');
      prefs.remove('member_cached_today_splits');
      prefs.remove('member_cached_diet_title');
      prefs.remove('member_cached_diet_plan_json');
      prefs.remove('member_cached_attendance_method');
      prefs.remove('member_cached_attendance_enabled');
    });

    // NOTE: _hasAgreedRules and _agreementRecord are NEVER cleared.
    // Once a member agrees to gym rules, it is permanent and irreversible.
    // Agreement persists across logout/login cycles.

    notifyListeners();
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _memberSubscription?.unsubscribe();
    super.dispose();
  }

  // ── Check-in ──
  Future<Map<String, dynamic>> markCheckIn(String qrToken) async {
    final tokenToUse = qrToken.trim();
    if (tokenToUse.isEmpty) {
      return {
        'success': false,
        'reason': 'QR code is required. Please scan a valid QR code.',
        'message': 'No QR code detected. Please scan the QR code to check in.',
      };
    }

    if (_isCheckingIn) {
      return {
        'success': false,
        'reason': 'Check-in is already in progress. Please wait a moment.',
        'message': 'Check-in in progress.',
      };
    }

    _isCheckingIn = true;
    notifyListeners();

    try {
      if (SupabaseService.isInitialized) {
        final res = await SupabaseService.client.rpc('process_qr_attendance', params: {
          'p_token': tokenToUse,
          'p_user_type': 'Member',
        });
        final Map<String, dynamic> result = Map<String, dynamic>.from(res as Map);
        if (result['success'] == true) {
          final now = DateTime.now();
          final todayIso = DateFormat('yyyy-MM-dd').format(now);
          _checkedInToday = true;
          _checkInTime = result['check_in'] ?? DateFormat('hh:mm a').format(now);
          _checkInDate = result['attendance_date'] ?? DateFormat('dd MMM yyyy').format(now);
          _checkInDateIso = todayIso;
          if (result['already_marked'] != true) {
            _currentStreak += 1;
            _currentXP += 250;
          }
          final isSun = now.weekday == DateTime.sunday;
          final isDecHol = _declaredHolidays.any((h) => h.startsWith(todayIso));
          _attendanceMapByIsoDate[todayIso] = 'Present';
          if (!isSun && !isDecHol) {
            if (!_attendedDaysOfCurrentMonth.contains(now.day)) {
              _attendedDaysOfCurrentMonth.add(now.day);
              _presentDays = _attendedDaysOfCurrentMonth.length;
            }
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('member_checked_in_today', true);
          await prefs.setString('member_check_in_time', _checkInTime);
          await prefs.setString('member_check_in_date', _checkInDate);
          await prefs.setString('member_check_in_date_iso', todayIso);
          try {
            await loadMemberDataFromSupabase();
          } catch (e) {
            print('Error refreshing member achievements: $e');
          }
          notifyListeners();
        }
        return result;
      }
    } catch (e) {
      print('Error marking member check-in: $e');
      return {'success': false, 'reason': e.toString()};
    } finally {
      _isCheckingIn = false;
      notifyListeners();
    }
    return {'success': false, 'reason': 'Supabase service not initialized.'};
  }

  // ── Refresh Quote ──
  void refreshQuote() {
    _currentQuote = _quotes[Random().nextInt(_quotes.length)];
    notifyListeners();
  }

  void addPaymentHistoryEntry({required double amount, required String method, required String notes}) {
    final invoiceNum = 'INV-2026-${100 + _paymentHistory.length + 1}';
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    _paymentHistory.insert(0, {
      'invoice': invoiceNum,
      'date': DateFormat('dd MMM yyyy').format(DateTime.now()),
      'amount': formatter.format(amount),
      'status': 'Paid',
    });
    // Decrease membership days left or update next due date to simulate updates
    _membershipDaysLeft += 30;
    _notificationCount += 1;
    notifyListeners();
  }

  Future<bool> updateBodyStats({
    required String weight,
    required String height,
    required String bodyFat,
  }) async {
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return false;

      final memberData = await SupabaseService.client
          .from('members')
          .select('extra_fields')
          .eq('user_id', user.id)
          .maybeSingle();

      final Map<String, dynamic> extra = Map<String, dynamic>.from(
        (memberData?['extra_fields'] as Map?) ?? {}
      );

      extra['weight'] = weight;
      extra['height'] = height;
      extra['body_fat'] = bodyFat;

      await SupabaseService.client
          .from('members')
          .update({'extra_fields': extra})
          .eq('user_id', user.id);

      _weight = weight;
      _height = height;
      _bodyFat = bodyFat;
      notifyListeners();
      return true;
    } catch (e) {
      print('Error updating body stats in Supabase: $e');
      return false;
    }
  }

  Map<String, dynamic> _badgeDisplayDetails(String key) {
    switch (key) {
      case 'first_step':
        return {
          'title': 'First Step',
          'description': 'Take your first step into a larger world.',
          'requirement': 'First Attendance Check-In',
          'icon': '🌱',
          'color': const Color(0xFF10B981),
        };
      case 'week_warrior':
        return {
          'title': 'Week Warrior',
          'description': 'Keep the momentum going.',
          'requirement': '7 Consecutive Attendances',
          'icon': '🏃',
          'color': const Color(0xFF3B82F6),
        };
      case 'perfect_month':
        return {
          'title': 'Perfect Month',
          'description': 'Maximum dedication.',
          'requirement': '30 Consecutive Attendances',
          'icon': '💪',
          'color': const Color(0xFFEC4899),
        };
      case 'century_club':
        return {
          'title': 'Century Club',
          'description': '100 days of fitness.',
          'requirement': '100 Total Attendances',
          'icon': '🏆',
          'color': const Color(0xFFF59E0B),
        };
      case 'club_365':
        return {
          'title': '365 Club',
          'description': 'A full year of progress.',
          'requirement': '365 Total Attendances',
          'icon': '🔥',
          'color': const Color(0xFFEF4444),
        };
      case 'early_bird':
        return {
          'title': 'Early Bird',
          'description': 'Rise and grind.',
          'requirement': '20 Attendances before 7:00 AM',
          'icon': '🌅',
          'color': const Color(0xFF6366F1),
        };
      case 'weekend_warrior':
        return {
          'title': 'Weekend Warrior',
          'description': 'No days off.',
          'requirement': '25 Weekend Attendances',
          'icon': '🛡️',
          'color': const Color(0xFF8B5CF6),
        };
      case 'monthly_machine':
        return {
          'title': 'Monthly Machine',
          'description': 'Consistent month after month.',
          'requirement': 'Complete 20 Attendances in 3 Different Months',
          'icon': '⚡',
          'color': const Color(0xFF06B6D4),
        };
      case 'half_year_hero':
        return {
          'title': 'Half-Year Hero',
          'description': 'Dedication across seasons.',
          'requirement': '180 Total Attendance Days',
          'icon': '🏆',
          'color': const Color(0xFF14B8A6),
        };
      case 'loyal_member':
        return {
          'title': 'Loyal Member',
          'description': 'Part of the family.',
          'requirement': 'Membership active for one year',
          'icon': '💎',
          'color': const Color(0xFFF472B6),
        };
      case 'attendance_master':
        return {
          'title': 'Attendance Master',
          'description': 'Mastery of consistency.',
          'requirement': '500 Total Attendances',
          'icon': '👑',
          'color': const Color(0xFFD97706),
        };
      case 'rising_star':
        return {
          'title': 'Rising Star',
          'description': 'Climbing to new heights.',
          'requirement': 'Reach Level 25',
          'icon': '🌟',
          'color': const Color(0xFF3B82F6),
        };
      case 'elite_member':
        return {
          'title': 'Elite Member',
          'description': 'Among the gym elite.',
          'requirement': 'Reach Level 50',
          'icon': '⚔️',
          'color': const Color(0xFF8B5CF6),
        };
      case 'never_miss_gym':
        return {
          'title': 'Never Miss Gym',
          'description': 'Absolute, unbroken discipline.',
          'requirement': '365 Consecutive Attendances (No Misses)',
          'icon': '🔥',
          'color': const Color(0xFFF59E0B),
        };
      case 'gymos_legend':
        return {
          'title': 'GymOS Legend',
          'description': 'The ultimate gym milestone.',
          'requirement': 'All Badges, Never Miss Gym & 365 Club, Level 99',
          'icon': '👑',
          'color': const Color(0xFFD97706),
        };
      default:
        return {
          'title': 'Unknown Badge',
          'description': '',
          'requirement': '',
          'icon': '❓',
          'color': Colors.grey,
        };
    }
  }
}
