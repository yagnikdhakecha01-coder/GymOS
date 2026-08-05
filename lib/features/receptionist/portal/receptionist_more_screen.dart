import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../authentication/role_selection_screen.dart';
import '../receptionist_viewmodel.dart';
import 'receptionist_activity_log_screen.dart';
import '../../members/trial_members_screen.dart';
import '../../more/holidays_screen.dart';
import '../../dashboard/gym_switcher_bottom_sheet.dart';
import '../../staff/portal/staff_requests_screen.dart';

class ReceptionistMoreScreen extends StatelessWidget {
  const ReceptionistMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final vm = Provider.of<ReceptionistViewModel>(context);
    final staff = vm.staffRecord;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'More',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // User Card
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(staff?.avatar ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=200'),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          staff?.name ?? 'Receptionist',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          staff?.phone ?? '9876543210',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // More Options Cards
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  _buildMenuRow(
                    icon: Icons.task_alt_rounded,
                    title: 'Tasks',
                    onTap: () {},
                  ),
                  _divider(),
                  _buildMenuRow(
                    icon: Icons.message_outlined,
                    title: 'Messages',
                    badge: '3',
                    onTap: () {},
                  ),
                  _divider(),
                  _buildMenuRow(
                    icon: Icons.history_edu_rounded,
                    title: 'Activity Log',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ReceptionistActivityLogScreen(gymId: vm.staffRecord!.gymId)),
                      );
                    },
                  ),
                  _divider(),
                  _buildMenuRow(
                    icon: Icons.post_add_rounded,
                    title: 'My Requests',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StaffRequestsScreen()),
                      );
                    },
                  ),
                  _divider(),
                  _buildMenuRow(
                    icon: Icons.event_busy_rounded,
                    title: 'Gym Holidays',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HolidaysScreen()),
                      );
                    },
                  ),
                  if (vm.hasPermission('add_member')) ...[
                    _divider(),
                    _buildMenuRow(
                      icon: Icons.assignment_ind_outlined,
                      title: 'Trial Members',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TrialMembersScreen()),
                        );
                      },
                    ),
                  ],
                  _divider(),
                  _buildMenuRow(
                    icon: Icons.swap_horiz_rounded,
                    title: 'Switch Profile',
                    onTap: () {
                      GymSwitcherBottomSheet.show(context);
                    },
                  ),
                  _divider(),
                  _buildMenuRow(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    onTap: () {},
                  ),
                  _divider(),
                  _buildMenuRow(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    onTap: () {},
                  ),
                  _divider(),
                  _buildMenuRow(
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    iconColor: Colors.redAccent,
                    textColor: Colors.redAccent,
                    onTap: () async {
                      await authVm.logout();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuRow({
    required IconData icon,
    required String title,
    String? badge,
    Color iconColor = AppTheme.primary,
    Color textColor = AppTheme.textPrimary,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                badge,
                style: GoogleFonts.inter(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.only(left: 56),
      child: Divider(height: 1, color: AppTheme.border),
    );
  }
}
