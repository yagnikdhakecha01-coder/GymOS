class GymAttendanceSettings {
  final String gymId;
  final bool isEnabled;
  final String method; // QR Only, WiFi Only, QR + WiFi, Static QR + WiFi
  final int qrValiditySeconds;
  final String wifiSsid;
  final String wifiBssid;
  final String staticQrToken;
  final bool staticQrLocked;
  final String lateTimeSetting;
  final bool autoMarkAbsent;
  final bool autoCloseShift;

  GymAttendanceSettings({
    required this.gymId,
    required this.isEnabled,
    required this.method,
    required this.qrValiditySeconds,
    required this.wifiSsid,
    required this.wifiBssid,
    required this.staticQrToken,
    required this.staticQrLocked,
    required this.lateTimeSetting,
    required this.autoMarkAbsent,
    required this.autoCloseShift,
  });

  factory GymAttendanceSettings.fromJson(Map<String, dynamic> json) {
    return GymAttendanceSettings(
      gymId: json['gym_id'] as String,
      isEnabled: json['is_enabled'] as bool? ?? true,
      method: json['method'] as String? ?? 'QR Only',
      qrValiditySeconds: json['qr_validity_seconds'] as int? ?? 150,
      wifiSsid: json['wifi_ssid'] as String? ?? '',
      wifiBssid: json['wifi_bssid'] as String? ?? '',
      staticQrToken: json['static_qr_token'] as String? ?? '',
      staticQrLocked: json['static_qr_locked'] as bool? ?? false,
      lateTimeSetting: json['late_time_setting'] as String? ?? '09:05 AM',
      autoMarkAbsent: json['auto_mark_absent'] as bool? ?? false,
      autoCloseShift: json['auto_close_shift'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gym_id': gymId,
      'is_enabled': isEnabled,
      'method': method,
      'qr_validity_seconds': qrValiditySeconds,
      'wifi_ssid': wifiSsid,
      'wifi_bssid': wifiBssid,
      'static_qr_token': staticQrToken,
      'static_qr_locked': staticQrLocked,
      'late_time_setting': lateTimeSetting,
      'auto_mark_absent': autoMarkAbsent,
      'auto_close_shift': autoCloseShift,
    };
  }
}
