import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'notification_service_mobile.dart';
import '../repository/gym_repository.dart';
import '../../features/authentication/auth_viewmodel.dart';

class AlertsNotificationEngine {
  static Timer? _timer;
  static RealtimeChannel? _realtimeChannel;
  static final Set<String> _notifiedEntities = {};
  static bool _isRunning = false;

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    for (final fmt in ['dd MMM yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy', 'd MMM yyyy']) {
      try {
        final d = DateFormat(fmt).parse(trimmed);
        return DateTime(d.year, d.month, d.day);
      } catch (_) {}
    }
    return null;
  }

  static DateTime? _getUserStartDate({
    required bool isOwner,
    required bool isStaff,
    required bool isMember,
    required AuthViewModel authVm,
    required dynamic storage,
  }) {
    String? rawDate;
    if (isMember) {
      rawDate = storage.getString('member_cached_join_date') ??
                storage.getString('member_join_date');
    } else if (isStaff) {
      rawDate = authVm.staffRecord?.joinDate ?? 
                authVm.staffRecord?.createdAt ??
                storage.getString('staff_join_date');
    } else if (isOwner) {
      rawDate = authVm.activeAssociation?.createdAt ??
                authVm.gymInfo?['created_at']?.toString() ??
                authVm.currentUser?.createdAt;
    }
    return _parseDate(rawDate);
  }

  /// Starts the notification background check loop & realtime listener
  static void start(BuildContext context) {
    if (_isRunning) return;
    _isRunning = true;

    // Smoothly request notification permissions when user enters active gym dashboard
    NotificationService.requestPermissions();

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

    // ── 1. REALTIME LISTENER FOR INSTANT SUPPORT MESSAGES & ALERTS ──
    _subscribeRealtime(context);

    // Initial run on startup (alerts check)
    _runPeriodicChecks(context);

    // ── 2. PERIODIC POLL LOOP (every 5 minutes instead of 30 seconds) ──
    _timer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await _runPeriodicChecks(context);
    });
  }

  static Future<void> _runPeriodicChecks(BuildContext context) async {
    try {
      final gymRepo = Provider.of<GymRepository>(context, listen: false);
      final storage = gymRepo.storage;
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      final role = (authVm.selectedRole ?? authVm.storage.getUserRole() ?? '').toLowerCase();
      final bool isOwner = role == 'owner' || role == 'superadmin' || role == 'admin';
      final bool isStaff = role == 'staff' || role == 'receptionist' || role == 'trainer';
      final bool isMember = role == 'member';
      final staffId = authVm.staffRecord?.id;
      final authUid = authVm.currentUser?.id;
      final memberId = storage.getString('member_id');
      final userStartDate = _getUserStartDate(
        isOwner: isOwner,
        isStaff: isStaff,
        isMember: isMember,
        authVm: authVm,
        storage: storage,
      );
      
      if (gymId != null && SupabaseService.isInitialized) {
        // A. Run membership expiring alerts (Owner only, once per day per gym)
        if (isOwner) {
          final todayStr = DateTime.now().toIso8601String().substring(0, 10);
          final lastChecked = storage.getString('last_expiring_alerts_check_$gymId');
          if (lastChecked != todayStr) {
            try {
              await SupabaseService.client.rpc('check_membership_expiring_alerts', params: {'p_gym_id': gymId});
              await storage.setString('last_expiring_alerts_check_$gymId', todayStr);
            } catch (_) {
              try {
                await SupabaseService.client.rpc('check_membership_expiring_15_days', params: {'p_gym_id': gymId});
                await storage.setString('last_expiring_alerts_check_$gymId', todayStr);
              } catch (_) {}
            }
          }
        }

          // B. Fetch notifications for this gym and filter strictly by active role, user & join date
          try {
            final List allNotifs = await SupabaseService.client
                .from('notifications')
                .select()
                .eq('gym_id', gymId)
                .order('created_at', ascending: false)
                .limit(30);

            final matchingNotifs = allNotifs.where((n) {
              final targetRole = (n['target_role']?.toString() ?? '').toLowerCase();
              final notifUserId = n['user_id']?.toString();

              // Strictly exclude notifications created before user's join / start date
              if (userStartDate != null) {
                final notifCreated = DateTime.tryParse(n['created_at']?.toString() ?? '');
                if (notifCreated != null && notifCreated.isBefore(userStartDate)) {
                  return false;
                }
              }

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
              final type = notif['type']?.toString() ?? '';

              String? payload;
              bool forceAlert = false;
              if (type.startsWith('support_ticket:')) {
                final ticketId = type.replaceFirst('support_ticket:', '').trim();
                payload = jsonEncode({'type': 'support_ticket', 'ticket_id': ticketId});
                forceAlert = true;
              } else if (type == 'support_ticket') {
                payload = jsonEncode({'type': 'support_ticket', 'ticket_id': notif['entity_id'] ?? ''});
                forceAlert = true;
              }

              final uniqueKey = 'db_notif_$id';
              if (!_notifiedEntities.contains(uniqueKey)) {
                _notifiedEntities.add(uniqueKey);
                await storage.setString('notified_entities', jsonEncode(_notifiedEntities.toList()));

                await NotificationService.showNotification(
                  id: uniqueKey.hashCode,
                  title: title,
                  body: body,
                  payload: payload,
                  force: forceAlert,
                );
              }
            }
          } catch (e) {
            debugPrint('Error polling notifications: $e');
          }

          // C. System Alerts Check (ONLY for Gym Owner / Admin)
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
    }

  static void _subscribeRealtime(BuildContext context) {
    if (!SupabaseService.isInitialized) return;
    try {
      _realtimeChannel?.unsubscribe();
      _realtimeChannel = SupabaseService.client
          .channel('public:notifications_alerts_engine')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            callback: (payload) async {
              final record = payload.newRecord;
              if (record.isEmpty) return;

              final authVm = Provider.of<AuthViewModel>(context, listen: false);
              final gymRepo = Provider.of<GymRepository>(context, listen: false);
              final storage = gymRepo.storage;

              final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
              final notifGymId = record['gym_id']?.toString();
              if (gymId != null && notifGymId != null && gymId != notifGymId) {
                return; // Different gym
              }

              final role = (authVm.selectedRole ?? authVm.storage.getUserRole() ?? '').toLowerCase();
              final bool isOwner = role == 'owner' || role == 'superadmin' || role == 'admin';
              final bool isStaff = role == 'staff' || role == 'receptionist' || role == 'trainer';
              final bool isMember = role == 'member';
              final staffId = authVm.staffRecord?.id;
              final authUid = authVm.currentUser?.id;
              final memberId = storage.getString('member_id');

              final targetRole = (record['target_role']?.toString() ?? '').toLowerCase();
              final notifUserId = record['user_id']?.toString();

              // Check join date
              final userStartDate = _getUserStartDate(
                isOwner: isOwner,
                isStaff: isStaff,
                isMember: isMember,
                authVm: authVm,
                storage: storage,
              );
              if (userStartDate != null) {
                final notifCreated = DateTime.tryParse(record['created_at']?.toString() ?? '');
                if (notifCreated != null && notifCreated.isBefore(userStartDate)) {
                  return;
                }
              }

              bool isMatch = false;
              if (isOwner) {
                isMatch = targetRole == 'owner' || targetRole == 'all' || targetRole == 'both' || targetRole.isEmpty;
              } else if (isStaff) {
                if (targetRole != 'owner') {
                  final bool isRoleMatch = targetRole == 'staff' || targetRole == 'all' || targetRole == 'both';
                  if (isRoleMatch) {
                    if (notifUserId != null && notifUserId.isNotEmpty) {
                      isMatch = (notifUserId == staffId || notifUserId == authUid);
                    } else {
                      isMatch = true;
                    }
                  }
                }
              } else if (isMember) {
                if (targetRole != 'owner' && targetRole != 'staff') {
                  final bool isRoleMatch = targetRole == 'member' || targetRole == 'all' || targetRole == 'both';
                  if (isRoleMatch) {
                    if (notifUserId != null && notifUserId.isNotEmpty) {
                      isMatch = (notifUserId == memberId || notifUserId == authUid);
                    } else {
                      isMatch = true;
                    }
                  }
                }
              }

              if (!isMatch) return;

              final id = record['id']?.toString() ?? '';
              final title = record['title']?.toString() ?? 'Notification';
              final body = record['body']?.toString() ?? record['message']?.toString() ?? '';
              final type = record['type']?.toString() ?? '';

              String? notifPayload;
              bool forceAlert = false;
              if (type.startsWith('support_ticket:')) {
                final ticketId = type.replaceFirst('support_ticket:', '').trim();
                notifPayload = jsonEncode({'type': 'support_ticket', 'ticket_id': ticketId});
                forceAlert = true;
              } else if (type == 'support_ticket') {
                notifPayload = jsonEncode({'type': 'support_ticket', 'ticket_id': record['entity_id'] ?? ''});
                forceAlert = true;
              }

              final uniqueKey = 'db_notif_$id';
              if (!_notifiedEntities.contains(uniqueKey)) {
                _notifiedEntities.add(uniqueKey);
                await storage.setString('notified_entities', jsonEncode(_notifiedEntities.toList()));

                authVm.setUnreadNotificationsCount(authVm.unreadNotificationsCount + 1);

                await NotificationService.showNotification(
                  id: uniqueKey.hashCode,
                  title: title,
                  body: body,
                  payload: notifPayload,
                  force: forceAlert,
                );
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('AlertsNotificationEngine realtime subscription error: $e');
    }
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _isRunning = false;
  }
}
