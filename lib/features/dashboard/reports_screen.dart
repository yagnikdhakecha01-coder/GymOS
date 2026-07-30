import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../members/members_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../finance/finance_viewmodel.dart';
import '../attendance/attendance_viewmodel.dart';
import 'report_detail_screen.dart';
import '../../core/theme/responsive.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);
    final financeVm = Provider.of<FinanceViewModel>(context);

    final reports = [
      _ReportItem(
        icon: Icons.trending_up,
        color: const Color(0xFF16A34A),
        title: 'Revenue Report',
        summary: '₹${financeVm.totalRevenue.toStringAsFixed(0)} total',
        type: 'revenue',
      ),
      _ReportItem(
        icon: Icons.trending_down,
        color: const Color(0xFFEF4444),
        title: 'Expense Report',
        summary: '₹${financeVm.totalExpense.toStringAsFixed(0)} total',
        type: 'expense',
      ),
      _ReportItem(
        icon: Icons.payment,
        color: const Color(0xFFF59E0B),
        title: 'Payment Report',
        summary: '₹${financeVm.totalPendingPayments.toStringAsFixed(0)} pending',
        type: 'payment',
      ),
      _ReportItem(
        icon: Icons.card_membership,
        color: const Color(0xFF8B5CF6),
        title: 'Membership Report',
        summary: '${membersVm.allMembers.length} members',
        type: 'membership',
      ),
      _ReportItem(
        icon: Icons.calendar_today,
        color: const Color(0xFF3B82F6),
        title: 'Attendance Report',
        summary: 'Daily tracking',
        type: 'attendance',
      ),
      _ReportItem(
        icon: Icons.people,
        color: const Color(0xFF0EA5E9),
        title: 'Staff Report',
        summary: '${staffVm.allStaff.length} staff members',
        type: 'staff',
      ),
      _ReportItem(
        icon: Icons.show_chart,
        color: const Color(0xFF10B981),
        title: 'Member Growth',
        summary: 'Growth analytics',
        type: 'growth',
      ),
      _ReportItem(
        icon: Icons.fitness_center,
        color: const Color(0xFF7C3AED),
        title: 'Workout Report',
        summary: 'Plan assignments',
        type: 'workout',
      ),
      _ReportItem(
        icon: Icons.restaurant_menu,
        color: const Color(0xFFEC4899),
        title: 'Diet Report',
        summary: 'Plan assignments',
        type: 'diet',
      ),
      _ReportItem(
        icon: Icons.sports_martial_arts,
        color: const Color(0xFFF97316),
        title: 'PT Report',
        summary: '${membersVm.allMembers.where((m) => m.ptMember).length} PT members',
        type: 'pt',
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Reports', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards row
            Row(
              children: [
                Expanded(
                  child: _summaryCard(
                    'Total Revenue',
                    '₹${financeVm.totalRevenue.toStringAsFixed(0)}',
                    Icons.arrow_upward,
                    AppTheme.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _summaryCard(
                    'Total Expense',
                    '₹${financeVm.totalExpense.toStringAsFixed(0)}',
                    Icons.arrow_downward,
                    AppTheme.danger,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _summaryCard(
                    'Net Profit',
                    '₹${financeVm.totalProfit.toStringAsFixed(0)}',
                    Icons.account_balance_wallet,
                    AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Text('ALL REPORTS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
            const SizedBox(height: 10),

            ResponsiveGrid(
              crossAxisCountMobile: 2,
              crossAxisCountTablet: 4,
              spacing: 10,
              runSpacing: 10,
              childAspectRatio: context.selectValue(mobile: 1.35, smallMobile: 1.15, tablet: 1.6),
              children: List.generate(reports.length, (index) {
                final report = reports[index];
                return _reportCard(context, report);
              }),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 2),
          Text(title, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _reportCard(BuildContext context, _ReportItem report) {
    return CustomCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReportDetailScreen(reportType: report.type, reportTitle: report.title)),
          );
        },
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: report.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(report.icon, size: 20, color: report.color),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(report.summary, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportItem {
  final IconData icon;
  final Color color;
  final String title;
  final String summary;
  final String type;

  _ReportItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.summary,
    required this.type,
  });
}
