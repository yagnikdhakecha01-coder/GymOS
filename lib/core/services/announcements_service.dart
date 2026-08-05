import 'dart:convert';
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
      audience: json['audience']?.toString() ?? json['target_role']?.toString() ?? 'All Members',
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
  static const String _keyAnnouncements = 'gymos_announcements';

  static Future<List<Announcement>> getAnnouncements({String? gymId}) async {
    List<Announcement> announcements = [];

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
          await prefs.setString(_keyAnnouncements, jsonEncode(announcements.map((e) => e.toJson()).toList()));
          return announcements;
        }

        // Also check public.notifications table
        final List notifRes = (gymId != null && gymId.isNotEmpty)
            ? await SupabaseService.client
                .from('notifications')
                .select()
                .eq('gym_id', gymId)
                .order('created_at', ascending: false)
            : await SupabaseService.client
                .from('notifications')
                .select()
                .order('created_at', ascending: false);

        if (notifRes.isNotEmpty) {
          announcements = notifRes.map((e) => Announcement.fromJson(e)).toList();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyAnnouncements, jsonEncode(announcements.map((e) => e.toJson()).toList()));
          return announcements;
        }
      } catch (e) {
        print('AnnouncementsService fetch error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAnnouncements);
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      return decoded.map((e) => Announcement.fromJson(e)).toList();
    }

    // Return clean empty list by default - NO FAKE HARDCODED ANNOUNCEMENTS!
    return [];
  }

  static Future<void> addAnnouncement(Announcement ann, {String? gymId}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getAnnouncements(gymId: gymId);
    current.insert(0, ann);
    await prefs.setString(_keyAnnouncements, jsonEncode(current.map((e) => e.toJson()).toList()));

    if (SupabaseService.isInitialized && gymId != null && gymId.isNotEmpty) {
      try {
        await SupabaseService.client.from('announcements').insert({
          'gym_id': gymId,
          'title': ann.title,
          'message': ann.message,
          'image': ann.image,
          'audience': ann.audience,
          'status': ann.status,
        });
      } catch (e) {
        print('Error inserting announcement to Supabase: $e');
      }
    }
  }

  static Future<void> deleteAnnouncement(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getAnnouncements();
    current.removeWhere((e) => e.id == id);
    await prefs.setString(_keyAnnouncements, jsonEncode(current.map((e) => e.toJson()).toList()));

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('announcements').delete().eq('id', id);
      } catch (_) {}
    }
  }
}
