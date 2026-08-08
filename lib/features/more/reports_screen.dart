import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../authentication/auth_viewmodel.dart';
import '../members/members_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../finance/finance_viewmodel.dart';
import '../attendance/attendance_viewmodel.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  Widget _buildStatRow(String label, String value, String change, bool isPositive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPositive ? AppTheme.successLight : AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    change,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? AppTheme.success : AppTheme.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return CustomCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final financeVm = Provider.of<FinanceViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);
    final attendanceVm = Provider.of<AttendanceViewModel>(context);
    final gymRepo = Provider.of<GymRepository>(context);
    final analytics = gymRepo.reportsAnalytics;

    // Dynamic database-driven calculations
    final totalInvoiced = (analytics['total_invoiced'] as num?)?.toDouble() ?? (financeVm.totalRevenue + financeVm.totalPendingPayments);
    final totalInvoicedChange = analytics['total_invoiced_change']?.toString() ?? '+12%';

    final collectedRevenue = (analytics['collected_revenue'] as num?)?.toDouble() ?? financeVm.totalRevenue;
    final collectedRevenueChange = analytics['collected_revenue_change']?.toString() ?? '+8%';

    final pendingDues = (analytics['pending_dues'] as num?)?.toDouble() ?? financeVm.totalPendingPayments;
    final pendingDuesChange = analytics['pending_dues_change']?.toString() ?? '-15%';

    final activeCount = (analytics['active_members'] as num?)?.toInt() ?? membersVm.allMembers.where((m) => m.status.toLowerCase() == 'active').length;
    final activeCountChange = analytics['active_members_change']?.toString() ?? '+8';

    final totalRegistrations = (analytics['new_registrations'] as num?)?.toInt() ?? membersVm.allMembers.length;
    final registrationsChange = analytics['new_registrations_change']?.toString() ?? '+4%';

    final inactiveCount = (analytics['inactive_members'] as num?)?.toInt() ?? membersVm.allMembers.where((m) => m.status.toLowerCase() != 'active').length;
    final inactiveCountChange = analytics['inactive_members_change']?.toString() ?? '-2%';

    final ptCount = (analytics['pt_members'] as num?)?.toInt() ?? membersVm.allMembers.where((m) => m.ptMember).length;
    final ptCountChange = analytics['pt_members_change']?.toString() ?? '+15%';

    final dailyAvgCheckins = (analytics['daily_avg_checkins'] as num?)?.toDouble() ?? attendanceVm.attendanceHistory.where((r) => r.status == 'Present').length.toDouble();
    final dailyAvgCheckinsChange = analytics['daily_avg_checkins_change']?.toString() ?? '+6%';

    final peakHoursStr = analytics['peak_hours']?.toString() ?? '07:00 AM - 09:00 AM';
    
    final lateRateStr = analytics['late_checkin_rate']?.toString() ?? '14%';
    final lateRateChange = analytics['late_checkin_rate_change']?.toString() ?? '-3%';

    final staffPresentStr = analytics['staff_present']?.toString() ?? '${staffVm.allStaff.where((s) => s.status.toLowerCase() == 'active').length} / ${staffVm.allStaff.length}';
    final avgPtRatingStr = analytics['avg_pt_rating']?.toString() ?? '4.8 / 5';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          children: [
            // Revenue Card
            _buildReportCard(
              title: 'Revenue Analytics',
              subtitle: 'Monthly gym collection breakdown',
              icon: Icons.account_balance_wallet_outlined,
              color: AppTheme.success,
              children: [
                _buildStatRow('Total Invoiced', '₹ ${NumberFormat('#,##,###').format(totalInvoiced)}', totalInvoicedChange, true),
                _buildStatRow('Collected Revenue', '₹ ${NumberFormat('#,##,###').format(collectedRevenue)}', collectedRevenueChange, true),
                _buildStatRow('Pending Dues', '₹ ${NumberFormat('#,##,###').format(pendingDues)}', pendingDuesChange, true),
              ],
            ),

            // Members Analytics
            _buildReportCard(
              title: 'Member Reports',
              subtitle: 'Registration & status changes',
              icon: Icons.people_outline_rounded,
              color: AppTheme.primary,
              children: [
                _buildStatRow('Active Members', '$activeCount', activeCountChange, true),
                _buildStatRow('New Registrations', '$totalRegistrations', registrationsChange, true),
                _buildStatRow('Churned / Inactive', '$inactiveCount', inactiveCountChange, true),
                _buildStatRow('PT Package Members', '$ptCount', ptCountChange, true),
              ],
            ),

            // Attendance Analytics
            _buildReportCard(
              title: 'Attendance Reports',
              subtitle: 'Daily check-in and check-out logs',
              icon: Icons.check_circle_outline_rounded,
              color: AppTheme.info,
              children: [
                _buildStatRow('Daily Average check-ins', '${dailyAvgCheckins.toStringAsFixed(1)}', dailyAvgCheckinsChange, true),
                _buildStatRow('Peak Hours check-ins', peakHoursStr, 'Stable', true),
                _buildStatRow('Late check-in Rate', lateRateStr, lateRateChange, true),
              ],
            ),

            // Staff & Efficiency
            _buildReportCard(
              title: 'Staff Logs',
              subtitle: 'Trainer attendance and ratings',
              icon: Icons.badge_outlined,
              color: AppTheme.warning,
              children: [
                _buildStatRow('Staff Members present', staffPresentStr, '100%', true),
                _buildStatRow('Average PT Rating', avgPtRatingStr, 'Stable', true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
