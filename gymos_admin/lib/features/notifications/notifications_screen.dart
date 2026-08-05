import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/skeleton_loader.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  String _selectedType = NotificationType.push;
  String _selectedTarget = NotificationTarget.allGyms;
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _isLoading = false); });
  }

  @override
  void dispose() { _titleController.dispose(); _messageController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 4));
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
              Text('Notifications', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              const SizedBox(height: 4),
              Text('Send push notifications, banners, and announcements', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
              const SizedBox(height: 28),
              if (isDesktop)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: _buildComposeForm(context)),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: _buildHistory(context)),
                ])
              else ...[_buildComposeForm(context), const SizedBox(height: 24), _buildHistory(context)],
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
        Text('Compose Notification', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        const SizedBox(height: 24),
        // Type selector
        Text('Type', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          _typeChip('Push', NotificationType.push, Icons.notifications_rounded),
          _typeChip('Banner', NotificationType.banner, Icons.announcement_rounded),
          _typeChip('Popup', NotificationType.popup, Icons.open_in_new_rounded),
          _typeChip('Maintenance', NotificationType.maintenance, Icons.build_rounded),
          _typeChip('Offer', NotificationType.offer, Icons.local_offer_rounded),
        ]),
        const SizedBox(height: 20),
        // Target selector
        Text('Send To', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          _targetChip('All Gyms', NotificationTarget.allGyms),
          _targetChip('Trial Gyms', NotificationTarget.trialGyms),
          _targetChip('Active Gyms', NotificationTarget.activeGyms),
          _targetChip('Selected Gyms', NotificationTarget.selectedGyms),
        ]),
        const SizedBox(height: 20),
        _buildField('Title', _titleController, 'Enter notification title'),
        const SizedBox(height: 16),
        _buildField('Message', _messageController, 'Enter your message...', maxLines: 4),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification sent successfully!'), backgroundColor: AdminTheme.success));
            },
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text('Send Notification', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
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
        Text('Sent History', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        const SizedBox(height: 16),
        ..._sentHistory.map((h) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: (h['color'] as Color).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(h['icon'] as IconData, size: 18, color: h['color'] as Color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h['title'] as String, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
              const SizedBox(height: 2),
              Text(h['target'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
              Text(h['time'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
            ])),
          ]),
        )),
      ]),
    );
  }
}

const _sentHistory = [
  {'title': 'New Feature: AI Workout', 'target': 'All Gyms', 'time': '2h ago', 'icon': Icons.notifications_rounded, 'color': AdminTheme.primary},
  {'title': 'Maintenance Notice', 'target': 'All Gyms', 'time': '1d ago', 'icon': Icons.build_rounded, 'color': AdminTheme.orange},
  {'title': 'Diwali Offer — 20% Off', 'target': 'Active Gyms', 'time': '3d ago', 'icon': Icons.local_offer_rounded, 'color': AdminTheme.success},
  {'title': 'Update to v2.4.1', 'target': 'Trial Gyms', 'time': '5d ago', 'icon': Icons.system_update_rounded, 'color': AdminTheme.info},
];
