import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/diet_plan.dart';

class MemberAppViewModel extends ChangeNotifier {
  // ── Auth State ──
  bool _isLoggedIn = false;
  bool _isMemberCodeVerified = false;
  bool _isLoading = false;
  RealtimeChannel? _memberSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;

  // ── Member Profile ──
  String _memberName = 'Jigar Patel';
  String _memberId = 'M10042';
  String _gymName = 'GYMOS';
  String _memberAvatar = 'assets/images/member/avatar_default.png';
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

  final List<Map<String, dynamic>> _attendanceHistory = [
    {'date': '17 May 2026', 'checkIn': '07:32 AM', 'checkOut': '09:00 AM', 'status': 'Present'},
    {'date': '16 May 2026', 'checkIn': '07:45 AM', 'checkOut': '09:15 AM', 'status': 'Present'},
    {'date': '15 May 2026', 'checkIn': '08:05 AM', 'checkOut': '09:30 AM', 'status': 'Late'},
    {'date': '14 May 2026', 'checkIn': '07:30 AM', 'checkOut': '08:45 AM', 'status': 'Present'},
    {'date': '13 May 2026', 'checkIn': '07:35 AM', 'checkOut': '09:00 AM', 'status': 'Present'},
  ];

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
  bool _checkedInToday = false;
  bool _isCheckingIn = false;

