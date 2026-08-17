import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/services/gym_logo_cache_service.dart';
import '../authentication/auth_viewmodel.dart';
import '../authentication/role_selection_screen.dart';
import '../../core/navigation/app_router.dart';
import '../workout/workout_plans_screen.dart';
import '../diet/diet_plans_screen.dart';
import '../membership/membership_plans_screen.dart';
import '../gym_settings/gym_settings_menu_screen.dart';
import 'reports_screen.dart';
import '../members/trial_members_screen.dart';
import 'holidays_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'help_support_screen.dart';
import 'about_gymos_screen.dart';
import 'backup_restore_screen.dart';
import '../receptionist/portal/receptionist_activity_log_screen.dart';
import '../dashboard/gym_switcher_bottom_sheet.dart';

import '../subscription/owner_subscription_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<AuthViewModel>(context, listen: false).fetchSubscriptionStatus();
      }
    });
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: AppTheme.iconContainerSize,
        height: AppTheme.iconContainerSize,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusIconContainer),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final gym = authVm.gymInfo ?? {};
    final subInfo = authVm.subscriptionInfo;
    
    final gymName = gym['name']?.toString().trim() ?? 'GYMOS';
    final logoUrl = gym['logo'] ?? gym['logo_url'] ?? '';

    // Plan name format (e.g. 'free_trial' -> 'Free Trial', 'pro' -> 'Pro')
    String rawPlan = (subInfo?['plan'] ?? gym['plan'] ?? 'Free Trial').toString();
    String planDisplay = rawPlan
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
    if (planDisplay.isEmpty) planDisplay = 'Free Trial';

    // Validity date from database
    String validityDisplay = '';
    final dynamic rawExpiry = subInfo?['expiry_date'] ?? gym['expiry_date'] ?? gym['trial_end_date'] ?? gym['validUntil'];
    if (rawExpiry != null) {
      final DateTime? parsed = rawExpiry is DateTime ? rawExpiry : DateTime.tryParse(rawExpiry.toString());
      if (parsed != null) {
        validityDisplay = DateFormat('dd MMM yyyy').format(parsed);
      }
    }
    if (validityDisplay.isEmpty) {
      final daysLeft = subInfo?['days_left'] as int?;
      if (daysLeft != null && daysLeft > 0) {
        validityDisplay = DateFormat('dd MMM yyyy').format(DateTime.now().add(Duration(days: daysLeft)));
      } else {
        validityDisplay = 'Active';
      }
    }

    final bool hasValidLogo = logoUrl != null && logoUrl.toString().trim().isNotEmpty && logoUrl.toString().startsWith('http');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('More'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined),
            onPressed: () {
              Navigator.push(context, AppRouter.slideRoute(const NotificationsScreen()));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 12),
          children: [
            // Gym Profile Banner
            CustomCard(
              padding: const EdgeInsets.all(16),
              onTap: () {
                Navigator.push(context, AppRouter.slideRoute(const OwnerSubscriptionScreen()));
              },
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      final gymId = authVm.activeAssociation?.gymId ?? gym['id']?.toString();
                      final logoStr = logoUrl?.toString().trim() ?? '';
                      final cachedBase64 = GymLogoCacheService.getCachedLogoBase64(authVm.storage, gymId, logoStr);

                      ImageProvider? imageProvider;
                      if (cachedBase64 != null && cachedBase64.isNotEmpty) {
                        try {
                          imageProvider = MemoryImage(base64Decode(cachedBase64));
                        } catch (_) {}
                      } else if (hasValidLogo) {
                        imageProvider = NetworkImage(logoStr);
                      }

                      return Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(12),
                          image: imageProvider != null
                              ? DecorationImage(
                                  image: imageProvider,
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: imageProvider == null
                            ? Center(
                                child: Text(
                                  gymName.isNotEmpty ? gymName[0].toUpperCase() : 'G',
                                  style: GoogleFonts.inter(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                gymName,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                authVm.selectedRole ?? 'Owner',
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$planDisplay • Valid till $validityDisplay',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Premium Settings List
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // 1. Gym Settings ⭐ (First Item)
                  _buildSettingTile(
                    context,
                    icon: Icons.business_rounded,
                    color: AppTheme.primary,
                    title: 'Gym Settings',
                    subtitle: 'Configure gym profile, goals, form builder',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const GymSettingsMenuScreen()));
                    },
                  ),
                  const Divider(height: 1),

                  // Subscription & Billing (Owner only)
                  if (authVm.selectedRole?.toLowerCase() == 'owner') ...[
                    _buildSettingTile(
                      context,
                      icon: Icons.card_membership_rounded,
                      color: AppTheme.primary,
                      title: 'Subscription & Billing',
                      subtitle: 'Manage your GymOS plan, usage, invoices',
                      onTap: () {
                        Navigator.push(context, AppRouter.slideRoute(const OwnerSubscriptionScreen()));
                      },
                    ),
                    const Divider(height: 1),
                  ],

                  // Switch Profile Item
                  _buildSettingTile(
                    context,
                    icon: Icons.swap_horiz_rounded,
                    color: AppTheme.warning,
                    title: 'Switch Profile',
                    subtitle: 'Switch role or gym profile context',
                    onTap: () {
                      GymSwitcherBottomSheet.show(context);
                    },
                  ),
                  const Divider(height: 1),

                  // 5. Reports
                  _buildSettingTile(
                    context,
                    icon: Icons.analytics_outlined,
                    color: AppTheme.info,
                    title: 'Reports & Analytics',
                    subtitle: 'Track revenues, members, attendance',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const ReportsScreen()));
                    },
                  ),
                  const Divider(height: 1),



                  // 7. Backup & Restore (Future)
                  _buildSettingTile(
                    context,
                    icon: Icons.backup_outlined,
                    color: Colors.teal,
                    title: 'Backup & Restore',
                    subtitle: 'Backup database to cloud & local storage',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const BackupRestoreScreen()));
                    },
                  ),
                  const Divider(height: 1),

                  // 8. Settings
                  _buildSettingTile(
                    context,
                    icon: Icons.settings_outlined,
                    color: Colors.blueGrey,
                    title: 'General Settings',
                    subtitle: 'Biometrics, push notifications, preferences',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const SettingsScreen()));
                    },
                  ),
                  const Divider(height: 1),

                  // 9. Help & Support
                  _buildSettingTile(
                    context,
                    icon: Icons.headset_mic_outlined,
                    color: Colors.indigo,
                    title: 'Help & Support',
                    subtitle: 'Frequently Asked Questions & support team',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const HelpSupportScreen()));
                    },
                  ),
                  const Divider(height: 1),

                  // 10. About GymOS
                  _buildSettingTile(
                    context,
                    icon: Icons.info_outline_rounded,
                    color: Colors.deepPurple,
                    title: 'About GymOS',
                    subtitle: 'App version, licensing, terms',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const AboutGymOSScreen()));
                    },
                  ),
                  const Divider(height: 1),

                  // Logout
                  _buildSettingTile(
                    context,
                    icon: Icons.logout_rounded,
                    color: AppTheme.danger,
                    title: 'Logout',
                    subtitle: 'Sign out from GymOS',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Confirm Logout'),
                          content: const Text('Are you sure you want to sign out from GymOS?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                              onPressed: () async {
                                await authVm.logout();
                                if (context.mounted) {
                                  Navigator.pop(context); // Close dialog
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    AppRouter.scaleRoute(const RoleSelectionScreen()),
                                    (route) => false,
                                  );
                                }
                              },
                              child: const Text('Logout'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
