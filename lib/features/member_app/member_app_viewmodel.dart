import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';

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
  String _gymName = 'FitZone Gym';
  String _memberAvatar = 'assets/images/member/avatar_default.png';
  int _notificationCount = 0;

  // Body Stats & Fitness Goals
  String _weight = '76 kg';
  String _height = '178 cm';
  String _bodyFat = '14.5%';
  String _fitnessGoal = 'Lean Muscle Gain';

  // ── Streak Data ──
  int _currentStreak = 0;
  int _lastStreak = 0;
  List<bool> _weekAttendance = [false, false, false, false, false, false, false];
  List<String> _weekDays = ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon'];
  List<int> _weekDates = [22, 23, 24, 25, 26, 27, 28];

  // ── Statistics ──
  int _attendancePercentage = 0;
  int _membershipDaysLeft = 0;
  int _ptSessionsLeft = 0;
  double _pendingAmount = 0.0;

  // ── Today's Training ──
  String _todayMuscleGroup = 'Chest Day'; // Chest, Back, Leg, Shoulder, Arm, Rest, Cardio
  bool _isTrainingCompleted = false;

  // Training History Mock
  final List<Map<String, dynamic>> _trainingHistory = [
    {'date': '16 May 2026', 'muscle': 'Back Day', 'status': 'Completed'},
    {'date': '15 May 2026', 'muscle': 'Leg Day', 'status': 'Completed'},
    {'date': '14 May 2026', 'muscle': 'Shoulder Day', 'status': 'Completed'},
    {'date': '13 May 2026', 'muscle': 'Arm Day', 'status': 'Completed'},
    {'date': '12 May 2026', 'muscle': 'Rest Day', 'status': 'Completed'},
  ];

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

  // Payment History Mock
  final List<Map<String, dynamic>> _paymentHistory = [
    {'invoice': 'INV-2026-004', 'date': '01 Jan 2026', 'amount': '₹12,000', 'status': 'Paid'},
    {'invoice': 'INV-2025-012', 'date': '01 Jul 2025', 'amount': '₹12,000', 'status': 'Paid'},
  ];

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

  MemberAppViewModel() {
    _generateCurrentWeek();
    _currentQuote = _quotes[Random().nextInt(_quotes.length)];
    _loadPersistedState();
    if (SupabaseService.isInitialized) {
      _authStateSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        final session = data.session;
        if (event == AuthChangeEvent.signedOut || session == null) {
          clearAllDataInMemory();
        } else if (event == AuthChangeEvent.signedIn) {
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

  String get assignedWorkoutId => _assignedWorkoutId;
  String get assignedDietId => _assignedDietId;
  String get assignedWorkoutTitle => _assignedWorkoutTitle;
  String get assignedDietTitle => _assignedDietTitle;

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
  int get ptSessionsLeft => _ptSessionsLeft;
  double get pendingAmount => _pendingAmount;

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
  }

  void addCalories(int amount) {
    _caloriesIntake = min(_caloriesGoal, _caloriesIntake + amount);
    notifyListeners();
  }

  void addProtein(int amount) {
    _proteinIntake = min(_proteinGoal, _proteinIntake + amount);
    notifyListeners();
  }

  // ── Persistence ──
  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    _isMemberCodeVerified = prefs.getBool('member_code_verified') ?? false;
    _isLoggedIn = prefs.getBool('member_logged_in') ?? false;
    _checkedInToday = prefs.getBool('member_checked_in_today') ?? false;
    if (_checkedInToday) {
      _checkInTime = prefs.getString('member_check_in_time') ?? '07:32 AM';
      _checkInDate = prefs.getString('member_check_in_date') ?? '15 May 2026';
    }
    _generateCurrentWeek();
    await loadMemberDataFromSupabase();
    notifyListeners();
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
    try {
      if (SupabaseService.client == null) return;
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
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
              final rawSchedule = wData['schedule'] as Map<String, dynamic>? ?? {};
              final todayName = DateFormat('EEEE').format(DateTime.now()); // e.g. 'Monday'
              final todayList = rawSchedule[todayName] as List?;
              if (todayList != null && todayList.isNotEmpty) {
                final firstVal = todayList.first as Map<String, dynamic>?;
                _todayMuscleGroup = firstVal?['title'] ?? 'Rest Day';
              } else {
                _todayMuscleGroup = 'Rest Day';
              }
            } else {
              _assignedWorkoutTitle = '';
              _todayMuscleGroup = 'Rest Day';
            }
          } catch (_) {
            _assignedWorkoutTitle = '';
            _todayMuscleGroup = 'Rest Day';
          }
        } else {
          _assignedWorkoutTitle = '';
          _todayMuscleGroup = 'Rest Day';
        }

        if (_assignedDietId.isNotEmpty) {
          try {
            final dData = await SupabaseService.client
                .from('diet_plans')
                .select('title')
                .eq('id', _assignedDietId)
                .maybeSingle();
            _assignedDietTitle = dData?['title'] ?? '';
          } catch (_) {
            _assignedDietTitle = '';
          }
        } else {
          _assignedDietTitle = '';
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

        // Keep local storage synchronized for roles and gym ID so GymRepository works correctly
        final prefs = await SharedPreferences.getInstance();
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
            
            _membershipStartDate = membershipData['start_date'] ?? _membershipStartDate;
            _membershipEndDate = membershipData['end_date'] ?? _membershipEndDate;
            
            final totalAmount = membershipData['total_amount'] ?? 0;
            _amountPaid = '₹$totalAmount';
            
            try {
              final endDate = DateTime.parse(_membershipEndDate);
              final today = DateTime.now();
              final difference = DateTime(endDate.year, endDate.month, endDate.day)
                  .difference(DateTime(today.year, today.month, today.day))
                  .inDays;
              _membershipDaysLeft = difference > 0 ? difference : 0;
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

        final extra = memberData['extra_fields'] as Map<String, dynamic>? ?? {};
        _weight = extra['weight'] ?? _weight;
        _height = extra['height'] ?? _height;
        _bodyFat = extra['body_fat'] ?? extra['bodyFat'] ?? _bodyFat;
        _fitnessGoal = extra['fitness_goal'] ?? extra['fitnessGoal'] ?? _fitnessGoal;

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
            }
          }
        } catch (e) {
          print('Error loading gamification profile: $e');
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

  Future<void> logout() async {
    clearAllDataInMemory();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
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
    _ptSessionsLeft = 0;
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
  Future<Map<String, dynamic>> markCheckIn([String? qrToken]) async {
    final tokenToUse = qrToken ?? 'static_default_token';
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
