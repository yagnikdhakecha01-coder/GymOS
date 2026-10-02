import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  static const String keyActiveAssociationId = 'gymos_active_association_id';
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

  // Save/Get active association ID
  String? getActiveAssociationId() => _prefs.getString(keyActiveAssociationId);
  Future<bool> setActiveAssociationId(String id) =>
      _prefs.setString(keyActiveAssociationId, id);

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

  // Initialize clean data defaults without mock personal data
  Future<void> _initDemoData({bool force = false}) async {
    final bool hasNewDb = _prefs.getBool('gymos_db_version_v5') ?? false;
    if (!force && hasNewDb) {
      return; // Already initialized
    }

    // Default Gym Info
    await setGymInfo({
      'name': 'My Gym',
      'owner': '',
      'email': '',
      'country': '',
      'phone': '',
      'logo': '',
      'plan': 'Trial Plan',
      'validUntil': '',
      'attendanceMethod': 'QR Code',
      'categories': ['Weight Loss', 'Weight Gain', 'Fitness / General'],
    });

    // Clean slate by default
    await _prefs.setString(keyMemberships, jsonEncode([]));
    await _prefs.setString(keyWorkouts, jsonEncode([]));
    await _prefs.setString(keyDiets, jsonEncode([]));
    await _prefs.setString(keyMembers, jsonEncode([]));
    await _prefs.setString(keyStaff, jsonEncode([]));
    await _prefs.setString(keyTransactions, jsonEncode([]));
    await _prefs.setString(keyAttendance, jsonEncode([]));
    await _prefs.setBool('gymos_db_version_v5', true);
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
    debugPrint('Executing Local DB Schema Migration: Version ${targetVersion - 1} -> Version $targetVersion');
    // Future versioned migrations go here
  }
}
