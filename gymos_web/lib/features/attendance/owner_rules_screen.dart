import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import 'attendance_viewmodel.dart';

class OwnerAttendanceRulesScreen extends StatelessWidget {
  const OwnerAttendanceRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<AttendanceViewModel>(context);

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
          'Attendance Rules',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Verification Rules ──
            Text(
              'Verification Rules',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF0F0F2)),
              ),
              child: Column(
                children: [
                  _ruleToggle(
                    title: 'WiFi Verification',
                    subtitle: 'Require Gym WiFi connection for QR scanning',
                    icon: Icons.wifi_rounded,
                    value: vm.isWiFiVerificationEnabled,
                    onChanged: (val) => vm.toggleWiFiVerification(val),
                  ),
                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF3F4F6)),
                  _ruleToggle(
                    title: 'Dynamic QR Code',
                    subtitle: 'Rotate QR codes to prevent screenshots',
                    icon: Icons.qr_code_2_rounded,
                    value: vm.isDynamicQrEnabled,
                    onChanged: (val) => vm.toggleDynamicQr(val),
                  ),
                  const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF3F4F6)),
                  _ruleToggle(
                    title: 'Manual Check-In',
                    subtitle: 'Allow owner to manually mark attendance',
                    icon: Icons.edit_note_rounded,
                    value: vm.isManualAttendanceEnabled,
                    onChanged: (val) => vm.toggleManualAttendance(val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Time Rules ──
            Text(
              'Time Settings',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF0F0F2)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _selectTime(context, vm),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.access_time_rounded, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Late Attendance Cutoff',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Mark as late if check-in after this time',
                              style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          vm.lateTimeSetting,
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleToggle({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: AppTheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _selectTime(BuildContext context, AttendanceViewModel vm) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 5),
    );
    if (picked != null) {
      final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      final formatted = '${hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')} $period';
      vm.setLateTimeSetting(formatted);
    }
  }
}
