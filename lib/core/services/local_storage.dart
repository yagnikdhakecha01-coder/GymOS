import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String keyMembers = 'gymos_members';
  static const String keyStaff = 'gymos_staff';
  static const String keyWorkouts = 'gymos_workouts';
  static const String keyDiets = 'gymos_diets';
  static const String keyMemberships = 'gymos_memberships';
  static const String keyTransactions = 'gymos_transactions';
  static const String keyAttendance = 'gymos_attendance';
  static const String keyUserRole = 'gymos_user_role';
  static const String keyUserGymInfo = 'gymos_gym_info';
  static const String keyIsLoggedIn = 'gymos_is_logged_in';
  static const String keyTrialMembers = 'gymos_trial_members';
  static const String keyAttendanceQueue = 'gymos_attendance_queue';
  static const String keyCrudQueue = 'gymos_crud_queue';
  static const String keyAttendanceSettings = 'gymos_attendance_settings';
  static const String keyGymShifts = 'gymos_gym_shifts';
  static const String keySalaryAdvances = 'gymos_salary_advances';
  static const String keySalaryDrafts = 'gymos_salary_drafts';
  static const String keyLeaveRequests = 'gymos_leave_requests';
  static const String keyGymShiftSettings = 'gymos_gym_shift_settings';
  static const String keyGymShiftsList = 'gymos_gym_shifts_list';
  static const String keyInitialSyncComplete = 'gymos_initial_sync_complete';
  static const String keyLastSuccessfulSync = 'gymos_last_successful_sync';
  static const String keyAchievements = 'gymos_achievements';
  static const String keyGamificationProfile = 'gymos_gamification_profile';
  static const String keyGoals = 'gymos_fitness_goals_all';
  static const String keyCustomFields = 'gymos_custom_fields_all';
  static const String keyRecentActivities = 'gymos_recent_activities_all';
  static const String keyDisplaySessions = 'gymos_display_sessions_all';
  static const String keyCorrections = 'gymos_attendance_corrections_all';
  static const String keyAlerts = 'gymos_attendance_alerts_all';
  static const String keyManualAttendanceQueue = 'gymos_manual_attendance_queue';
  static const String keyAttendanceAuditLog = 'gymos_attendance_audit_log';
  static const String keyOfflineMemberCache = 'gymos_offline_member_cache';
  static const String keyOfflineStaffCache = 'gymos_offline_staff_cache';

  static LocalStorageService? _instance;
  static LocalStorageService? get instance => _instance;

  final SharedPreferences _prefs;

  LocalStorageService(this._prefs) {
    _instance = this;
    _initDemoData().then((_) {
      SchemaMigrationManager.checkAndMigrate(this);
    });
  }

  // Helper method to clear all data
  Future<void> clearAll() async {
    await _prefs.clear();
    await _initDemoData(force: true);
  }

  // Get raw JSON string
  String? getString(String key) => _prefs.getString(key);

  // Set raw JSON string
  Future<bool> setString(String key, String value) => _prefs.setString(key, value);

  // Checks if key exists
  bool hasKey(String key) => _prefs.containsKey(key);

  // Get/Set int
  int? getInt(String key) => _prefs.getInt(key);
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  // Get/Set bool
  bool? getBool(String key) => _prefs.getBool(key);
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  // Remove key
  Future<bool> remove(String key) => _prefs.remove(key);

  // Save/Get Login status
  bool isLoggedIn() => _prefs.getBool(keyIsLoggedIn) ?? false;
  Future<bool> setLoggedIn(bool value) => _prefs.setBool(keyIsLoggedIn, value);

  // Save/Get role
  String? getUserRole() => _prefs.getString(keyUserRole);
  Future<bool> setUserRole(String role) => _prefs.setString(keyUserRole, role);

  // Save/Get gym details
  Map<String, dynamic>? getGymInfo() {
    final data = _prefs.getString(keyUserGymInfo);
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }
  Future<bool> setGymInfo(Map<String, dynamic> info) =>
      _prefs.setString(keyUserGymInfo, jsonEncode(info));

  // Cache base64 images
  String? getCachedImage(String key) => _prefs.getString('cached_img_$key');
  Future<bool> setCachedImage(String key, String base64Data) =>
      _prefs.setString('cached_img_$key', base64Data);

  // Custom branding helpers
  bool getBrandingEnabled() => _prefs.getBool('gymos_branding_enabled') ?? false;
  Future<bool> setBrandingEnabled(bool value) => _prefs.setBool('gymos_branding_enabled', value);

  String? getBrandingName() => _prefs.getString('gymos_branding_name');
  Future<bool> setBrandingName(String name) => _prefs.setString('gymos_branding_name', name);

  String? getBrandingLogoUrl() => _prefs.getString('gymos_branding_logo_url');
  Future<bool> setBrandingLogoUrl(String url) => _prefs.setString('gymos_branding_logo_url', url);

  // Initialize beautiful, production-quality dummy data
  Future<void> _initDemoData({bool force = false}) async {
    final bool hasNewDb = _prefs.getBool('gymos_db_version_v5') ?? false;
    if (!force && hasNewDb) {
      return; // Already initialized
    }

    // Default Gym Info
    await setGymInfo({
      'name': 'GYMOS',
      'owner': 'Jigar Gamer',
      'email': 'jigarnaliyadhara10@gmail.com',
      'country': 'India',
      'phone': '+91 98765 43210',
      'logo': '',
      'plan': 'Premium Plan',
      'validUntil': '25 May 2025',
      'attendanceMethod': 'QR Code',
      'categories': ['Weight Loss', 'Weight Gain', 'Fitness / General'],
    });

    // Default Membership Plans (Clean slate by default)
    await _prefs.setString(keyMemberships, jsonEncode([]));
    await _prefs.setString(keyWorkouts, jsonEncode([]));
    await _prefs.setString(keyDiets, jsonEncode([]));
    await _prefs.setString(keyMembers, jsonEncode([]));
    await _prefs.setString(keyStaff, jsonEncode([]));
    await _prefs.setString(keyTransactions, jsonEncode([]));
    await _prefs.setString(keyAttendance, jsonEncode([]));
    await _prefs.setBool('gymos_db_version_v5', true);
    return;
    final defaultWorkouts = [
      {
        'id': 'w_1',
        'title': 'Fat Burn Plan',
        'goal': 'Weight Loss',
        'difficulty': 'Intermediate',
        'durationWeeks': 4,
        'exercisesCount': 12,
        'durationMinutes': 45,
        'exercises': [
          {'name': 'Jumping Jacks', 'sets': 4, 'reps': '30 sec', 'restSeconds': 15},
          {'name': 'Bodyweight Squats', 'sets': 4, 'reps': '15 reps', 'restSeconds': 30},
          {'name': 'Pushups', 'sets': 3, 'reps': '12 reps', 'restSeconds': 30},
          {'name': 'Mountain Climbers', 'sets': 3, 'reps': '20 reps', 'restSeconds': 20},
          {'name': 'Plank Hold', 'sets': 3, 'reps': '45 sec', 'restSeconds': 30},
        ]
      },
      {
        'id': 'w_2',
        'title': 'Muscle Gain Plan',
        'goal': 'Weight Gain',
        'difficulty': 'Advanced',
        'durationWeeks': 8,
        'exercisesCount': 16,
        'durationMinutes': 75,
        'exercises': [
          {'name': 'Barbell Bench Press', 'sets': 4, 'reps': '8-10 reps', 'restSeconds': 90},
          {'name': 'Incline Dumbbell Press', 'sets': 4, 'reps': '10 reps', 'restSeconds': 60},
          {'name': 'Barbell Squat', 'sets': 4, 'reps': '8 reps', 'restSeconds': 95},
          {'name': 'Deadlift', 'sets': 4, 'reps': '5 reps', 'restSeconds': 120},
          {'name': 'Lat Pulldown', 'sets': 4, 'reps': '10-12 reps', 'restSeconds': 60},
        ]
      },
      {
        'id': 'w_3',
        'title': 'Full Body Fitness',
        'goal': 'Fitness',
        'difficulty': 'Beginner',
        'durationWeeks': 4,
        'exercisesCount': 10,
        'durationMinutes': 45,
        'exercises': [
          {'name': 'Dumbbell Goblet Squats', 'sets': 3, 'reps': '12 reps', 'restSeconds': 45},
          {'name': 'Dumbbell Shoulder Press', 'sets': 3, 'reps': '10 reps', 'restSeconds': 45},
          {'name': 'Dumbbell Rows', 'sets': 3, 'reps': '12 reps', 'restSeconds': 45},
          {'name': 'Glute Bridges', 'sets': 3, 'reps': '15 reps', 'restSeconds': 30},
          {'name': 'Abdominal Crunches', 'sets': 3, 'reps': '15 reps', 'restSeconds': 30},
        ]
      },
      {
        'id': 'w_4',
        'title': 'Lean & Strong',
        'goal': 'Weight Loss',
        'difficulty': 'Intermediate',
        'durationWeeks': 6,
        'exercisesCount': 14,
        'durationMinutes': 60,
        'exercises': [
          {'name': 'Kettlebell Swings', 'sets': 4, 'reps': '15 reps', 'restSeconds': 30},
          {'name': 'Push Press', 'sets': 4, 'reps': '10 reps', 'restSeconds': 45},
          {'name': 'Pullups', 'sets': 3, 'reps': 'Max reps', 'restSeconds': 60},
          {'name': 'Walking Lunges', 'sets': 3, 'reps': '20 steps', 'restSeconds': 45},
        ]
      }
    ];
    await _prefs.setString(keyWorkouts, jsonEncode(defaultWorkouts));

    // Default Diet Plans
    final defaultDiets = [
      {
        'id': 'd_1',
        'title': 'Fat Loss Diet',
        'goal': 'Weight Loss',
        'calories': 1400,
        'meals': [
          {'name': 'Breakfast', 'items': 'Oats with berries & 3 egg whites', 'time': '08:00 AM'},
          {'name': 'Lunch', 'items': 'Grilled chicken breast (150g) with broccoli & brown rice', 'time': '01:30 PM'},
          {'name': 'Snack', 'items': 'Whey protein shake & a handful of almonds', 'time': '05:00 PM'},
          {'name': 'Dinner', 'items': 'Baked salmon (120g) with leafy green salad', 'time': '08:30 PM'},
        ],
        'notes': 'Avoid sugar, drink at least 4 liters of water daily.',
      },
      {
        'id': 'd_2',
        'title': 'Mass Gain Diet',
        'goal': 'Weight Gain',
        'calories': 2800,
        'meals': [
          {'name': 'Breakfast', 'items': '4 whole eggs, 2 slices of whole wheat toast, 1 banana & peanut butter', 'time': '07:30 AM'},
          {'name': 'Lunch', 'items': 'Lean beef chunks (200g) with white rice & sweet potato', 'time': '01:00 PM'},
          {'name': 'Snack', 'items': 'Gainer shake with oats, peanut butter, milk, and banana', 'time': '04:30 PM'},
          {'name': 'Dinner', 'items': 'Grilled chicken breast (200g) with whole wheat pasta & avocado', 'time': '09:00 PM'},
        ],
        'notes': 'High protein, high carb intake. Eat every 3 hours.',
      },
      {
        'id': 'd_3',
        'title': 'Maintenance Diet',
        'goal': 'Fitness',
        'calories': 2000,
        'meals': [
          {'name': 'Breakfast', 'items': 'Muesli with Greek yogurt & chia seeds', 'time': '08:00 AM'},
          {'name': 'Lunch', 'items': 'Paneer/Tofu bhurji (150g) with 2 multigrain rotis & mixed salad', 'time': '01:30 PM'},
          {'name': 'Snack', 'items': 'Sprouted moong salad & green tea', 'time': '05:30 PM'},
          {'name': 'Dinner', 'items': 'Mixed lentil soup with roasted vegetables & quinoa', 'time': '08:30 PM'},
        ],
        'notes': 'Balanced macronutrient diet for general health.',
      }
    ];
    await _prefs.setString(keyDiets, jsonEncode(defaultDiets));

    // Default Members
    final defaultMembers = [
      {
        'id': 'mem_1',
        'name': 'Rahul Sharma',
        'email': 'rahul.sharma@gmail.com',
        'phone': '+91 98765 11111',
        'avatar': '',
        'joinDate': '12 Jan 2026',
        'status': 'Active',
        'membershipPlanId': 'm_plan_3', // Premium Half-Yearly
        'ptMember': true,
        'ptTrainer': 'STF001', // Assigned to Rahul Trainer
        'assignedWorkoutId': 'w_2',
        'assignedDietId': 'd_2',
        'medicalDetails': 'Slight lower back sensitivity',
        'notes': 'Aims to gain 10kg muscle in 6 months.',
        'pendingAmount': 0.0,
      },
      {
        'id': 'mem_2',
        'name': 'Pooja Patel',
        'email': 'pooja.patel@gmail.com',
        'phone': '+91 98765 22222',
        'avatar': '',
        'joinDate': '01 Feb 2026',
        'status': 'Active',
        'membershipPlanId': 'm_plan_2', // Quarterly Growth
        'ptMember': false,
        'ptTrainer': '',
        'assignedWorkoutId': 'w_1',
        'assignedDietId': 'd_1',
        'medicalDetails': 'None',
        'notes': 'Wants to reduce weight for a wedding event.',
        'pendingAmount': 1500.0,
      },
      {
        'id': 'mem_3',
        'name': 'Vivek Singh',
        'email': 'vivek.singh@gmail.com',
        'phone': '+91 98765 33333',
        'avatar': '',
        'joinDate': '10 May 2026',
        'status': 'Active',
        'membershipPlanId': 'm_plan_1', // Monthly Starter
        'ptMember': false,
        'ptTrainer': '',
        'assignedWorkoutId': 'w_3',
        'assignedDietId': 'd_3',
        'medicalDetails': 'Asthma (keeps inhaler)',
        'notes': 'Focusing on cardio and breathing exercises.',
        'pendingAmount': 0.0,
      },
      {
        'id': 'mem_4',
        'name': 'Neha Joshi',
        'email': 'neha.joshi@gmail.com',
        'phone': '+91 98765 44444',
        'avatar': '',
        'joinDate': '25 May 2026',
        'status': 'Active',
        'membershipPlanId': 'm_plan_4', // Elite Annual VIP
        'ptMember': true,
        'ptTrainer': 'STF003',
        'assignedWorkoutId': 'w_4',
        'assignedDietId': 'd_1',
        'medicalDetails': 'Knee injury 2 years ago',
        'notes': 'Strength training with emphasis on joint recovery.',
        'pendingAmount': 2000.0,
      },
      {
        'id': 'mem_5',
        'name': 'Amit Verma',
        'email': 'amit.verma@gmail.com',
        'phone': '+91 98765 55555',
        'avatar': '',
        'joinDate': '15 Jun 2026',
        'status': 'Inactive',
        'membershipPlanId': 'm_plan_1',
        'ptMember': false,
        'ptTrainer': '',
        'assignedWorkoutId': 'w_3',
        'assignedDietId': 'd_3',
        'medicalDetails': 'None',
        'notes': 'Out of town for 2 months.',
        'pendingAmount': 0.0,
      }
    ];
    await _prefs.setString(keyMembers, jsonEncode(defaultMembers));

    // Default Staff
    final defaultStaff = [
      {
        'id': 'STF001',
        'name': 'Rahul Sharma',
        'email': 'rahul.sharma@fitzone.com',
        'phone': '+91 98765 43210',
        'role': 'Trainer',
        'department': 'Training',
        'status': 'Active',
        'joinDate': '12 Jan 2024',
        'shift': '6:00 AM - 2:00 PM',
        'reportingTo': 'Amit Patel (Manager)',
        'experience': '3 Years',
        'rating': 4.2,
        'sessionsCount': 128,
        'membersTrained': 56,
        'salary': 35000.0,
        'salaryDue': 0.0,
      },
      {
        'id': 'STF002',
        'name': 'Priya Patel',
        'email': 'priya.patel@fitzone.com',
        'phone': '+91 98765 43211',
        'role': 'Receptionist',
        'department': 'Admin',
        'status': 'Active',
        'joinDate': '20 Mar 2024',
        'shift': '9:00 AM - 5:00 PM',
        'reportingTo': 'Amit Patel (Manager)',
        'experience': '1 Year',
        'rating': 4.5,
        'sessionsCount': 0,
        'membersTrained': 0,
        'salary': 18000.0,
        'salaryDue': 18000.0,
      },
      {
        'id': 'STF003',
        'name': 'Vivek Singh',
        'email': 'vivek.singh@fitzone.com',
        'phone': '+91 98765 43212',
        'role': 'Trainer',
        'department': 'Training',
        'status': 'Active',
        'joinDate': '15 Nov 2024',
        'shift': '2:00 PM - 10:00 PM',
        'reportingTo': 'Amit Patel (Manager)',
        'experience': '5 Years',
        'rating': 4.8,
        'sessionsCount': 240,
        'membersTrained': 78,
        'salary': 40000.0,
        'salaryDue': 0.0,
      },
      {
        'id': 'STF004',
        'name': 'Neha Joshi',
        'email': 'neha.joshi@fitzone.com',
        'phone': '+91 98765 43213',
        'role': 'Dietitian',
        'department': 'Nutrition',
        'status': 'On Leave',
        'joinDate': '01 Jan 2025',
        'shift': '10:00 AM - 6:00 PM',
        'reportingTo': 'Amit Patel (Manager)',
        'experience': '4 Years',
        'rating': 4.6,
        'sessionsCount': 90,
        'membersTrained': 42,
        'salary': 30000.0,
        'salaryDue': 30000.0,
      },
      {
        'id': 'STF005',
        'name': 'Amit Verma',
        'email': 'amit.verma@fitzone.com',
        'phone': '+91 98765 43214',
        'role': 'Accountant',
        'department': 'Finance',
        'status': 'Active',
        'joinDate': '10 Apr 2024',
        'shift': '9:00 AM - 5:00 PM',
        'reportingTo': 'Amit Patel (Manager)',
        'experience': '6 Years',
        'rating': 4.9,
        'sessionsCount': 0,
        'membersTrained': 0,
        'salary': 32000.0,
        'salaryDue': 0.0,
      }
    ];
    await _prefs.setString(keyStaff, jsonEncode(defaultStaff));

    // Default Finance Transactions
    final defaultTransactions = [
      {
        'id': 'tx_1',
        'title': 'Rahul Sharma - Membership Renewal',
        'amount': 7500.0,
        'type': 'Revenue',
        'category': 'Membership',
        'date': '15 Jul 2026',
        'notes': '6 months Premium plan renewal',
      },
      {
        'id': 'tx_2',
        'title': 'Vivek Singh - Membership Renewal',
        'amount': 1500.0,
        'type': 'Revenue',
        'category': 'Membership',
        'date': '14 Jul 2026',
        'notes': 'Monthly starter plan',
      },
      {
        'id': 'tx_3',
        'title': 'Priya Patel - Monthly Salary',
        'amount': 18000.0,
        'type': 'Expense',
        'category': 'Salary',
        'date': '05 Jul 2026',
        'notes': 'June month salary',
      },
      {
        'id': 'tx_4',
        'title': 'Rent & Maintenance',
        'amount': 45000.0,
        'type': 'Expense',
        'category': 'Rent',
        'date': '02 Jul 2026',
        'notes': 'Gym space monthly rent',
      },
      {
        'id': 'tx_5',
        'title': 'Pooja Patel - Part Membership Fee',
        'amount': 2500.0,
        'type': 'Revenue',
        'category': 'Membership',
        'date': '29 Jun 2026',
        'notes': 'Quarterly plan installment',
      },
      {
        'id': 'tx_6',
        'title': 'Electricity & Utility Bills',
        'amount': 12000.0,
        'type': 'Expense',
        'category': 'Utilities',
        'date': '28 Jun 2026',
        'notes': 'Summer air conditioning electricity bill',
      }
    ];
    await _prefs.setString(keyTransactions, jsonEncode(defaultTransactions));

    // Default Attendance
    final defaultAttendance = [
      {
        'id': 'att_1',
        'userId': 'mem_1',
        'userName': 'Rahul Sharma',
        'userType': 'Member',
        'checkInTime': '16-07-2026 06:15 AM',
        'checkOutTime': '16-07-2026 07:45 AM',
        'date': '16-07-2026',
        'status': 'Present',
      },
      {
        'id': 'att_2',
        'userId': 'mem_2',
        'userName': 'Pooja Patel',
        'userType': 'Member',
        'checkInTime': '16-07-2026 07:05 AM',
        'checkOutTime': null,
        'date': '16-07-2026',
        'status': 'Present',
      },
      {
        'id': 'att_3',
        'userId': 'STF001',
        'userName': 'Rahul Sharma (Trainer)',
        'userType': 'Staff',
        'checkInTime': '16-07-2026 05:55 AM',
        'checkOutTime': null,
        'date': '16-07-2026',
        'status': 'Present',
      },
      {
        'id': 'att_4',
        'userId': 'STF005',
        'userName': 'Amit Verma',
        'userType': 'Staff',
        'checkInTime': '16-07-2026 08:58 AM',
        'checkOutTime': null,
        'date': '16-07-2026',
        'status': 'Late',
      }
    ];
    await _prefs.setString(keyAttendance, jsonEncode(defaultAttendance));
  }
}

class SchemaMigrationManager {
  static const String keyDbVersion = 'local_db_version';
  static const int currentVersion = 1;

  static Future<void> checkAndMigrate(LocalStorageService storage) async {
    final int oldVersion = storage.getInt(keyDbVersion) ?? 1;
    if (oldVersion < currentVersion) {
      for (int version = oldVersion + 1; version <= currentVersion; version++) {
        await _runMigrationStep(storage, version);
      }
      await storage.setInt(keyDbVersion, currentVersion);
    } else if (!storage.hasKey(keyDbVersion)) {
      await storage.setInt(keyDbVersion, currentVersion);
    }
  }

  static Future<void> _runMigrationStep(LocalStorageService storage, int targetVersion) async {
    print('Executing Local DB Schema Migration: Version ${targetVersion - 1} -> Version $targetVersion');
    // Future versioned migrations go here
  }
}
