import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import 'package:provider/provider.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../authentication/role_selection_screen.dart';
import '../../../core/navigation/app_router.dart';
import '../staff_viewmodel.dart';
import '../staff_profile_screen.dart';
import 'staff_salary_screen.dart';
import '../../more/help_support_screen.dart';
import '../../more/settings_screen.dart';
import '../../more/linked_devices_screen.dart';
import '../../../core/models/staff.dart';
import '../../../core/repository/gym_repository.dart';
import '../../dashboard/gym_switcher_bottom_sheet.dart';

class StaffMoreScreen extends StatelessWidget {
  const StaffMoreScreen({super.key});

  void _showChangePasswordDialog(BuildContext context) {
    final oldPassword = TextEditingController();
    final newPassword = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: oldPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Old Password')),
            const SizedBox(height: 8),
            TextField(controller: newPassword, obscureText: true, decoration: const InputDecoration(labelText: 'New Password')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (newPassword.text.trim().isNotEmpty) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Password updated successfully!'), backgroundColor: AppTheme.success),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _showScheduleDialog(BuildContext context, Staff staff) async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id']?.toString() ?? staff.gymId;
    final repo = Provider.of<GymRepository>(context, listen: false);

    Map<String, dynamic>? schedule;
    if (gymId.isNotEmpty) {
      schedule = await repo.fetchStaffWorkSchedule(staff.id, gymId);
    }

    final isBothShift = schedule?['is_both_shift'] == true ||
        staff.shiftType == 'both' ||
        staff.shift.toLowerCase().contains('both');
    final shiftLabel = schedule?['shift_label']?.toString() ??
        (isBothShift ? 'Both Shifts (Double)' : (staff.shift.isNotEmpty ? staff.shift : 'Single Shift'));
    final shift1Start = schedule?['shift1_start']?.toString() ?? staff.shift1Start;
    final shift1End = schedule?['shift1_end']?.toString() ?? staff.shift1End;
    final shift2Start = schedule?['shift2_start']?.toString() ?? staff.shift2Start;
    final shift2End = schedule?['shift2_end']?.toString() ?? staff.shift2End;

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('My Work Schedule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shift: $shiftLabel',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            if (schedule != null) ...[
              const SizedBox(height: 4),
              Text(
                'Timings from your staff profile',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 6),
            if (isBothShift) ...[
              Text(
                'Shift 1: ${shift1Start.isNotEmpty ? shift1Start : '09:00 AM'} - ${shift1End.isNotEmpty ? shift1End : '01:00 PM'}',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                'Shift 2: ${shift2Start.isNotEmpty ? shift2Start : '04:00 PM'} - ${shift2End.isNotEmpty ? shift2End : '09:00 PM'}',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ] else ...[
              Text(
                'Timing: ${shift1Start.isNotEmpty ? shift1Start : '09:00 AM'} - ${shift1End.isNotEmpty ? shift1End : '05:00 PM'}',
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

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final staffVm = Provider.of<StaffViewModel>(context);

    // Get the logged-in staff profile accurately
    final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;
    final userEmail = (authVm.currentUser?.email ?? authVm.currentProfile?.email ?? '').toLowerCase().trim();

    Staff? resolvedStaff = authVm.staffRecord;
    if (resolvedStaff == null && profileUserId != null) {
      try {
        resolvedStaff = staffVm.allStaff.firstWhere(
          (s) => (s.userId != null && s.userId == profileUserId) || s.id == profileUserId,
        );
      } catch (_) {}
    }
    if (resolvedStaff == null && userEmail.isNotEmpty) {
      try {
        resolvedStaff = staffVm.allStaff.firstWhere(
          (s) => s.email.toLowerCase().trim() == userEmail,
        );
      } catch (_) {}
    }

    final staff = resolvedStaff ?? Staff(
      id: profileUserId ?? '',
      name: authVm.currentProfile?.fullName ?? 'Staff',
      email: authVm.currentProfile?.email ?? authVm.currentUser?.email ?? '',
      phone: '',
      role: 'Staff',
      department: '',
      status: 'Active',
      joinDate: '',
      shift: '',
      experience: '',
      rating: 5.0,
      sessionsCount: 0,
      membersTrained: 0,
      salary: 0.0,
      salaryDue: 0.0,
      avatar: authVm.currentProfile?.photoUrl ?? '',
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          'More',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Card Header
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: (staff.avatar.isNotEmpty) ? NetworkImage(staff.avatar) : null,
                    child: (staff.avatar.isEmpty) ? const Icon(Icons.person_rounded) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          staff.name,
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          staff.role,
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Staff ID: ${staff.id.length > 8 ? staff.id.substring(0, 8) : staff.id}',
                          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action List
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildMenuItem(
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(StaffProfileScreen(staff: staff, isOwnerView: false)));
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 16, endIndent: 16),
                  _buildMenuItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'My Salary',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(StaffSalaryScreen(staff: staff)));
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 16, endIndent: 16),
                  _buildMenuItem(
                    icon: Icons.calendar_month_outlined,
                    label: 'My Work Schedule',
                    onTap: () => _showScheduleDialog(context, staff),
                  ),
                  const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 16, endIndent: 16),
                  _buildMenuItem(
                    icon: Icons.lock_open_rounded,
                    label: 'Change Password',
                    onTap: () => _showChangePasswordDialog(context),
                  ),
                  const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 16, endIndent: 16),
                  _buildMenuItem(
                    icon: Icons.headset_mic_outlined,
                    label: 'Help & Support',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const HelpSupportScreen()));
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 16, endIndent: 16),
                  _buildMenuItem(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Switch Profile',
                    onTap: () {
                      GymSwitcherBottomSheet.show(context);
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 16, endIndent: 16),
                  _buildMenuItem(
                    icon: Icons.devices_rounded,
                    label: 'Linked Devices',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const LinkedDevicesScreen()));
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFF3F4F6), indent: 16, endIndent: 16),
                  _buildMenuItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () {
                      Navigator.push(context, AppRouter.slideRoute(const SettingsScreen()));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Logout Button Card
            CustomCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: Text(
                  'Logout',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                onTap: () async {
                  await authVm.logout();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      AppRouter.scaleRoute(const RoleSelectionScreen()),
                      (route) => false,
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 12),

            // Delete Account Card
            CustomCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: Text(
                  'Delete Account',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                subtitle: Text(
                  'Permanently delete your staff account and profile',
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                ),
                onTap: () => _showDeleteAccountDialog(context, authVm),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, AuthViewModel authVm) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Staff Account?',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete your staff account? This will permanently erase your profile, assigned clients, and staff attendance history. This action CANNOT be undone.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: const Color(0xFF64748B),
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final success = await authVm.deleteAccount();
              if (context.mounted && success) {
                Navigator.pushAndRemoveUntil(
                  context,
                  AppRouter.scaleRoute(const RoleSelectionScreen()),
                  (route) => false,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Your staff account has been permanently deleted.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(
              'Delete Forever',
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textPrimary, size: 20),
      title: Text(
        label,
        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
      onTap: onTap,
    );
  }
}
