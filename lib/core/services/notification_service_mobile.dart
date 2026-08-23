import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool isAppInForeground = true;

  static void setAppInForeground(bool inForeground) {
    isAppInForeground = inForeground;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (response) {},
      );

      // Create high priority notification channel for Android with GymOS branding
      final androidImplementation = _localNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            'gymos_notifications',
            'GymOS Notifications',
            description: 'Alerts and updates from GymOS',
            importance: Importance.max,
            enableVibration: true,
            enableLights: true,
            ledColor: Color(0xFF6C4EFF),
          ),
        );
      }

      _initialized = true;
    } catch (e) {
      print('NotificationService initialize error: $e');
    }
  }

  static Future<void> requestPermissions() async {
    try {
      await initialize();
      final status = await Permission.notification.request();
      print('Notification permission status: $status');

      final androidImplementation = _localNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      final iosImplementation = _localNotificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      print('NotificationService requestPermissions error: $e');
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    bool force = false,
  }) async {
    // If the user is currently using the app and force is false,
    // do NOT pop up a system status-bar notification.
    if (isAppInForeground && !force) {
      return;
    }

    try {
      await initialize();

      final BigTextStyleInformation bigTextStyleInformation =
          BigTextStyleInformation(
        body,
        htmlFormatBigText: false,
        contentTitle: title,
        htmlFormatContentTitle: false,
        summaryText: 'GymOS',
        htmlFormatSummaryText: false,
      );

      final AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
        'gymos_notifications',
        'GymOS Notifications',
        channelDescription: 'Alerts and updates from GymOS',
        importance: Importance.max,
        priority: Priority.high,
        ticker: title,
        icon: '@mipmap/launcher_icon',
        color: const Color(0xFF6C4EFF),
        styleInformation: bigTextStyleInformation,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        enableLights: true,
        ledColor: const Color(0xFF6C4EFF),
        ledOnMs: 1000,
        ledOffMs: 500,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: 'GymOS',
        interruptionLevel: InterruptionLevel.active,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      await _localNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      print('NotificationService showNotification error: $e');
    }
  }
}
