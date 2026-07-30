import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/auth_viewmodel.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDbNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Provider.of<AuthViewModel>(context, listen: false).clearUnreadNotifications();
      } catch (_) {}
    });
  }

  Future<void> _loadDbNotifications() async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId != null) {
        final res = await SupabaseService.client
            .from('notifications')
            .select()
            .eq('gym_id', gymId)
            .order('created_at', ascending: false);
        
        if (mounted) {
          setState(() {
            _notifications = List<Map<String, dynamic>>.from(res ?? []);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading notifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getIconForTitle(String title) {
    title = title.toLowerCase();
    if (title.contains('expire') || title.contains('warning')) return Icons.warning_amber_rounded;
    if (title.contains('signup') || title.contains('member') || title.contains('register')) return Icons.person_add_outlined;
    if (title.contains('payment') || title.contains('confirm') || title.contains('received')) return Icons.check_circle_outline_rounded;
    if (title.contains('staff') || title.contains('check')) return Icons.badge_outlined;
    return Icons.notifications_active_outlined;
  }

  Color _getColorForTitle(String title) {
    title = title.toLowerCase();
    if (title.contains('expire') || title.contains('warning')) return AppTheme.warning;
    if (title.contains('signup') || title.contains('member') || title.contains('register')) return AppTheme.success;
    if (title.contains('payment') || title.contains('confirm') || title.contains('received')) return AppTheme.success;
    if (title.contains('staff') || title.contains('check')) return AppTheme.info;
    return AppTheme.primary;
  }

  void _markAllRead() {
    try {
      Provider.of<AuthViewModel>(context, listen: false).clearUnreadNotifications();
    } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ All notifications marked as read'), backgroundColor: AppTheme.success),
    );
  }

  void _showNotificationDetail(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? 'Notification';
    final body = item['body']?.toString() ?? '';
    final created = DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now();
    final time = DateFormat('dd MMM yyyy, hh:mm a').format(created);
    final icon = _getIconForTitle(title);
    final color = _getColorForTitle(title);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body, style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            Text(time, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? 'Notification';
    final body = item['body']?.toString() ?? '';
    final created = DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now();
    final time = DateFormat('dd MMM yyyy, hh:mm a').format(created);
    final icon = _getIconForTitle(title);
    final color = _getColorForTitle(title);

    return CustomCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: () => _showNotificationDetail(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      time,
                      style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: Text(
              'Mark all read',
              style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notifications.isEmpty
                ? Center(
                    child: Text(
                      'No notifications found.',
                      style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      return _buildNotificationItem(_notifications[index]);
                    },
                  ),
      ),
    );
  }
}
