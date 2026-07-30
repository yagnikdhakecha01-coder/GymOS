import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'supabase_service.dart';
import 'notification_service_mobile.dart';
import '../../features/authentication/auth_viewmodel.dart';

class AlertsNotificationEngine {
  static Timer? _timer;
  static final Set<String> _notifiedEntities = {};
  static bool _isRunning = false;

  /// Starts the notification background check loop (every 3 seconds)
  static void start(BuildContext context) {
    if (_isRunning) return;
    _isRunning = true;

    // Periodically run check every 3 seconds to guarantee near instant alerts
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
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
