import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'supabase_service.dart';
import 'notification_service_mobile.dart';
import '../repository/gym_repository.dart';
import '../../features/authentication/auth_viewmodel.dart';

class AlertsNotificationEngine {
  static Timer? _timer;
  static final Set<String> _notifiedEntities = {};
  static bool _isRunning = false;

  /// Starts the notification background check loop (every 3 seconds)
  static void start(BuildContext context) {
    if (_isRunning) return;
    _isRunning = true;

    final gymRepo = Provider.of<GymRepository>(context, listen: false);
    final storage = gymRepo.storage;

    // Load persisted notified entities from shared preferences
    final savedData = storage.getString('notified_entities');
    if (savedData != null && savedData.isNotEmpty) {
      try {
        final List parsed = jsonDecode(savedData);
        _notifiedEntities.addAll(parsed.map((e) => e.toString()));
      } catch (_) {}
    }

    // Periodically run check every 20 seconds to guarantee alerts
    _timer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      try {
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
        
        if (gymId != null && SupabaseService.isInitialized) {
          final List response = await SupabaseService.client.rpc(
            'check_new_alerts_v1',
            params: {'p_gym_id': gymId},
          );

          for (var item in response) {
            final map = Map<String, dynamic>.from(item as Map);
            final type = map['alert_type'] as String;
            final entityId = map['entity_id'] as String;
            final title = map['title'] as String;
            final message = map['message'] as String;

            final uniqueKey = '${type}_$entityId';

            if (!_notifiedEntities.contains(uniqueKey)) {
              _notifiedEntities.add(uniqueKey);
              
              // Persist notified entities list
              await storage.setString('notified_entities', jsonEncode(_notifiedEntities.toList()));

              // Insert the alert as a notification in Supabase so it appears in the notification center
              try {
                await SupabaseService.client.from('notifications').insert({
                  'gym_id': gymId,
                  'title': title,
                  'body': message,
                  'is_read': false,
                });
              } catch (e) {
                debugPrint('Error inserting notification to DB: $e');
              }

              // Update local unread notifications count in viewmodel
              authVm.setUnreadNotificationsCount(authVm.unreadNotificationsCount + 1);

              // Generate a stable numeric notification ID
              final notificationId = uniqueKey.hashCode;
              
              await NotificationService.showNotification(
                id: notificationId,
                title: title,
                body: message,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('AlertsNotificationEngine error: $e');
      }
    });
  }

  /// Stops the loop (e.g. on logout)
  static void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }
}
