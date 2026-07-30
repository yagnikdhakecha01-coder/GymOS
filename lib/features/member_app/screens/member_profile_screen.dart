import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../authentication/role_selection_screen.dart';
import '../../authentication/auth_viewmodel.dart';
import '../member_app_viewmodel.dart';
import 'member_membership_screen.dart';
import 'member_notifications_screen.dart';
import '../../more/help_support_screen.dart';
import '../../more/settings_screen.dart';

class MemberProfileScreen extends StatelessWidget {
  const MemberProfileScreen({super.key});

  void _showPersonalInfo(BuildContext context, MemberAppViewModel vm) {
    final displayId = vm.memberId.length > 8 ? vm.memberId.substring(0, 8) : vm.memberId;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Personal Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Name', vm.memberName),
            _detailRow('Member ID', displayId),
            _detailRow('Gym Name', vm.gymName),
            _detailRow('Goal', vm.fitnessGoal),
            _detailRow('Joined On', vm.membershipStartDate),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showBodyStatsDialog(BuildContext context, MemberAppViewModel vm) {
    final weightController = TextEditingController(text: vm.weight);
    final heightController = TextEditingController(text: vm.height);
    final fatController = TextEditingController(text: vm.bodyFat);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Body Stats'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: weightController, decoration: const InputDecoration(labelText: 'Weight (e.g. 76 kg)')),
            const SizedBox(height: 8),
            TextField(controller: heightController, decoration: const InputDecoration(labelText: 'Height (e.g. 178 cm)')),
            const SizedBox(height: 8),
            TextField(controller: fatController, decoration: const InputDecoration(labelText: 'Body Fat (e.g. 14.5%)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final success = await vm.updateBodyStats(
                weight: weightController.text,
                height: heightController.text,
                bodyFat: fatController.text,
              );
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Body stats updated successfully!'), backgroundColor: AppTheme.success),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('❌ Failed to update body stats.'), backgroundColor: AppTheme.danger),
                  );
                }
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showFitnessGoalDialog(BuildContext context, MemberAppViewModel vm) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Change Fitness Goal'),
        children: ['Lean Muscle Gain', 'Weight Loss', 'Weight Gain', 'General Fitness', 'Strength & Conditioning'].map((goal) {
          return SimpleDialogOption(
            onPressed: () {
              // Simulated update or trigger vm update if VM supports it
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✅ Fitness goal updated to $goal'), backgroundColor: AppTheme.success),
              );
              Navigator.pop(context);
            },
            child: Text(goal),
          );
        }).toList(),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Profile',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Consumer<MemberAppViewModel>(
        builder: (context, vm, _) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // ── Profile Avatar & Name (matching reference image 12) ──
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primary, width: 3),
                        ),
                        child: ClipOval(
                          child: vm.memberAvatar.startsWith('http')
                              ? Image.network(
                                  vm.memberAvatar,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppTheme.primaryLight,
                                    child: const Icon(Icons.person, color: AppTheme.primary, size: 44),
                                  ),
                                )
                              : Image.asset(
                                  'assets/images/member/avatar_default.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppTheme.primaryLight,
                                    child: const Icon(Icons.person, color: AppTheme.primary, size: 44),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        vm.memberName,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Member ID: ${vm.memberId.length > 8 ? vm.memberId.substring(0, 8) : vm.memberId}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Menu Items ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(Icons.person_outline_rounded, 'Personal Information', () {
                          _showPersonalInfo(context, vm);
                        }),
                        _divider(),
                        _buildMenuItem(Icons.monitor_weight_outlined, 'Body Stats', () {
                          _showBodyStatsDialog(context, vm);
                        }),
                        _divider(),
                        _buildMenuItem(Icons.track_changes_rounded, 'Fitness Goal: ${vm.fitnessGoal}', null),
                        _divider(),
                        _buildMenuItem(Icons.credit_card_rounded, 'My Membership', () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MemberMembershipScreen()),
                          );
                        }),
                        _divider(),
                        _buildMenuItem(Icons.settings_outlined, 'Settings', () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                        }),
                        _divider(),
                        _buildMenuItem(Icons.notifications_none_rounded, 'Notifications', () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MemberNotificationsScreen()),
                          );
                        }),
                        _divider(),
                        _buildMenuItem(Icons.headset_mic_outlined, 'Help & Support', () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Logout Button (Red, matching reference) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildMenuItem(
                      Icons.logout_rounded,
                      'Logout',
                      () async {
                        final authVm = Provider.of<AuthViewModel>(context, listen: false);
                        await vm.logout();
                        await authVm.logout();
                        if (context.mounted) {
                          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                            (route) => false,
                          );
                        }
                      },
                      color: AppTheme.danger,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _divider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 0.5,
      color: AppTheme.border,
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback? onTap, {Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color ?? AppTheme.textPrimary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color ?? AppTheme.textPrimary,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: color != null ? color.withValues(alpha: 0.5) : AppTheme.textMuted,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
