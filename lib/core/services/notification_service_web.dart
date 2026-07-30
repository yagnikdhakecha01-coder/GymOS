class NotificationService {
  static Future<void> initialize() async {}
  static Future<void> requestPermissions() async {}
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    print('Web Notification: $title - $body');
  }
}
