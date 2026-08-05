import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/admin_theme.dart';
import '../constants/app_constants.dart';

enum AdminBadgeType { trial, active, gracePeriod, suspended, disabled, custom }

class AdminStatusBadge extends StatelessWidget {
  final String text;
  final AdminBadgeType type;
  final Color? customColor;
  final Color? customBgColor;

  const AdminStatusBadge({
    super.key,
    required this.text,
    required this.type,
    this.customColor,
    this.customBgColor,
  });

  factory AdminStatusBadge.fromGymStatus(String status) {
    switch (status.toLowerCase()) {
      case 'trial':
        return const AdminStatusBadge(text: 'Trial', type: AdminBadgeType.trial);
      case 'active':
        return const AdminStatusBadge(text: 'Active', type: AdminBadgeType.active);
      case 'grace_period':
        return const AdminStatusBadge(text: 'Grace Period', type: AdminBadgeType.gracePeriod);
      case 'suspended':
        return const AdminStatusBadge(text: 'Suspended', type: AdminBadgeType.suspended);
      case 'disabled':
        return const AdminStatusBadge(text: 'Disabled', type: AdminBadgeType.disabled);
      default:
        return AdminStatusBadge(text: GymStatus.displayName(status), type: AdminBadgeType.custom);
    }
  }

  Color get _bgColor {
    if (customBgColor != null) return customBgColor!;
    switch (type) {
      case AdminBadgeType.trial: return AdminTheme.infoLight;
      case AdminBadgeType.active: return AdminTheme.successLight;
      case AdminBadgeType.gracePeriod: return AdminTheme.warningLight;
      case AdminBadgeType.suspended: return AdminTheme.orangeLight;
      case AdminBadgeType.disabled: return AdminTheme.dangerLight;
      case AdminBadgeType.custom: return AdminTheme.lightSurface;
    }
  }

  Color get _textColor {
    if (customColor != null) return customColor!;
    switch (type) {
      case AdminBadgeType.trial: return AdminTheme.info;
      case AdminBadgeType.active: return AdminTheme.success;
      case AdminBadgeType.gracePeriod: return AdminTheme.warning;
      case AdminBadgeType.suspended: return AdminTheme.orange;
      case AdminBadgeType.disabled: return AdminTheme.danger;
      case AdminBadgeType.custom: return AdminTheme.textSecondary;
    }
  }

  IconData get _icon {
    switch (type) {
      case AdminBadgeType.trial: return Icons.hourglass_top_rounded;
      case AdminBadgeType.active: return Icons.check_circle_outline_rounded;
      case AdminBadgeType.gracePeriod: return Icons.warning_amber_rounded;
      case AdminBadgeType.suspended: return Icons.pause_circle_outline_rounded;
      case AdminBadgeType.disabled: return Icons.block_rounded;
      case AdminBadgeType.custom: return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(AdminTheme.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: _textColor),
          const SizedBox(width: 5),
          Text(
            text,
            style: GoogleFonts.inter(
              color: _textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
