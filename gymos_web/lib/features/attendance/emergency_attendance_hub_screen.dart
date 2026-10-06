import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/repository/gym_repository.dart';
import 'emergency_member_attendance_screen.dart';
import 'emergency_staff_attendance_screen.dart';
import 'owner_attendance_correction_screen.dart';

/// Hub screen for Emergency Attendance Recovery System.
/// Accessible from: Settings → Attendance → Manual Attendance
class EmergencyAttendanceHubScreen extends StatelessWidget {
  const EmergencyAttendanceHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Provider.of<GymRepository>(context, listen: false);
    final role = repo.storage.getUserRole() ?? '';
    final isOwner = role.toLowerCase() == 'owner' || role.isEmpty;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Manual Attendance',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Emergency Notice Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFF7ED),
                    const Color(0xFFFEF3C7).withOpacity(0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Use Only',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use this only when QR attendance is unavailable. Records are saved offline and synced automatically when the server becomes available.',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: const Color(0xFFB45309),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Section: Emergency Manual Attendance
            Text(
              'Emergency Manual Attendance',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Mark attendance when server is unavailable',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),

            // Member Card
            _buildActionCard(
              context: context,
              icon: Icons.people_alt_rounded,
              iconBgColor: const Color(0xFFEDE9FE),
              iconColor: AppTheme.primary,
              title: 'Member Attendance',
              subtitle: 'Select multiple members and mark present',
              badgeText: 'Multi-Select',
              badgeColor: const Color(0xFFEDE9FE),
              badgeTextColor: AppTheme.primary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmergencyMemberAttendanceScreen()),
              ),
            ),
            const SizedBox(height: 12),

            // Staff Card
            _buildActionCard(
              context: context,
              icon: Icons.badge_rounded,
              iconBgColor: const Color(0xFFDBEAFE),
              iconColor: AppTheme.info,
              title: 'Staff Attendance',
              subtitle: 'Select staff, shift, and enter times',
              badgeText: 'Shift Support',
              badgeColor: const Color(0xFFDBEAFE),
              badgeTextColor: AppTheme.info,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmergencyStaffAttendanceScreen()),
              ),
            ),

            if (isOwner) ...[
              const SizedBox(height: 32),
              const Divider(color: Color(0xFFF3F4F6)),
              const SizedBox(height: 24),

              // Section: Attendance Correction
              Text(
                'Attendance Correction',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Correct past attendance records',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),

              _buildActionCard(
                context: context,
                icon: Icons.edit_note_rounded,
                iconBgColor: const Color(0xFFFEF3C7),
                iconColor: const Color(0xFFD97706),
                title: 'Correct Attendance',
                subtitle: 'Change status, times, or shift for any record',
                badgeText: 'Owner Only',
                badgeColor: const Color(0xFFFEE2E2),
                badgeTextColor: AppTheme.danger,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OwnerAttendanceCorrectionScreen()),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Sync Status
            Consumer<GymRepository>(
              builder: (context, repo, _) {
                final pendingCount = repo.manualAttendanceQueue
                    .where((e) => e.syncStatus == 'pending' || e.syncStatus == 'syncing')
                    .length;
                final failedCount = repo.manualAttendanceQueue
                    .where((e) => e.syncStatus == 'failed')
                    .length;

                if (pendingCount == 0 && failedCount == 0) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_done_rounded, color: Color(0xFF16A34A), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'All manual attendance records are synced',
                            style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF166534), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_sync_rounded, color: Color(0xFFD97706), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (pendingCount > 0)
                              Text(
                                '$pendingCount record${pendingCount > 1 ? 's' : ''} pending sync',
                                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF92400E), fontWeight: FontWeight.w600),
                              ),
                            if (failedCount > 0)
                              Padding(
                                padding: EdgeInsets.only(top: pendingCount > 0 ? 4 : 0),
                                child: Text(
                                  '$failedCount record${failedCount > 1 ? 's' : ''} failed — will retry',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.danger),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF0F0F2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeText,
                            style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: badgeTextColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
