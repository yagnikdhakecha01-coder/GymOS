import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/admin_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  bool _isSending = false;
  String _selectedType = NotificationType.push;
  String _selectedTarget = NotificationTarget.allGyms;
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  List<AdminNotificationItem> _liveNotifications = [];
  List<Map<String, dynamic>> _sentBroadcasts = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final notifs = await AdminNotificationService.fetchNotifications(limit: 50);
    final broadcasts = await AdminNotificationService.fetchBroadcastHistory();
    if (mounted) {
      setState(() {
        _liveNotifications = notifs;
        _sentBroadcasts = broadcasts;
        _isLoading = false;
      });
    }
  }

  Future<void> _sendNotification() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both title and message'), backgroundColor: AdminTheme.warning),
      );
      return;
    }

    setState(() => _isSending = true);
    final success = await AdminNotificationService.sendBroadcast(
      type: _selectedType,
      target: _selectedTarget,
      title: title,
      message: message,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (success) {
      _titleController.clear();
      _messageController.clear();
      _fetchData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Broadcast notification saved to database & dispatched!'), backgroundColor: AdminTheme.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error saving broadcast notification to database.'), backgroundColor: AdminTheme.danger),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 6));
    final isDesktop = AdminResponsive.isDesktop(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Platform Notifications', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                      const SizedBox(height: 4),
                      Text('Live platform events, database triggers, and broadcast announcements', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                    ],
                  ),
                  IconButton(
                    onPressed: _fetchData,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Notifications',
                    color: AdminTheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (isDesktop)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: _buildComposeForm(context)),
                  const SizedBox(width: 24),
                  Expanded(flex: 3, child: _buildHistory(context)),
                ])
              else ...[
                _buildComposeForm(context),
                const SizedBox(height: 24),
                _buildHistory(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposeForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard), border: Border.all(color: AdminTheme.borderColor(context))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Compose Broadcast Announcement', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        const SizedBox(height: 24),
        // Type selector
        Text('Notification Type', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _typeChip('Push', NotificationType.push, Icons.notifications_rounded),
          _typeChip('Banner', NotificationType.banner, Icons.announcement_rounded),
          _typeChip('Popup', NotificationType.popup, Icons.open_in_new_rounded),
          _typeChip('Maintenance', NotificationType.maintenance, Icons.build_rounded),
          _typeChip('Offer', NotificationType.offer, Icons.local_offer_rounded),
        ]),
        const SizedBox(height: 20),
        // Target selector
        Text('Target Gyms', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _targetChip('All Gyms', NotificationTarget.allGyms),
          _targetChip('Trial Gyms', NotificationTarget.trialGyms),
          _targetChip('Active Gyms', NotificationTarget.activeGyms),
          _targetChip('Selected Gyms', NotificationTarget.selectedGyms),
        ]),
        const SizedBox(height: 20),
        _buildField('Title', _titleController, 'e.g. New Feature Update / Scheduled Maintenance'),
        const SizedBox(height: 16),
        _buildField('Message', _messageController, 'Enter announcement message for gym owners...', maxLines: 4),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSending ? null : _sendNotification,
            icon: _isSending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(_isSending ? 'Sending...' : 'Send Broadcast Notification', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
          ),
        ),
      ]),
    );
  }

  Widget _typeChip(String label, String value, IconData icon) {
    final isActive = _selectedType == value;
    return InkWell(
      borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
      onTap: () => setState(() => _selectedType = value),
      child: AnimatedContainer(
        duration: AdminTheme.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AdminTheme.primary.withValues(alpha: 0.1) : AdminTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
          border: Border.all(color: isActive ? AdminTheme.primary.withValues(alpha: 0.4) : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: isActive ? AdminTheme.primary : AdminTheme.mutedTextColor(context)),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: isActive ? AdminTheme.primary : AdminTheme.secondaryTextColor(context))),
        ]),
      ),
    );
  }

  Widget _targetChip(String label, String value) {
    final isActive = _selectedTarget == value;
    return InkWell(
      borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
      onTap: () => setState(() => _selectedTarget = value),
      child: AnimatedContainer(
        duration: AdminTheme.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AdminTheme.primary.withValues(alpha: 0.1) : AdminTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
          border: Border.all(color: isActive ? AdminTheme.primary.withValues(alpha: 0.4) : Colors.transparent),
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: isActive ? AdminTheme.primary : AdminTheme.secondaryTextColor(context))),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
      const SizedBox(height: 6),
      TextField(controller: controller, maxLines: maxLines, style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
        decoration: InputDecoration(hintText: hint, hintStyle: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context)),
          filled: true, fillColor: AdminTheme.surfaceColor(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
    ]);
  }

  Widget _buildHistory(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard), border: Border.all(color: AdminTheme.borderColor(context))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Live Database Alerts', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
            if (_liveNotifications.any((n) => !n.isRead))
              TextButton(
                onPressed: () async {
                  await AdminNotificationService.markAllAsRead();
                  _fetchData();
                },
                child: Text('Mark All Read', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AdminTheme.primary)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_liveNotifications.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No database notifications yet.\nEvents like Gym Registration, Payments & Tickets will appear here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context))),
            ),
          )
        else
          ..._liveNotifications.take(15).map((item) {
            IconData icon = Icons.notifications_rounded;
            Color color = AdminTheme.primary;
            switch (item.category) {
              case 'gym_registered': icon = Icons.business_rounded; color = AdminTheme.primary; break;
              case 'subscription_change': icon = Icons.stars_rounded; color = AdminTheme.success; break;
              case 'support_ticket': icon = Icons.support_agent_rounded; color = AdminTheme.orange; break;
              case 'payment_received': icon = Icons.payments_rounded; color = Colors.green; break;
              case 'trial_expiry': icon = Icons.timer_rounded; color = AdminTheme.danger; break;
            }

            final diff = DateTime.now().difference(item.createdAt);
            String timeStr = 'Just now';
            if (diff.inMinutes >= 60) {
              timeStr = diff.inHours < 24 ? '${diff.inHours}h ago' : '${diff.inDays}d ago';
            } else if (diff.inMinutes > 0) {
              timeStr = '${diff.inMinutes}m ago';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: item.isRead ? AdminTheme.surfaceColor(context).withValues(alpha: 0.5) : AdminTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                border: Border.all(color: item.isRead ? Colors.transparent : color.withValues(alpha: 0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(item.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: item.isRead ? FontWeight.w500 : FontWeight.bold, color: AdminTheme.textColor(context))),
                        ),
                        Text(timeStr, style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context))),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(item.message, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
                  ]),
                ),
              ]),
            );
          }),
        if (_sentBroadcasts.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Text('Broadcast History', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          const SizedBox(height: 12),
          ..._sentBroadcasts.take(5).map((b) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.send_rounded, size: 16, color: AdminTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b['title']?.toString() ?? '', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                        Text(b['message']?.toString() ?? '', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AdminTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text((b['target'] ?? 'all').toString().toUpperCase(), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AdminTheme.primary)),
                  ),
                ],
              ),
            );
          }),
        ],
      ]),
    );
  }
}
