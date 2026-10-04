import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AdminNotificationItem {
  final String id;
  final String title;
  final String message;
  final String category; // 'gym_registered', 'subscription_change', 'support_ticket', 'payment_received', 'trial_expiry', 'system'
  final String priority; // 'normal', 'high', 'urgent'
  final bool isRead;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  AdminNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.priority,
    required this.isRead,
    required this.metadata,
    required this.createdAt,
  });

  factory AdminNotificationItem.fromMap(Map<String, dynamic> map) {
    return AdminNotificationItem(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      category: map['category']?.toString() ?? 'system',
      priority: map['priority']?.toString() ?? 'normal',
      isRead: map['is_read'] == true,
      metadata: map['metadata'] is Map ? Map<String, dynamic>.from(map['metadata']) : {},
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class AdminNotificationService {
  static SupabaseClient? get client => _client;
  static SupabaseClient? get _client {
    try {
      return AdminSupabaseService.isInitialized ? AdminSupabaseService.client : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch all notifications for Super Admin from Supabase
  static Future<List<AdminNotificationItem>> fetchNotifications({int limit = 50}) async {
    final client = _client;
    if (client == null) return [];
    try {
      final res = await client
          .from('admin_notifications')
          .select('*')
          .order('created_at', ascending: false)
          .limit(limit);
      
      return (res as List).map((e) => AdminNotificationItem.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      debugPrint('Error fetching admin_notifications: $e');
      return [];
    }
  }

  /// Fetch unread notifications count
  static Future<int> fetchUnreadCount() async {
    final client = _client;
    if (client == null) return 0;
    try {
      final res = await client
          .from('admin_notifications')
          .select('id')
          .eq('is_read', false);
      return (res as List).length;
    } catch (e) {
      debugPrint('Error fetching unread count: $e');
      return 0;
    }
  }

  /// Mark single notification as read
  static Future<bool> markAsRead(String id) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client
          .from('admin_notifications')
          .update({'is_read': true})
          .eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      return false;
    }
  }

  /// Mark all notifications as read
  static Future<bool> markAllAsRead() async {
    final client = _client;
    if (client == null) return false;
    try {
      await client
          .from('admin_notifications')
          .update({'is_read': true})
          .eq('is_read', false);
      return true;
    } catch (e) {
      debugPrint('Error marking all as read: $e');
      return false;
    }
  }

  /// Send broadcast notification (saved to database)
  static Future<bool> sendBroadcast({
    required String type,
    required String target,
    required String title,
    required String message,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.from('broadcast_notifications').insert({
        'type': type,
        'target': target,
        'title': title,
        'message': message,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Error sending broadcast notification: $e');
      return false;
    }
  }

  /// Fetch broadcast notifications history
  static Future<List<Map<String, dynamic>>> fetchBroadcastHistory() async {
    final client = _client;
    if (client == null) return [];
    try {
      final res = await client
          .from('broadcast_notifications')
          .select('*')
          .order('created_at', ascending: false)
          .limit(30);
      return (res as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint('Error fetching broadcast history: $e');
      return [];
    }
  }
}
