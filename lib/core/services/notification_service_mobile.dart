import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../navigation/app_router.dart';
import 'supabase_service.dart';
import '../../features/dashboard/support_chat_screen.dart';
import '../../features/dashboard/support_tickets_screen.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _permissionRequested = false;
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
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            handleNotificationTapPayload(payload);
          }
        },
      );

      // Check if app was launched via notification click
      final launchDetails = await _localNotificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            handleNotificationTapPayload(payload);
          });
        }
      }

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

  static Future<void> handleNotificationTapPayload(String payload) async {
    try {
      final Map<String, dynamic> data = jsonDecode(payload);
      final String type = data['type']?.toString() ?? '';
      final String ticketId = data['ticket_id']?.toString() ?? '';

      if (type == 'support_ticket' && ticketId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final navState = AppRouter.rootNavigatorKey.currentState;
          if (navState == null) return;

          Map<String, dynamic>? ticketData;
          if (SupabaseService.isInitialized) {
            try {
              final res = await SupabaseService.client
                  .from('support_tickets')
                  .select()
                  .eq('id', ticketId)
                  .maybeSingle();
              if (res != null) {
                ticketData = Map<String, dynamic>.from(res);
              }
            } catch (e) {
              debugPrint('Error fetching ticket for notification deep link: $e');
            }
          }

          if (ticketData != null) {
            navState.push(
              AppRouter.slideRoute(SupportChatScreen(ticket: ticketData)),
            );
          } else {
            navState.push(
              AppRouter.slideRoute(const SupportTicketsScreen()),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('NotificationService handleNotificationTapPayload error: $e');
    }
  }

  static Future<void> requestPermissions() async {
    _permissionRequested = true;
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
    String? payload,
    bool force = false,
  }) async {
    // If the user is currently using the app and force is false,
    // do NOT pop up a system status-bar notification.
    if (isAppInForeground && !force) {
      return;
    }

    try {
      await initialize();
      if (!_permissionRequested) {
        await requestPermissions();
      }

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
        payload: payload,
      );
    } catch (e) {
      print('NotificationService showNotification error: $e');
    }
  }
}
