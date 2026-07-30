import 'package:flutter/material.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/attendance.dart';
import '../../core/models/attendance_settings.dart';
import '../../core/models/display_session.dart';
import '../../core/services/supabase_service.dart';
import 'package:intl/intl.dart';
import '../../core/models/attendance_alert.dart';
import '../../core/models/attendance_correction.dart';

class AttendanceViewModel extends ChangeNotifier {
  final GymRepository _repository;

  bool _isManualAttendanceEnabled = false;
  String _currentConnectedSSID = "FitZone_Gym_5G";

  AttendanceViewModel(this._repository) {
    _repository.addListener(notifyListeners);
    _repository.fetchAttendanceSettingsFromSupabase();
    _repository.fetchAttendanceLogsFromSupabase();
    _repository.fetchDisplaySessionsFromSupabase();
  }

  @override
  void dispose() {
    _repository.removeListener(notifyListeners);
    super.dispose();
  }

  void refresh() {
    _repository.fetchAttendanceSettingsFromSupabase();
    _repository.fetchAttendanceLogsFromSupabase();
    _repository.fetchDisplaySessionsFromSupabase();
    notifyListeners();
  }

  // Getters
  GymAttendanceSettings? get settings => _repository.getAttendanceSettings();
  List<AttendanceDisplaySession> get displaySessions => _repository.getDisplaySessions();
  List<AttendanceAlert> get alerts => _repository.alerts;
  List<AttendanceCorrectionRequest> get corrections => _repository.corrections;
  Map<String, dynamic> get dashboardStats => _repository.dashboardStats;

  String get savedGymWiFiSSID => settings?.wifiSsid ?? "";
  bool get isWiFiVerificationEnabled => settings != null && 
      (settings!.method == 'WiFi Only' || 
       settings!.method == 'QR + WiFi' || 
       settings!.method == 'Static QR + WiFi' ||
       settings!.method == 'Dynamic QR + WiFi');
  bool get isDynamicQrEnabled => settings != null && 
      (settings!.method == 'QR Only' || 
       settings!.method == 'QR + WiFi' ||
       settings!.method == 'Dynamic QR' ||
       settings!.method == 'Dynamic QR + WiFi');
  bool get isManualAttendanceEnabled => _isManualAttendanceEnabled;
  String get lateTimeSetting => settings?.lateTimeSetting ?? "09:05 AM";
  String get currentConnectedSSID => _currentConnectedSSID;

  bool get isGymWiFiConnected {
    if (!isWiFiVerificationEnabled) return true;
    return _currentConnectedSSID == savedGymWiFiSSID;
  }

  List<AttendanceRecord> get attendanceHistory => _repository.getAttendance();

