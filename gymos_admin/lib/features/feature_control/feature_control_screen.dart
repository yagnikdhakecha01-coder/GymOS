import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/skeleton_loader.dart';

class FeatureControlScreen extends StatefulWidget {
  const FeatureControlScreen({super.key});
  @override
  State<FeatureControlScreen> createState() => _FeatureControlScreenState();
}

class _FeatureControlScreenState extends State<FeatureControlScreen> {
  bool _isLoading = true;
  final Map<String, bool> _flags = {
    for (var f in FeatureFlags.all) f: true,
  };

  @override
  void initState() {
    super.initState();
    // Simulate some disabled features
    _flags[FeatureFlags.aiDiet] = false;
    _flags[FeatureFlags.beaconAttendance] = false;
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _isLoading = false); });
  }

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
                  Text('Feature Control', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                  const SizedBox(height: 4),
                  Text('Enable or disable features remotely across all gyms', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                ]),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AdminTheme.successLight, borderRadius: BorderRadius.circular(AdminTheme.radiusXs)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AdminTheme.success)),
                    const SizedBox(width: 6),
                    Text('Changes sync instantly', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminTheme.success)),
                  ]),
                ),
              ]),
              const SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(
                  color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
                  border: Border.all(color: AdminTheme.borderColor(context)),
                ),
                child: Column(
                  children: FeatureFlags.all.asMap().entries.map((entry) {
                    final flag = entry.value;
                    final isLast = entry.key == FeatureFlags.all.length - 1;
                    return _buildFeatureToggle(context, flag, isLast);
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureToggle(BuildContext context, String flag, bool isLast) {
    final enabled = _flags[flag] ?? true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: AdminTheme.borderColor(context))),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: enabled
                  ? AdminTheme.primary.withValues(alpha: AdminTheme.isDark(context) ? 0.15 : 0.08)
                  : AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(AdminTheme.radiusMd),
            ),
            child: Icon(
              _getFeatureIcon(flag),
              size: 20,
              color: enabled ? AdminTheme.primary : AdminTheme.mutedTextColor(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(FeatureFlags.displayName(flag), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
                const SizedBox(height: 2),
                Text(FeatureFlags.description(flag), style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: enabled,
            onChanged: (v) {
              setState(() => _flags[flag] = v);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${FeatureFlags.displayName(flag)} ${v ? "enabled" : "disabled"}'),
                  backgroundColor: v ? AdminTheme.success : AdminTheme.orange,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _getFeatureIcon(String flag) {
    switch (flag) {
      case FeatureFlags.qrAttendance: return Icons.qr_code_scanner_rounded;
      case FeatureFlags.manualAttendance: return Icons.touch_app_rounded;
      case FeatureFlags.ptModule: return Icons.sports_gymnastics_rounded;
      case FeatureFlags.aiDiet: return Icons.restaurant_rounded;
      case FeatureFlags.aiWorkout: return Icons.fitness_center_rounded;
      case FeatureFlags.finance: return Icons.account_balance_wallet_rounded;
      case FeatureFlags.memberApp: return Icons.phone_android_rounded;
      case FeatureFlags.staffApp: return Icons.badge_rounded;
      case FeatureFlags.beaconAttendance: return Icons.bluetooth_rounded;
      case FeatureFlags.notifications: return Icons.notifications_rounded;
      default: return Icons.extension_rounded;
    }
  }
}
