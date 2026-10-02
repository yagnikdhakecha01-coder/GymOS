import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/services/announcements_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../authentication/auth_viewmodel.dart';
import '../member_app_viewmodel.dart';

class MemberNotificationItem {
  final String id;
  final String title;
  final String message;
  final String type; // 'expiry', 'payment', 'announcement', 'general'
  final DateTime createdAt;
  final String imageUrl;
  final bool isRead;

  MemberNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.imageUrl = '',
    this.isRead = true,
  });
}

class MemberNotificationsScreen extends StatefulWidget {
  const MemberNotificationsScreen({super.key});

  @override
  State<MemberNotificationsScreen> createState() => _MemberNotificationsScreenState();
}

class _MemberNotificationsScreenState extends State<MemberNotificationsScreen> {
  List<MemberNotificationItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final List<MemberNotificationItem> combined = [];

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final memberVm = Provider.of<MemberAppViewModel>(context, listen: false);

      final prefs = await SharedPreferences.getInstance();
      final gymInfoStr = prefs.getString('gymos_gym_info');
      String? gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId == null && gymInfoStr != null) {
        try {
          final gymInfo = jsonDecode(gymInfoStr) as Map<String, dynamic>;
          gymId = gymInfo['id'];
        } catch (_) {}
      }

      final authUid = authVm.currentUser?.id;
      final memberId = memberVm.memberId.isNotEmpty ? memberVm.memberId : prefs.getString('member_id');

      // Determine member's join date to filter out historical notifications/announcements
      DateTime? memberJoinDate;
      final rawJoin = memberVm.joinDate.isNotEmpty 
          ? memberVm.joinDate 
          : (prefs.getString('member_cached_join_date') ?? prefs.getString('member_join_date'));
      if (rawJoin != null && rawJoin.trim().isNotEmpty) {
        final trimmed = rawJoin.trim();
        final iso = DateTime.tryParse(trimmed);
        if (iso != null) {
          memberJoinDate = DateTime(iso.year, iso.month, iso.day);
        } else {
          for (final fmt in ['dd MMM yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd', 'dd/MM/yyyy', 'd MMM yyyy']) {
            try {
              final d = DateFormat(fmt).parse(trimmed);
              memberJoinDate = DateTime(d.year, d.month, d.day);
              break;
            } catch (_) {}
          }
        }
      }

      // 1. Fetch personal member notifications from DB
      if (gymId != null && SupabaseService.isInitialized) {
        try {
          final dbRes = await SupabaseService.client
              .from('notifications')
              .select()
              .eq('gym_id', gymId)
              .order('created_at', ascending: false)
              .limit(50);

          for (var row in dbRes) {
            final targetRole = (row['target_role']?.toString() ?? '').toLowerCase();
            // Strictly exclude Owner and Staff notifications
            if (targetRole == 'owner' || targetRole == 'staff') continue;

            final notifUserId = row['user_id']?.toString();
            // If targeted to a specific user, verify it belongs to this member
            if (notifUserId != null && notifUserId.isNotEmpty) {
              final matches = (notifUserId == memberId || notifUserId == authUid);
              if (!matches) continue;
            }

            final created = DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now();

            // Strictly filter out notifications created before member joined
            if (memberJoinDate != null && created.isBefore(memberJoinDate)) {
              continue;
            }

            final id = row['id']?.toString() ?? '';
            final title = row['title']?.toString() ?? 'Notification';
            final body = row['body']?.toString() ?? row['message']?.toString() ?? '';
            final type = row['type']?.toString() ?? 'general';
            final isRead = row['is_read'] == true;

            combined.add(MemberNotificationItem(
              id: id,
              title: title,
              message: body,
              type: type,
              createdAt: created,
              isRead: isRead,
            ));
          }
        } catch (e) {
          debugPrint('Error fetching member db notifications: $e');
        }
      }

      // 2. Fetch Sent Announcements (filtered by join date)
      try {
        final annList = await AnnouncementsService.getAnnouncements(gymId: gymId, filterJoinDate: memberJoinDate);
        final sent = annList.where((e) => e.status == 'Sent').toList();
        for (var ann in sent) {
          final created = DateTime.tryParse(ann.date) ?? DateTime.now();
          if (memberJoinDate != null && created.isBefore(memberJoinDate)) {
            continue;
          }
          combined.add(MemberNotificationItem(
            id: ann.id,
            title: ann.title,
            message: ann.message,
            type: 'announcement',
            createdAt: created,
            imageUrl: ann.image,
            isRead: true,
          ));
        }
      } catch (e) {
        debugPrint('Error fetching announcements: $e');
      }

      // 3. Sort newest first
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    } catch (e) {
      debugPrint('Error loading member notifications: $e');
    }

    if (mounted) {
      setState(() {
        _items = combined;
        _isLoading = false;
      });
    }
  }

  Color _getTagColor(String type) {
    switch (type.toLowerCase()) {
      case 'expiry':
        return AppTheme.warning;
      case 'payment':
        return AppTheme.success;
      case 'holiday':
        return Colors.purple;
      case 'announcement':
      default:
        return AppTheme.primary;
    }
  }

  String _getTagLabel(String type) {
    switch (type.toLowerCase()) {
      case 'expiry':
        return 'PLAN EXPIRY';
      case 'payment':
        return 'PAYMENT';
      case 'holiday':
        return 'HOLIDAY';
      case 'announcement':
        return 'ANNOUNCEMENT';
      default:
        return 'NOTICE';
    }
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'expiry':
        return Icons.timer_outlined;
      case 'payment':
        return Icons.check_circle_outline_rounded;
      case 'holiday':
        return Icons.celebration_outlined;
      case 'announcement':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 56, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text('No Notifications Yet', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Text('We\'ll notify you when there\'s an update.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppTheme.pagePadding),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final tagColor = _getTagColor(item.type);
                      final tagLabel = _getTagLabel(item.type);
                      final iconData = _getIconForType(item.type);
                      final timeStr = DateFormat('dd MMM, hh:mm a').format(item.createdAt);

                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(iconData, size: 16, color: tagColor),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: tagColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        tagLabel,
                                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: tagColor),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(timeStr, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              item.title,
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.message,
                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                            ),
                            if (item.imageUrl.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  item.imageUrl,
                                  height: 150,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => const SizedBox(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