  List<AttendanceRecord> get todayRecords {
    final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());
    return _repository.getAttendance().where((r) => r.date == todayStr).toList();
  }

  // Setters
  Future<void> updateWiFiSettings(String ssid, String bssid) async {
    if (settings != null) {
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: settings!.isEnabled,
        method: settings!.method,
        qrValiditySeconds: settings!.qrValiditySeconds,
        wifiSsid: ssid,
        wifiBssid: bssid,
        staticQrToken: settings!.staticQrToken,
        staticQrLocked: settings!.staticQrLocked,
        lateTimeSetting: settings!.lateTimeSetting,
        autoMarkAbsent: settings!.autoMarkAbsent,
        autoCloseShift: settings!.autoCloseShift,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> updateAttendanceMethod(String method) async {
    if (settings != null) {
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: settings!.isEnabled,
        method: method,
        qrValiditySeconds: settings!.qrValiditySeconds,
        wifiSsid: settings!.wifiSsid,
        wifiBssid: settings!.wifiBssid,
        staticQrToken: settings!.staticQrToken,
        staticQrLocked: settings!.staticQrLocked,
        lateTimeSetting: settings!.lateTimeSetting,
        autoMarkAbsent: settings!.autoMarkAbsent,
        autoCloseShift: settings!.autoCloseShift,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> updateQrValiditySeconds(int seconds) async {
    if (settings != null) {
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: settings!.isEnabled,
        method: settings!.method,
        qrValiditySeconds: seconds,
        wifiSsid: settings!.wifiSsid,
        wifiBssid: settings!.wifiBssid,
        staticQrToken: settings!.staticQrToken,
        staticQrLocked: settings!.staticQrLocked,
        lateTimeSetting: settings!.lateTimeSetting,
        autoMarkAbsent: settings!.autoMarkAbsent,
        autoCloseShift: settings!.autoCloseShift,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> toggleAttendanceEnabled(bool enabled) async {
    if (settings != null) {
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: enabled,
        method: settings!.method,
        qrValiditySeconds: settings!.qrValiditySeconds,
        wifiSsid: settings!.wifiSsid,
        wifiBssid: settings!.wifiBssid,
        staticQrToken: settings!.staticQrToken,
        staticQrLocked: settings!.staticQrLocked,
        lateTimeSetting: settings!.lateTimeSetting,
        autoMarkAbsent: settings!.autoMarkAbsent,
        autoCloseShift: settings!.autoCloseShift,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> updateLateTime(String time) async {
    if (settings != null) {
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: settings!.isEnabled,
        method: settings!.method,
        qrValiditySeconds: settings!.qrValiditySeconds,
        wifiSsid: settings!.wifiSsid,
        wifiBssid: settings!.wifiBssid,
        staticQrToken: settings!.staticQrToken,
        staticQrLocked: settings!.staticQrLocked,
        lateTimeSetting: time,
        autoMarkAbsent: settings!.autoMarkAbsent,
        autoCloseShift: settings!.autoCloseShift,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> toggleStaticQrLock(bool locked) async {
    if (settings != null) {
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: settings!.isEnabled,
        method: settings!.method,
        qrValiditySeconds: settings!.qrValiditySeconds,
        wifiSsid: settings!.wifiSsid,
        wifiBssid: settings!.wifiBssid,
        staticQrToken: settings!.staticQrToken,
        staticQrLocked: locked,
        lateTimeSetting: settings!.lateTimeSetting,
        autoMarkAbsent: settings!.autoMarkAbsent,
        autoCloseShift: settings!.autoCloseShift,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> generateNewStaticQr() async {
    if (settings != null) {
      final newStaticToken = 'static_${DateTime.now().millisecondsSinceEpoch}';
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: settings!.isEnabled,
        method: settings!.method,
        qrValiditySeconds: settings!.qrValiditySeconds,
        wifiSsid: settings!.wifiSsid,
        wifiBssid: settings!.wifiBssid,
        staticQrToken: newStaticToken,
        staticQrLocked: settings!.staticQrLocked,
        lateTimeSetting: settings!.lateTimeSetting,
        autoMarkAbsent: settings!.autoMarkAbsent,
        autoCloseShift: settings!.autoCloseShift,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> verifyDisplay(String token) async {
    await _repository.verifyDisplayDeviceInSupabase(token);
  }

  Future<String> getOrGenerateDisplayLink() async {
    return await _repository.getOrGenerateDisplayLink();
  }

  Future<void> manageDisplayDevice(String displayId, String action, {String? name}) async {
    await _repository.manageDisplayDevice(displayId, action, name: name);
  }

  void setCurrentConnectedSSID(String ssid) {
    _currentConnectedSSID = ssid;
    notifyListeners();
  }

  void toggleManualAttendance(bool enabled) {
    _isManualAttendanceEnabled = enabled;
    notifyListeners();
  }

  Future<Map<String, dynamic>> markAttendance({
    required String token,
    required String method,
    String? userId,
  }) async {
    final uid = userId ?? SupabaseService.client.auth.currentUser?.id;
    if (uid == null) {
      return {
        'success': false,
        'reason': 'User not authenticated',
      };
    }

    final result = await _repository.processScanAttendanceInSupabase(
      token: token,
      userId: uid,
      userType: 'Staff',
      method: method,
      ssid: _currentConnectedSSID,
      bssid: '',
    );

    return result;
  }

  Future<void> toggleAutoMarkAbsent(bool enabled) async {
    if (settings != null) {
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: settings!.isEnabled,
        method: settings!.method,
        qrValiditySeconds: settings!.qrValiditySeconds,
        wifiSsid: settings!.wifiSsid,
        wifiBssid: settings!.wifiBssid,
        staticQrToken: settings!.staticQrToken,
        staticQrLocked: settings!.staticQrLocked,
        lateTimeSetting: settings!.lateTimeSetting,
        autoMarkAbsent: enabled,
        autoCloseShift: settings!.autoCloseShift,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> toggleAutoCloseShift(bool enabled) async {
    if (settings != null) {
      final updated = GymAttendanceSettings(
        gymId: settings!.gymId,
        isEnabled: settings!.isEnabled,
        method: settings!.method,
        qrValiditySeconds: settings!.qrValiditySeconds,
        wifiSsid: settings!.wifiSsid,
        wifiBssid: settings!.wifiBssid,
        staticQrToken: settings!.staticQrToken,
        staticQrLocked: settings!.staticQrLocked,
        lateTimeSetting: settings!.lateTimeSetting,
        autoMarkAbsent: settings!.autoMarkAbsent,
        autoCloseShift: enabled,
      );
      await _repository.saveAttendanceSettingsToSupabase(updated);
    }
  }

  Future<void> fetchDashboardStats(String gymId) async {
    await _repository.fetchOwnerDashboardStats(gymId);
  }

  Future<void> fetchAlerts(String gymId) async {
    await _repository.fetchAttendanceAlerts(gymId);
  }

  Future<void> fetchCorrections(String gymId) async {
    await _repository.fetchAttendanceCorrections(gymId);
  }

  Future<Map<String, dynamic>> submitCorrection({
    required String gymId,
    required String userId,
    required String? logId,
    required String date,
    required String checkIn,
    required String? checkOut,
    required String reason,
  }) async {
    return await _repository.submitAttendanceCorrection(
      gymId: gymId,
      userId: userId,
      logId: logId,
      date: date,
      checkIn: checkIn,
      checkOut: checkOut,
      reason: reason,
    );
  }

  Future<Map<String, dynamic>> reviewCorrection({
    required String requestId,
    required String status,
    required String gymId,
  }) async {
    return await _repository.reviewAttendanceCorrection(
      requestId: requestId,
      status: status,
      gymId: gymId,
    );
  }
}
