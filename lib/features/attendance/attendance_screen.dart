import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import 'attendance_viewmodel.dart';
import 'owner_scanner_screen.dart';
import 'owner_history_screen.dart';
import 'owner_settings_screen.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                  _buildStat('Total Staff', '18', AppTheme.textPrimary),
                  _verticalDivider(),
                  _buildStat('Checked In', '14', const Color(0xFF16A34A)),
                  _verticalDivider(),
                  _buildStat('Checked Out', '6', const Color(0xFFEF4444)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Check In / Check Out Action Cards ──
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.login_rounded,
                    label: 'Check In',
                    subtitle: 'Scan QR Code',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerQRScannerScreen(isCheckIn: true)),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.logout_rounded,
                    label: 'Check Out',
                    subtitle: 'Scan QR Code',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OwnerQRScannerScreen(isCheckIn: false)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Menu Items ──
            _MenuItem(
              icon: Icons.badge_outlined,
              title: 'Staff Attendance',
              subtitle: 'View all staff today',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerAttendanceHistoryScreen())),
            ),
            _MenuItem(
              icon: Icons.people_outline_rounded,
              title: 'Member Attendance',
              subtitle: 'View all members today',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerAttendanceHistoryScreen())),
            ),
            _MenuItem(
              icon: Icons.history_rounded,
              title: 'Attendance History',
              subtitle: 'View past records',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerAttendanceHistoryScreen())),
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

// ── Action Card Widget ──
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
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
