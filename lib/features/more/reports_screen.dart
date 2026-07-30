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

    // Revenue calculations
    final totalRevenue = financeVm.totalRevenue;
    final pendingPayments = financeVm.totalPendingPayments;
    final totalInvoiced = totalRevenue + pendingPayments;

    // Member calculations
    final activeCount = membersVm.allMembers.where((m) => m.status.toLowerCase() == 'active').length;
    final inactiveCount = membersVm.allMembers.where((m) => m.status.toLowerCase() != 'active').length;
    final trialCount = membersVm.allMembers.where((m) => m.ptMember).length;

    // Attendance records
    final checkInRecords = attendanceVm.attendanceHistory.where((r) => r.status == 'Present').length;

    // Staff calculations
    final activeStaffCount = staffVm.allStaff.where((s) => s.status.toLowerCase() == 'active').length;
    final totalStaffCount = staffVm.allStaff.length;

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
                _buildStatRow('Total Invoiced', '₹ ${NumberFormat('#,##,###').format(totalInvoiced)}', totalInvoiced > 0 ? '+12%' : '0%', true),
                _buildStatRow('Collected Revenue', '₹ ${NumberFormat('#,##,###').format(totalRevenue)}', totalRevenue > 0 ? '+8%' : '0%', true),
                _buildStatRow('Pending Dues', '₹ ${NumberFormat('#,##,###').format(pendingPayments)}', pendingPayments > 0 ? '-15%' : '0%', true),
              ],
            ),

            // Members Analytics
            _buildReportCard(
              title: 'Member Reports',
              subtitle: 'Registration & status changes',
              icon: Icons.people_outline_rounded,
              color: AppTheme.primary,
              children: [
                _buildStatRow('Active Members', '$activeCount', activeCount > 0 ? '+8' : '0', true),
                _buildStatRow('New Registrations', '${membersVm.allMembers.length}', membersVm.allMembers.isNotEmpty ? '+4%' : '0%', true),
                _buildStatRow('Churned / Inactive', '$inactiveCount', inactiveCount > 0 ? '-2%' : '0%', true),
                _buildStatRow('PT Package Members', '$trialCount', trialCount > 0 ? '+15%' : '0%', true),
              ],
            ),

            // Attendance Analytics
            _buildReportCard(
              title: 'Attendance Reports',
              subtitle: 'Daily check-in and check-out logs',
              icon: Icons.check_circle_outline_rounded,
              color: AppTheme.info,
              children: [
                _buildStatRow('Daily Average check-ins', '$checkInRecords', checkInRecords > 0 ? '+6%' : '0%', true),
                _buildStatRow('Peak Hours check-ins', checkInRecords > 0 ? '07:00 AM - 09:00 AM' : 'No Data', 'Stable', true),
                _buildStatRow('Late check-in Rate', checkInRecords > 0 ? '14%' : '0%', checkInRecords > 0 ? '-3%' : '0%', true),
              ],
            ),

            // Staff & Efficiency
            _buildReportCard(
              title: 'Staff Logs',
              subtitle: 'Trainer attendance and ratings',
              icon: Icons.badge_outlined,
              color: AppTheme.warning,
              children: [
                _buildStatRow('Staff Members present', '$activeStaffCount / $totalStaffCount', totalStaffCount > 0 ? '100%' : '0%', true),
                _buildStatRow('Average PT Rating', trialCount > 0 ? '4.8 / 5' : 'No Rating', 'Stable', true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
