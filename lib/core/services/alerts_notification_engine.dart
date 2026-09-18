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

    // Periodically run check every 30 seconds to guarantee push alerts & badge count without network thrashing
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
        final role = (authVm.selectedRole ?? authVm.storage.getUserRole() ?? '').toLowerCase();
        final bool isOwner = role == 'owner' || role == 'superadmin' || role == 'admin';
        final bool isStaff = role == 'staff' || role == 'receptionist' || role == 'trainer';
        final bool isMember = role == 'member';
        final staffId = authVm.staffRecord?.id;
        final authUid = authVm.currentUser?.id;
        final memberId = storage.getString('member_id');
        
        if (gymId != null && SupabaseService.isInitialized) {
          // 1. Run membership expiring alerts (Dual Notification: Owner + Specific Member)
          // Run only on Owner client to avoid redundant DB executions
          if (isOwner) {
            try {
              await SupabaseService.client.rpc('check_membership_expiring_alerts', params: {'p_gym_id': gymId});
            } catch (_) {
              try {
                await SupabaseService.client.rpc('check_membership_expiring_15_days', params: {'p_gym_id': gymId});
              } catch (_) {}
            }
          }

          // 2. Fetch notifications for this gym and filter strictly by active role & user
          try {
            final List allNotifs = await SupabaseService.client
                .from('notifications')
                .select()
                .eq('gym_id', gymId)
                .order('created_at', ascending: false);

            final matchingNotifs = allNotifs.where((n) {
              final targetRole = (n['target_role']?.toString() ?? '').toLowerCase();
              final notifUserId = n['user_id']?.toString();

              if (isOwner) {
                // Owner sees Owner, All, Both, or untargeted legacy alerts
                return targetRole == 'owner' || targetRole == 'all' || targetRole == 'both' || targetRole.isEmpty;
              } else if (isStaff) {
                // Staff NEVER sees Owner-private notifications
                if (targetRole == 'owner') return false;
                final bool isRoleMatch = targetRole == 'staff' || targetRole == 'all' || targetRole == 'both';
                if (!isRoleMatch) return false;
                // If targeted to a specific user, must match this staff
                if (notifUserId != null && notifUserId.isNotEmpty) {
                  return notifUserId == staffId || notifUserId == authUid;
                }
                return true;
              } else if (isMember) {
                // Member NEVER sees Owner or Staff notifications
                if (targetRole == 'owner' || targetRole == 'staff') return false;
                final bool isRoleMatch = targetRole == 'member' || targetRole == 'all' || targetRole == 'both';
                if (!isRoleMatch) return false;
                // If targeted to a specific user, must match this member
                if (notifUserId != null && notifUserId.isNotEmpty) {
                  return notifUserId == memberId || notifUserId == authUid;
                }
                return true;
              }
              return false;
            }).toList();

            final unreadNotifs = matchingNotifs.where((n) => n['is_read'] != true).toList();

            authVm.setUnreadNotificationsCount(unreadNotifs.length);

            for (var notif in unreadNotifs) {
              final id = notif['id']?.toString() ?? '';
              final title = notif['title']?.toString() ?? 'Notification';
              final body = notif['body']?.toString() ?? notif['message']?.toString() ?? '';

              final uniqueKey = 'db_notif_$id';
              if (!_notifiedEntities.contains(uniqueKey)) {
                _notifiedEntities.add(uniqueKey);
                await storage.setString('notified_entities', jsonEncode(_notifiedEntities.toList()));

                await NotificationService.showNotification(
                  id: uniqueKey.hashCode,
                  title: title,
                  body: body,
                );
              }
            }
          } catch (e) {
            debugPrint('Error polling notifications: $e');
          }

          // 3. System Alerts Check (ONLY for Gym Owner / Admin)
          if (isOwner) {
            try {
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
                  await storage.setString('notified_entities', jsonEncode(_notifiedEntities.toList()));

                  try {
                    await SupabaseService.client.from('notifications').insert({
                      'gym_id': gymId,
                      'target_role': 'Owner',
                      'title': title,
                      'body': message,
                      'type': type,
                      'is_read': false,
                    });
                  } catch (_) {}

                  authVm.setUnreadNotificationsCount(authVm.unreadNotificationsCount + 1);

                  await NotificationService.showNotification(
                    id: uniqueKey.hashCode,
                    title: title,
                    body: message,
                  );
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('AlertsNotificationEngine error: $e');
      }
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }
}
