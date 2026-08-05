import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/skeleton_loader.dart';

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});
  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _isLoading = false); });
  }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 8));

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Audit Logs', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                  const SizedBox(height: 4),
                  Text('Complete history of every admin action', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                ]),
                const Spacer(),
                SizedBox(width: 260, height: 40, child: TextField(controller: _searchController,
                  decoration: InputDecoration(hintText: 'Search logs...', hintStyle: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context)),
                    prefixIcon: Icon(Icons.search, size: 18, color: AdminTheme.mutedTextColor(context)),
                    filled: true, fillColor: AdminTheme.surfaceColor(context), contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none)),
                  style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context)))),
              ]),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard), border: Border.all(color: AdminTheme.borderColor(context))),
                child: Column(children: _logs.asMap().entries.map((e) => _logEntry(context, e.value, e.key == _logs.length - 1)).toList()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logEntry(BuildContext context, Map<String, dynamic> log, bool isLast) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: AdminTheme.borderColor(context)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: (log['color'] as Color).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(log['icon'] as IconData, size: 18, color: log['color'] as Color)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(log['action'] as String, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          const SizedBox(height: 4),
          if (log['details'] != null)
            Text(log['details'] as String, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.person_outline, size: 14, color: AdminTheme.mutedTextColor(context)),
            const SizedBox(width: 4),
            Text(log['admin'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
            const SizedBox(width: 16),
            Icon(Icons.schedule_rounded, size: 14, color: AdminTheme.mutedTextColor(context)),
            const SizedBox(width: 4),
            Text(log['time'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
            if (log['gym'] != null) ...[
              const SizedBox(width: 16),
              Icon(Icons.fitness_center_rounded, size: 14, color: AdminTheme.mutedTextColor(context)),
              const SizedBox(width: 4),
              Text(log['gym'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
            ],
          ]),
        ])),
      ]),
    );
  }
}

const _logs = [
  {'action': 'Changed Starter plan pricing', 'details': '₹499 → ₹599', 'admin': 'Super Admin', 'time': 'Aug 3, 2026 — 09:30 AM', 'gym': null, 'icon': Icons.edit_rounded, 'color': AdminTheme.primary},
  {'action': 'Extended trial by 30 days', 'details': 'Extended trial from 3 months to 4 months', 'admin': 'Super Admin', 'time': 'Aug 3, 2026 — 09:15 AM', 'gym': 'Power House Gym', 'icon': Icons.timer_rounded, 'color': AdminTheme.info},
  {'action': 'Suspended gym', 'details': 'Reason: Payment overdue for 45 days', 'admin': 'Super Admin', 'time': 'Aug 2, 2026 — 06:00 PM', 'gym': 'CrossFit Arena', 'icon': Icons.pause_circle_rounded, 'color': AdminTheme.orange},
  {'action': 'Enabled Force Update', 'details': 'Set minimum version to v2.4.0, force update enabled', 'admin': 'Super Admin', 'time': 'Aug 2, 2026 — 02:30 PM', 'gym': null, 'icon': Icons.system_update_rounded, 'color': AdminTheme.teal},
  {'action': 'Disabled AI Diet feature', 'details': 'AI Diet feature toggle turned off globally', 'admin': 'Super Admin', 'time': 'Aug 1, 2026 — 11:00 AM', 'gym': null, 'icon': Icons.toggle_off_rounded, 'color': AdminTheme.warning},
  {'action': 'Manual payment recorded', 'details': '₹999 — Pro Plan — Bank Transfer', 'admin': 'Super Admin', 'time': 'Aug 1, 2026 — 09:00 AM', 'gym': 'Iron Paradise', 'icon': Icons.payment_rounded, 'color': AdminTheme.success},
  {'action': 'Activated gym', 'details': 'Status changed from Trial to Active', 'admin': 'Super Admin', 'time': 'Jul 31, 2026 — 04:00 PM', 'gym': 'Thunder Gym', 'icon': Icons.check_circle_rounded, 'color': AdminTheme.success},
  {'action': 'Disabled gym', 'details': 'Reason: Terms Violation — Fake reviews detected', 'admin': 'Super Admin', 'time': 'Jul 30, 2026 — 10:00 AM', 'gym': 'Yoga Bliss Center', 'icon': Icons.block_rounded, 'color': AdminTheme.danger},
  {'action': 'Sent notification to all gyms', 'details': 'Type: Push — "New Feature: AI Workout Plans"', 'admin': 'Super Admin', 'time': 'Jul 29, 2026 — 03:00 PM', 'gym': null, 'icon': Icons.notifications_rounded, 'color': AdminTheme.primary},
  {'action': 'Database backup created', 'details': 'Full backup — 2.3 GB', 'admin': 'System', 'time': 'Jul 29, 2026 — 07:00 AM', 'gym': null, 'icon': Icons.backup_rounded, 'color': AdminTheme.teal},
];
