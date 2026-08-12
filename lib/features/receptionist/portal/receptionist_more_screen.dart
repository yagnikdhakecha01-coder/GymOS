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
import '../../dashboard/support_tickets_screen.dart';

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
                    icon: Icons.calendar_month_outlined,
                    title: 'My Work Schedule',
                    onTap: () {
                      if (staff != null) {
                        _showScheduleDialog(context, staff);
                      }
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
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SupportTicketsScreen()),
                      );
                    },
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

  Widget _dayScheduleRow(String days, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(days, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          Text(status, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: status.contains('Off') ? Colors.red : AppTheme.primary)),
        ],
      ),
    );
  }

  void _showScheduleDialog(BuildContext context, dynamic staff) {
    final isBothShift = staff.shiftType == 'both' || staff.shift.toLowerCase().contains('both');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('My Work Schedule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shift: ${isBothShift ? 'Both Shifts (Double)' : (staff.shift.isNotEmpty ? staff.shift : 'Single Shift')}',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            if (isBothShift) ...[
              Text(
                'Shift 1: ${staff.shift1Start.isNotEmpty ? staff.shift1Start : '09:00 AM'} - ${staff.shift1End.isNotEmpty ? staff.shift1End : '05:00 PM'}',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                'Shift 2: ${staff.shift2Start.isNotEmpty ? staff.shift2Start : '04:00 PM'} - ${staff.shift2End.isNotEmpty ? staff.shift2End : '09:00 PM'}',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ] else ...[
              Text(
                'Timing: ${staff.shift1Start.isNotEmpty ? staff.shift1Start : '09:00 AM'} - ${staff.shift1End.isNotEmpty ? staff.shift1End : '05:00 PM'}',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
            const Divider(height: 20),
            _dayScheduleRow('Mon - Fri', 'Active'),
            _dayScheduleRow('Saturday', 'Active'),
            _dayScheduleRow('Sunday', 'Weekly Off'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
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
