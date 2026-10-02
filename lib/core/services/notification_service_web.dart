class NotificationService {
  static bool isAppInForeground = true;
  static void setAppInForeground(bool inForeground) {
    isAppInForeground = inForeground;
  }
  static Future<void> initialize() async {}
  static Future<void> requestPermissions() async {}
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool force = false,
  }) async {
    print('Web Notification: $title - $body (payload: $payload)');
  }
}
