import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import 'attendance_viewmodel.dart';
import 'owner_history_screen.dart';
import 'owner_settings_screen.dart';
import 'manual_attendance_screen.dart';
import 'emergency_attendance_hub_screen.dart';
import '../gym_settings/online_database_screen.dart';
import '../staff/staff_viewmodel.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<AttendanceViewModel>(context, listen: false).refresh();
        Provider.of<StaffViewModel>(context, listen: false).fetchStaff();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final attendanceVm = Provider.of<AttendanceViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);

    final totalStaff = staffVm.allStaff.where((s) => s.status == 'Active').length;
    final staffTodayRecords = attendanceVm.todayRecords.where((r) => r.userType == 'Staff').toList();
    final checkedIn = staffTodayRecords.length;
    final checkedOut = staffTodayRecords.where((r) => r.checkOutTime != null && r.checkOutTime!.isNotEmpty).length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Attendance',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Today's Summary ──
            Text(
              "Today's Summary",
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),

            // Horizontal stats card
            CustomCard(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              child: Row(
                children: [
                  _buildStat('Total Staff', '$totalStaff', AppTheme.textPrimary),
                  _verticalDivider(),
                  _buildStat('Checked In', '$checkedIn', const Color(0xFF16A34A)),
                  _verticalDivider(),
                  _buildStat('Checked Out', '$checkedOut', const Color(0xFFEF4444)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Menu Items ──
            _MenuItem(
              icon: Icons.badge_outlined,
              title: 'Staff Attendance',
              subtitle: 'View all staff today',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OwnerAttendanceHistoryScreen(userTypeFilter: 'Staff'),
                ),
              ),
            ),
            _MenuItem(
              icon: Icons.people_outline_rounded,
              title: 'Member Attendance',
              subtitle: 'View all members today',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OwnerAttendanceHistoryScreen(userTypeFilter: 'Member'),
                ),
              ),
            ),
            _MenuItem(
              icon: Icons.history_rounded,
              title: 'Attendance History',
              subtitle: 'View past records',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OwnerAttendanceHistoryScreen(userTypeFilter: 'All'),
                ),
              ),
            ),
            _MenuItem(
              icon: Icons.edit_calendar_rounded,
              title: 'Manual Attendance',
              subtitle: 'Mark attendance manually',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyAttendanceHubScreen())),
            ),
            _MenuItem(
              icon: Icons.cloud_sync_rounded,
              title: 'Online Database',
              subtitle: 'View sync queue & health',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineDatabaseScreen())),
            ),
            _MenuItem(
              icon: Icons.settings_outlined,
              title: 'Attendance Settings',
              subtitle: 'Manage QR & rules',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerQrSettingsScreen())),
            ),
            const SizedBox(height: 24),

            // ── How it works? Banner ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How it works?',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Scan the QR code displayed in the gym to mark Check In and Check Out for staff and members.',
                          style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.primary.withOpacity(0.75), height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(height: 40, width: 1, color: const Color(0xFFE5E7EB));
  }
}

// ── Menu Item Widget ──
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Icon(icon, color: AppTheme.textSecondary, size: 22),
        title: Text(
          title,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 22),
        onTap: onTap,
      ),
    );
  }
}
