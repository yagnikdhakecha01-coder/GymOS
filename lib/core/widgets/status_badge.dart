import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme.dart';

enum BadgeType { active, expired, frozen, onLeave, pending }

class StatusBadge extends StatelessWidget {
  final String text;
  final BadgeType type;

  const StatusBadge({
    super.key,
    required this.text,
    required this.type,
  });

  factory StatusBadge.active() => const StatusBadge(text: 'Active', type: BadgeType.active);
  factory StatusBadge.expired() => const StatusBadge(text: 'Expired', type: BadgeType.expired);
  factory StatusBadge.frozen() => const StatusBadge(text: 'Frozen', type: BadgeType.frozen);
  factory StatusBadge.onLeave() => const StatusBadge(text: 'On Leave', type: BadgeType.onLeave);
  factory StatusBadge.pending() => const StatusBadge(text: 'Pending', type: BadgeType.pending);

  factory StatusBadge.fromStatus(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return const StatusBadge(text: '🟢 Connected', type: BadgeType.active);
      case 'pending activation':
        return const StatusBadge(text: '🟡 Pending', type: BadgeType.onLeave);
      case 'invitation expired':
        return const StatusBadge(text: '🔴 Expired', type: BadgeType.expired);
      case 'expired':
        return const StatusBadge(text: 'Expired', type: BadgeType.expired);
      case 'frozen':
        return const StatusBadge(text: 'Frozen', type: BadgeType.frozen);
      case 'on leave':
        return const StatusBadge(text: 'On Leave', type: BadgeType.onLeave);
      default:
        return StatusBadge(text: status, type: BadgeType.pending);
    }
  }

  Color get _bgColor {
    switch (type) {
      case BadgeType.active:
        return AppTheme.successLight;
      case BadgeType.expired:
        return AppTheme.dangerLight;
      case BadgeType.frozen:
        return AppTheme.infoLight;
      case BadgeType.onLeave:
        return AppTheme.warningLight;
      case BadgeType.pending:
        return AppTheme.surfaceGray;
    }
  }

  Color get _textColor {
    switch (type) {
      case BadgeType.active:
        return AppTheme.success;
      case BadgeType.expired:
        return AppTheme.danger;
      case BadgeType.frozen:
        return AppTheme.info;
      case BadgeType.onLeave:
        return const Color(0xFFD97706);
      case BadgeType.pending:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: _textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
