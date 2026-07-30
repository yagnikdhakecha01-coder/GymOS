import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      image: json['image'] as String? ?? '',
      audience: json['audience'] as String? ?? 'All Members',
      date: json['date'] as String? ?? '',
      status: json['status'] as String? ?? 'Sent',
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

  static final List<Announcement> _defaultAnnouncements = [
    Announcement(
      id: '1',
      title: 'Independence Day Timing Update 🇮🇳',
      message: 'On 15th August, the gym will be open only in the morning shift from 6:00 AM to 12:00 PM. Evening shift will remain closed.',
      image: 'https://images.unsplash.com/photo-1532375810709-75b1da00537c?auto=format&fit=crop&q=80&w=600',
      audience: 'All Members',
      date: '12 Aug 2026',
      status: 'Sent',
    ),
    Announcement(
      id: '2',
      title: 'New Strength Equipment Arrived! 🏋️',
      message: 'We have added two new squat racks and a hack squat machine in the strength section. Come check them out!',
      image: '',
      audience: 'All Members',
      date: '10 Aug 2026',
      status: 'Sent',
    ),
  ];

  static Future<List<Announcement>> getAnnouncements() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAnnouncements);
    if (raw == null) {
      return _defaultAnnouncements;
    }
    final List decoded = jsonDecode(raw);
    return decoded.map((e) => Announcement.fromJson(e)).toList();
  }

  static Future<void> addAnnouncement(Announcement ann) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getAnnouncements();
    current.insert(0, ann);
    await prefs.setString(_keyAnnouncements, jsonEncode(current.map((e) => e.toJson()).toList()));
  }

  static Future<void> deleteAnnouncement(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getAnnouncements();
    current.removeWhere((e) => e.id == id);
    await prefs.setString(_keyAnnouncements, jsonEncode(current.map((e) => e.toJson()).toList()));
  }
}
