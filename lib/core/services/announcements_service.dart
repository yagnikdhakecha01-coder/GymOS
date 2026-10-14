import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

class Announcement {
  final String id;
  final String title;
  final String message;
  final String image;
  final String audience;
  final String date;
  final String status; // Sent, Scheduled

  Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.image,
    required this.audience,
    required this.date,
    required this.status,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? json['body']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      audience: json['audience']?.toString() ?? json['target_role']?.toString() ?? 'Both (Staff & Members)',
      date: json['date']?.toString() ?? json['created_at']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Sent',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'image': image,
      'audience': audience,
      'date': date,
      'status': status,
    };
  }
}

class AnnouncementsService {
  static String _getKey(String? gymId) =>
      (gymId != null && gymId.isNotEmpty) ? 'gymos_announcements_$gymId' : 'gymos_announcements';

  static List<Announcement> _filterByDate(List<Announcement> list, DateTime minDate) {
    final startOfDay = DateTime(minDate.year, minDate.month, minDate.day);
    return list.where((a) {
      if (a.date.isEmpty) return true;
      final d = DateTime.tryParse(a.date);
      if (d != null) {
        return !d.isBefore(startOfDay);
      }
      return true;
    }).toList();
  }

  static Future<List<Announcement>> getAnnouncements({String? gymId, DateTime? filterJoinDate}) async {
    List<Announcement> announcements = [];
    final cacheKey = _getKey(gymId);

    if (SupabaseService.isInitialized) {
      try {
        final List dbRes = (gymId != null && gymId.isNotEmpty)
            ? await SupabaseService.client
                .from('announcements')
                .select()
                .eq('gym_id', gymId)
                .order('created_at', ascending: false)
            : await SupabaseService.client
                .from('announcements')
                .select()
                .order('created_at', ascending: false);

        if (dbRes.isNotEmpty) {
          announcements = dbRes.map((e) => Announcement.fromJson(e)).toList();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(cacheKey, jsonEncode(announcements.map((e) => e.toJson()).toList()));
          if (filterJoinDate != null) {
            return _filterByDate(announcements, filterJoinDate);
          }
          return announcements;
        }
      } catch (e) {
        print('AnnouncementsService fetch error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      final list = decoded.map((e) => Announcement.fromJson(e)).toList();
      if (filterJoinDate != null) {
        return _filterByDate(list, filterJoinDate);
      }
      return list;
    }

    return [];
  }

  static bool isValidUuid(String? id) {
    if (id == null) return false;
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return uuidRegex.hasMatch(id);
  }

  static String generateUuidV4() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<void> addAnnouncement(Announcement ann, {String? gymId}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = _getKey(gymId);

    final resolvedId = isValidUuid(ann.id) ? ann.id : generateUuidV4();
    final resolvedAnn = Announcement(
      id: resolvedId,
      title: ann.title,
      message: ann.message,
      image: ann.image,
      audience: ann.audience,
      date: ann.date,
      status: ann.status,
    );

    final current = await getAnnouncements(gymId: gymId);
    current.insert(0, resolvedAnn);
    await prefs.setString(cacheKey, jsonEncode(current.map((e) => e.toJson()).toList()));

    if (SupabaseService.isInitialized && gymId != null && gymId.isNotEmpty) {
      try {
        final String audienceLower = resolvedAnn.audience.toLowerCase();
        final bool targetStaff = audienceLower.contains('staff') || audienceLower.contains('both');
        final bool targetMembers = audienceLower.contains('member') || audienceLower.contains('both');
        final String targetRole = (targetStaff && targetMembers) ? 'Both' : (targetStaff ? 'Staff' : 'Member');

        await SupabaseService.client.from('announcements').insert({
          'id': resolvedId,
          'gym_id': gymId,
          'title': resolvedAnn.title,
          'message': resolvedAnn.message,
          'image': resolvedAnn.image,
          'audience': resolvedAnn.audience,
          'target_role': targetRole,
          'status': resolvedAnn.status,
        });

        // Direct client-side notification fanout (backup for DB trigger)
        final List<Map<String, dynamic>> notifRows = [];

        if (targetMembers) {
          try {
            final members = await SupabaseService.client
                .from('members')
                .select('user_id')
                .eq('gym_id', gymId);
            for (var m in members) {
              final uid = m['user_id']?.toString();
              if (uid != null && uid.isNotEmpty) {
                notifRows.add({
                  'gym_id': gymId,
                  'user_id': uid,
                  'target_role': 'Member',
                  'title': '📢 ${ann.title}',
                  'body': ann.message,
                  'type': 'announcement',
                  'is_read': false,
                });
              }
            }
          } catch (e) {
            print('Error fetching members for broadcast notification: $e');
          }
        }

        if (targetStaff) {
          try {
            final staff = await SupabaseService.client
                .from('staff')
                .select('user_id')
                .eq('gym_id', gymId);
            for (var s in staff) {
              final uid = s['user_id']?.toString();
              if (uid != null && uid.isNotEmpty) {
                notifRows.add({
                  'gym_id': gymId,
                  'user_id': uid,
                  'target_role': 'Staff',
                  'title': '📢 ${ann.title}',
                  'body': ann.message,
                  'type': 'announcement',
                  'is_read': false,
                });
              }
            }
          } catch (e) {
            print('Error fetching staff for broadcast notification: $e');
          }
        }

        // Add general role fallback notification
        notifRows.add({
          'gym_id': gymId,
          'target_role': targetRole,
          'title': '📢 ${ann.title}',
          'body': ann.message,
          'type': 'announcement',
          'is_read': false,
        });

        if (notifRows.isNotEmpty) {
          await SupabaseService.client.from('notifications').insert(notifRows);
        }
      } catch (e) {
        print('Error inserting announcement to Supabase: $e');
      }
    }
  }

  static Future<void> deleteAnnouncement(String id, {String? gymId}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = _getKey(gymId);
    final current = await getAnnouncements(gymId: gymId);
    current.removeWhere((e) => e.id == id);
    await prefs.setString(cacheKey, jsonEncode(current.map((e) => e.toJson()).toList()));

    if (SupabaseService.isInitialized) {
      try {
        if (isValidUuid(id)) {
          await SupabaseService.client.from('announcements').delete().eq('id', id);
        }
      } catch (e) {
        print('Error deleting announcement from Supabase: $e');
      }
    }
  }
}