  MemberAppViewModel() {
    _generateCurrentWeek();
    _currentQuote = _quotes[Random().nextInt(_quotes.length)];
    _loadPersistedState();
    if (SupabaseService.isInitialized) {
      _authStateSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        final session = data.session;
        if (event == AuthChangeEvent.signedOut) {
          clearAllDataInMemory();
        } else if ((event == AuthChangeEvent.signedIn ||
                    event == AuthChangeEvent.tokenRefreshed ||
                    event == AuthChangeEvent.initialSession) &&
                   session != null) {
          loadMemberDataFromSupabase();
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
  String get gymName => _gymName;
  String get memberAvatar => _memberAvatar;
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
  String get todayWorkoutImage {
    final group = _todayMuscleGroup.toLowerCase();
    if (group.contains('chest')) return 'assets/images/member/chest_day.png';
    if (group.contains('leg')) return 'assets/images/member/leg_day.png';
    if (group.contains('shoulder')) return 'assets/images/member/shoulder_day.png';
    if (group.contains('back')) return 'assets/images/member/back_day.png';
    if (group.contains('arm') || group.contains('tricep') || group.contains('trisep')) return 'assets/images/member/arm_day.png';
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

  // ── Persistence ──
  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    _isMemberCodeVerified = prefs.getBool('member_code_verified') ?? false;
    _isLoggedIn = prefs.getBool('member_logged_in') ?? false;
    _checkedInToday = prefs.getBool('member_checked_in_today') ?? false;
    if (_checkedInToday) {
      _checkInTime = prefs.getString('member_check_in_time') ?? '';
      _checkInDate = prefs.getString('member_check_in_date') ?? '';
    } else {
      _checkInTime = '';
      _checkInDate = '';
    }

    // Load cached workout plan, diet plan & attendance history for instant UI rendering
    _assignedWorkoutTitle = prefs.getString('member_cached_workout_title') ?? _assignedWorkoutTitle;
    _todayMuscleGroup = prefs.getString('member_cached_today_muscle') ?? _todayMuscleGroup;
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
    _presentDays = prefs.getInt('member_cached_present_days') ?? 0;
    _absentDays = prefs.getInt('member_cached_absent_days') ?? 0;
    _lateDays = prefs.getInt('member_cached_late_days') ?? 0;
    
    final cachedMonthDays = prefs.getStringList('member_cached_attended_days_curr_month');
    if (cachedMonthDays != null) {
      _attendedDaysOfCurrentMonth = cachedMonthDays.map((e) => int.parse(e)).toList();
    }
    
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

  Future<void> loadMemberDataFromSupabase() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (!SupabaseService.isInitialized) return;
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;

      final gymInfoStr = prefs.getString('gymos_gym_info');
      String? gymId;
      if (gymInfoStr != null) {
        try {
          final gymInfo = jsonDecode(gymInfoStr) as Map<String, dynamic>;
          gymId = gymInfo['id'];
        } catch (_) {}
      }

      var query = SupabaseService.client
          .from('members')
          .select()
          .eq('user_id', user.id);
      
      if (gymId != null) {
        query = query.eq('gym_id', gymId);
      }

      final memberData = await query.maybeSingle();

      if (memberData != null) {
        _memberName = memberData['name'] ?? _memberName;
        _memberId = memberData['id'] ?? _memberId;
        _memberAvatar = (memberData['avatar'] != null && memberData['avatar'].toString().isNotEmpty) 
            ? memberData['avatar'] 
            : _memberAvatar;
        _membershipStatus = memberData['status'] ?? _membershipStatus;
        _assignedWorkoutId = memberData['assigned_workout_id'] ?? '';
        _assignedDietId = memberData['assigned_diet_id'] ?? '';

        if (_assignedWorkoutId.isNotEmpty) {
          try {
            final wData = await SupabaseService.client
                .from('workout_plans')
                .select('title, schedule')
                .eq('id', _assignedWorkoutId)
                .maybeSingle();
            if (wData != null) {
              _assignedWorkoutTitle = wData['title'] ?? '';
              
              // Determine today's muscle group/day type dynamically from schedule
              dynamic rawSchedule = wData['schedule'];
              if (rawSchedule is String && rawSchedule.isNotEmpty) {
                try {
                  rawSchedule = jsonDecode(rawSchedule);
                } catch (_) {}
              }
              final todayName = DateFormat('EEEE').format(DateTime.now()); // e.g. 'Monday'
              dynamic todayList;
              if (rawSchedule is Map) {
                todayList = rawSchedule[todayName];
              }
              if (todayList is List && todayList.isNotEmpty) {
                final firstVal = todayList.first;
                if (firstVal is Map) {
                  _todayMuscleGroup = firstVal['title']?.toString() ?? 'Rest Day';
                } else {
                  _todayMuscleGroup = firstVal?.toString() ?? 'Rest Day';
                }
              } else {
                _todayMuscleGroup = 'Rest Day';
              }
              await prefs.setString('member_cached_workout_title', _assignedWorkoutTitle);
              await prefs.setString('member_cached_today_muscle', _todayMuscleGroup);
            } else {
              _assignedWorkoutTitle = '';
              _todayMuscleGroup = 'Rest Day';
            }
          } catch (_) {}
        } else {
          _assignedWorkoutTitle = '';
          _todayMuscleGroup = 'Rest Day';
        }

        final gymId = memberData['gym_id'];
        if (gymId != null) {
          final gymData = await SupabaseService.client
              .from('gyms')
              .select('name')
              .eq('id', gymId)
              .maybeSingle();
          if (gymData != null) {
            _gymName = gymData['name'] ?? _gymName;
          }
        }

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
              await prefs.setString('member_cached_diet_plan_json', jsonEncode(dData));
              await prefs.setString('member_cached_diet_title', _assignedDietTitle);
            }
          } catch (_) {}
        }

        // Fallback: If member does not have assigned diet or not found, fetch gym's default diet plan
        if (_assignedDietPlan == null && gymId != null) {
          try {
            final List gymDiets = await SupabaseService.client
                .from('diet_plans')
                .select()
                .eq('gym_id', gymId)
                .limit(1);
            if (gymDiets.isNotEmpty) {
              final firstDiet = Map<String, dynamic>.from(gymDiets.first as Map);
              _assignedDietPlan = DietPlan.fromJson(firstDiet);
              _assignedDietTitle = _assignedDietPlan!.title;
              await prefs.setString('member_cached_diet_plan_json', jsonEncode(firstDiet));
              await prefs.setString('member_cached_diet_title', _assignedDietTitle);
            }
          } catch (_) {}
        }

        if (_assignedDietPlan == null) {
          _assignedDietTitle = '';
        }

        // Keep local storage synchronized for roles and gym ID so GymRepository works correctly
        await prefs.setString('gymos_user_role', 'member');
        if (gymId != null) {
          await prefs.setString('gymos_gym_info', jsonEncode({
            'id': gymId,
            'name': _gymName,
          }));
        }

        // Fetch latest active membership from member_memberships
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
              await prefs.setInt('member_cached_days_left', _membershipDaysLeft);
              await prefs.setString('member_cached_days_timestamp', DateTime.now().toIso8601String());
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
            // Fallback to legacy single plan configuration
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
        } catch (e) {
          print('Error loading member_memberships: $e');
        }

        // Fetch real payment history from database (strictly deduplicated)
        _paymentHistory.clear();
        final Set<String> processedMembershipIds = {};
        final Set<String> seenPaymentKeys = {};

        List<dynamic>? membershipsList;
        try {
          // 1. Fetch memberships to extract direct paid amounts (safe, since we know member_memberships works)
          membershipsList = await SupabaseService.client
              .from('member_memberships')
              .select('id, start_date, total_amount, paid_amount, payment_status, membership_plans(title)')
              .eq('member_id', _memberId)
              .order('start_date', ascending: false);
        } catch (e) {
          print('Error loading member_memberships for payments: $e');
        }

        // 2. Fetch official revenue finance transactions for this member
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
              final dedupKey = '${pDate.year}-${pDate.month}-${pDate.day}_${amtNum.toStringAsFixed(0)}';

              if (!seenPaymentKeys.contains(dedupKey) && !seenPaymentKeys.contains(tx['id'].toString())) {
                seenPaymentKeys.add(dedupKey);
                seenPaymentKeys.add(tx['id'].toString());
                final invoiceNum = 'INV-${pDate.year}-${tx['id'].toString().replaceAll('-', '').substring(0, 4).toUpperCase()}';
                _paymentHistory.add({
                  'invoice': invoiceNum,
                  'date': formattedDate,
                  'amount': amtStr,
                  'status': 'Paid',
                  'raw_date': pDate,
                });
              }
            }
          }
        } catch (e) {
          print('Error loading finance transactions for payments: $e');
        }

        try {
          // 3. Fetch explicit membership payments
          final paymentsData = await SupabaseService.client
              .from('membership_payments')
              .select('id, amount, payment_date, member_membership_id')
              .order('payment_date', ascending: false);

          if (paymentsData != null && paymentsData.isNotEmpty) {
            for (var pay in paymentsData) {
              final mId = pay['member_membership_id']?.toString() ?? '';
              final belongsToUser = membershipsList?.any((m) => m['id'].toString() == mId) ?? false;
              if (belongsToUser) {
                processedMembershipIds.add(mId);
                final amtVal = pay['amount'];
                if (amtVal == null || (amtVal is num && amtVal <= 0)) continue;
                final pDate = DateTime.tryParse(pay['payment_date'] ?? '') ?? DateTime.now();
                final formattedDate = DateFormat('dd MMM yyyy').format(pDate);
                final amtNum = (amtVal is num) ? amtVal.toDouble() : double.tryParse(amtVal.toString()) ?? 0.0;
                final amtStr = '₹${amtNum.toStringAsFixed(0)}';
                final dedupKey = '${pDate.year}-${pDate.month}-${pDate.day}_${amtNum.toStringAsFixed(0)}';

                if (!seenPaymentKeys.contains(dedupKey) && !seenPaymentKeys.contains(pay['id'].toString())) {
                  seenPaymentKeys.add(dedupKey);
                  seenPaymentKeys.add(pay['id'].toString());
                  final invoiceNum = 'INV-${pDate.year}-${pay['id'].toString().replaceAll('-', '').substring(0, 4).toUpperCase()}';
                  _paymentHistory.add({
                    'invoice': invoiceNum,
                    'date': formattedDate,
                    'amount': amtStr,
                    'status': 'Paid',
                    'raw_date': pDate,
                  });
                }
              }
            }
          }
        } catch (e) {
          print('Error loading membership_payments: $e');
        }

        // 4. Fallback: for memberships that don't have explicit payments in membership_payments,
        // but have paid_amount > 0 in member_memberships, synthesize a payment history entry!
        if (membershipsList != null) {
          for (var mship in membershipsList) {
            final mId = mship['id'].toString();
            final paidAmount = (mship['paid_amount'] as num?)?.toDouble() ?? 0.0;
            
            if (!processedMembershipIds.contains(mId) && paidAmount > 0) {
              final pDate = DateTime.tryParse(mship['start_date'] ?? '') ?? DateTime.now();
              final formattedDate = DateFormat('dd MMM yyyy').format(pDate);
              final amtStr = '₹${paidAmount.toStringAsFixed(0)}';
              final dedupKey = '${pDate.year}-${pDate.month}-${pDate.day}_${paidAmount.toStringAsFixed(0)}';

              if (!seenPaymentKeys.contains(dedupKey) && !seenPaymentKeys.contains(mId)) {
                seenPaymentKeys.add(dedupKey);
                seenPaymentKeys.add(mId);
                final invoiceNum = 'INV-${pDate.year}-${mId.replaceAll('-', '').substring(0, 4).toUpperCase()}';
                final statusStr = mship['payment_status']?.toString() ?? 'Paid';
                _paymentHistory.add({
                  'invoice': invoiceNum,
                  'date': formattedDate,
                  'amount': amtStr,
                  'status': statusStr == 'Fully Paid' ? 'Paid' : statusStr,
                  'raw_date': pDate,
                });
              }
            }
          }
        }

        // Sort payments descending by date
        _paymentHistory.sort((a, b) {
          final da = a['raw_date'] as DateTime? ?? DateTime(2000);
          final db = b['raw_date'] as DateTime? ?? DateTime(2000);
          return db.compareTo(da);
        });

        // Fetch workout logs for the last 30 days and clean up old ones
        try {
          final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
          final cutoffDateIso = DateFormat('yyyy-MM-dd').format(thirtyDaysAgo);
          
          // Delete logs older than 30 days from database
          try {
            await SupabaseService.client
                .from('member_workout_logs')
                .delete()
                .eq('member_id', _memberId)
                .lt('date', cutoffDateIso);
          } catch (deleteErr) {
            print('Error purging old workout logs: $deleteErr');
          }

          // Fetch recent logs
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

            // Get assigned workout plan schedule
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

              // Determine muscle group for this day
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
                // Day changed, and they didn't complete it: save it in DB as 'Not Done'!
                try {
                  await SupabaseService.client.from('member_workout_logs').insert({
                    'gym_id': memberData['gym_id'],
                    'member_id': _memberId,
                    'date': pastDateIso,
                    'muscle': muscle,
                    'status': 'Not Done',
                  });
                } catch (_) {}

                newHistory.add({
                  'date': pastDateFormatted,
                  'muscle': muscle,
                  'status': 'Not Done',
                });
              }
            }

            _trainingHistory.clear();
            _trainingHistory.addAll(newHistory);
            await prefs.setString('member_training_history', jsonEncode(_trainingHistory));
          }
        } catch (e) {
          print('Error syncing training history: $e');
        }

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

        // Fetch latest weight and body fat from member_body_logs table
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

        _pendingAmount = (memberData['pending_amount'] as num?)?.toDouble() ?? 0.0;

        // Fetch current week's attendance checklist & streak directly from Supabase RPC
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
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('member_current_streak', _currentStreak);
        } catch (e) {
          print('Error loading member streak from DB: $e');
        }

        // Fetch current month's attendance logs
        try {
          final now = DateTime.now();
          final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();

          final monthLogs = await SupabaseService.client
              .from('attendance_logs')
              .select('check_in, status')
              .eq('user_id', user.id)
              .gte('check_in', startOfMonth);

          final Set<int> attendedDays = {};
          for (var log in monthLogs) {
            final checkInStr = log['check_in'] as String?;
            final status = log['status'] as String?;
            if (checkInStr != null && status != 'Absent' && status != 'Leave' && status != 'On Leave') {
              final checkInDate = DateTime.parse(checkInStr).toLocal();
              if (checkInDate.year == now.year && checkInDate.month == now.month) {
                attendedDays.add(checkInDate.day);
              }
            }
          }
          _attendedDaysOfCurrentMonth = attendedDays.toList();
          _presentDays = _attendedDaysOfCurrentMonth.length;
          await prefs.setString('member_cached_attendance_days', jsonEncode(_attendedDaysOfCurrentMonth));

          // Calculate attendance percentage based on total operational days (excluding Sundays) in current month
          int totalGymDays = 0;
          final lastDay = DateTime(now.year, now.month + 1, 0).day;
          for (int i = 1; i <= lastDay; i++) {
            if (DateTime(now.year, now.month, i).weekday != DateTime.sunday) {
              totalGymDays++;
            }
          }
          _attendancePercentage = totalGymDays > 0 ? ((_presentDays / totalGymDays) * 100).round() : 0;
        } catch (e) {
          print('Error loading month attendance logs: $e');
        }

        // Fetch gamification profile
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
            
            // Map achievements/badges from DB
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

              // Sort achievements: Unlocked badges FIRST, Locked badges SECOND
              _achievements.sort((a, b) {
                final aUnlocked = a['unlocked'] == true ? 0 : 1;
                final bUnlocked = b['unlocked'] == true ? 0 : 1;
                return aUnlocked.compareTo(bUnlocked);
              });
            }
          }
        } catch (e) {
          print('Error loading gamification profile: $e');
        }

        // Fetch declared holidays from public.holidays for gym
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
            await prefs.setStringList('member_declared_holidays', _declaredHolidays);
          }
        } catch (e) {
          print('Error loading declared holidays: $e');
        }

        // Fetch today's daily wellness logs (water, calories, protein)
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
            // First time today: reset daily counters and try inserting a row on database
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

          await prefs.setDouble('member_cached_water_intake', _waterIntake);
          await prefs.setDouble('member_cached_water_goal', _waterGoal);
          await prefs.setInt('member_cached_calories_intake', _caloriesIntake);
          await prefs.setInt('member_cached_calories_goal', _caloriesGoal);
          await prefs.setInt('member_cached_protein_intake', _proteinIntake);
          await prefs.setInt('member_cached_protein_goal', _proteinGoal);
        } catch (e) {
          print('Error loading member daily logs: $e');
        }

        // Fetch attendance logs for member
        try {
          final attendanceData = await SupabaseService.client
              .from('attendance_logs')
              .select('date, check_in, check_out, status')
              .eq('member_id', _memberId)
              .order('date', ascending: false)
              .limit(50);

          if (attendanceData != null) {
            _attendanceHistory.clear();
            _presentDays = 0;
            _absentDays = 0;
            _lateDays = 0;
            _attendedDaysOfCurrentMonth.clear();
            
            final now = DateTime.now();

            for (var row in attendanceData) {
              final status = row['status']?.toString() ?? 'Present';
              if (status == 'Present') _presentDays++;
              if (status == 'Absent') _absentDays++;
              if (status == 'Late') _lateDays++;

              final rawDateStr = row['date']?.toString() ?? '';
              DateTime? parsedDate;
              if (rawDateStr.isNotEmpty) {
                try {
                  parsedDate = DateTime.parse(rawDateStr);
                } catch (_) {}
              }

              if (parsedDate != null && parsedDate.month == now.month && parsedDate.year == now.year) {
                if (status == 'Present' || status == 'Late') {
                  _attendedDaysOfCurrentMonth.add(parsedDate.day);
                }
              }

              String displayDate = 'Unknown Date';
              if (parsedDate != null) {
                displayDate = DateFormat('dd MMM yyyy').format(parsedDate);
              }

              String checkInTime = '—';
              final rawCheckIn = row['check_in']?.toString() ?? '';
              if (rawCheckIn.isNotEmpty) {
                try {
                  checkInTime = DateFormat('hh:mm a').format(DateTime.parse(rawCheckIn));
                } catch (_) {
                  checkInTime = rawCheckIn;
                }
              }

              String checkOutTime = '—';
              final rawCheckOut = row['check_out']?.toString() ?? '';
              if (rawCheckOut.isNotEmpty) {
                try {
                  checkOutTime = DateFormat('hh:mm a').format(DateTime.parse(rawCheckOut));
                } catch (_) {
                  checkOutTime = rawCheckOut;
                }
              }

              _attendanceHistory.add({
                'date': displayDate,
                'checkIn': checkInTime,
                'checkOut': checkOutTime,
                'status': status,
              });
            }
            
            await prefs.setString('member_cached_attendance_history', jsonEncode(_attendanceHistory));
            await prefs.setInt('member_cached_present_days', _presentDays);
            await prefs.setInt('member_cached_absent_days', _absentDays);
            await prefs.setInt('member_cached_late_days', _lateDays);
            await prefs.setStringList('member_cached_attended_days_curr_month', _attendedDaysOfCurrentMonth.map((e) => e.toString()).toList());
          }
        } catch (e) {
          print('Error loading member attendance logs: $e');
        }

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
                    notifyListeners();
                  }
                },
              );
          _memberSubscription?.subscribe();
        } catch (e) {
          print('Error setting up Realtime member subscription: $e');
        }

        _isMemberCodeVerified = true;
        _isLoggedIn = true;

        notifyListeners();
      } else {
        clearAllDataInMemory();
      }
    } catch (e) {
      print('loadMemberDataFromSupabase error: $e');
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
    await prefs.remove('member_cached_today_muscle');
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
    _todayMuscleGroup = 'Rest Day';
    _isTrainingCompleted = false;
    _membershipPlan = '';
    _membershipStatus = 'Inactive';
    _membershipStartDate = '';
    _membershipEndDate = '';
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
    _checkInTime = '';
    _checkInDate = '';
    _checkedInToday = false;

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
          _checkedInToday = true;
          _checkInTime = result['check_in'] ?? DateFormat('hh:mm a').format(now);
          _checkInDate = result['attendance_date'] ?? DateFormat('dd MMM yyyy').format(now);
          if (result['already_marked'] != true) {
            _currentStreak += 1;
            _currentXP += 250;
          }
          if (!_attendedDaysOfCurrentMonth.contains(now.day)) {
            _attendedDaysOfCurrentMonth.add(now.day);
            _presentDays = _attendedDaysOfCurrentMonth.length;
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('member_checked_in_today', true);
          await prefs.setString('member_check_in_time', _checkInTime);
          await prefs.setString('member_check_in_date', _checkInDate);
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
