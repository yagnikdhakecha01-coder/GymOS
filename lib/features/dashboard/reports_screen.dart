import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../members/members_viewmodel.dart';
import '../members/trial_members_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../finance/finance_viewmodel.dart';
import '../attendance/attendance_viewmodel.dart';
import 'report_detail_screen.dart';
import '../../core/theme/responsive.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/auth_viewmodel.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _reportStats;

  @override
  void initState() {
    super.initState();
    _loadReportStats();
  }

  Future<void> _loadReportStats() async {
    setState(() => _isLoading = true);
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId != null && SupabaseService.isInitialized) {
        final response = await SupabaseService.client.rpc(
          'get_all_reports_stats',
          params: {'p_gym_id': gymId},
        );
        if (mounted) {
          setState(() {
            _reportStats = Map<String, dynamic>.from(response as Map);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading report stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);
    final financeVm = Provider.of<FinanceViewModel>(context);
    final trialsVm = Provider.of<TrialMembersViewModel>(context);

    // Dynamic stats from database (using VM calculations as local fallback)
    final stats = _reportStats ?? {
      'revenue_total': financeVm.totalRevenue,
      'expense_total': financeVm.totalExpense,
      'pending_payments_total': financeVm.totalPendingPayments,
      'members_count': membersVm.allMembers.length,
      'staff_count': staffVm.allStaff.length,
      'pt_members_count': membersVm.allMembers.where((m) => m.ptMember).length,
      'trials_count': trialsVm.allTrials.length,
    };

    final double revenue = (stats['revenue_total'] as num?)?.toDouble() ?? 0.0;
    final double expense = (stats['expense_total'] as num?)?.toDouble() ?? 0.0;
    final double profit = revenue - expense;
    final double pendingPayments = (stats['pending_payments_total'] as num?)?.toDouble() ?? 0.0;
    final int membersCount = stats['members_count'] as int? ?? 0;
    final int staffCount = stats['staff_count'] as int? ?? 0;
    final int ptCount = stats['pt_members_count'] as int? ?? 0;
    final int trialsCount = stats['trials_count'] as int? ?? 0;

    final reports = [
      _ReportItem(
        icon: Icons.trending_up,
        color: const Color(0xFF16A34A),
        title: 'Revenue Report',
        summary: '₹${revenue.toStringAsFixed(0)} total',
        type: 'revenue',
      ),
      _ReportItem(
        icon: Icons.trending_down,
        color: const Color(0xFFEF4444),
        title: 'Expense Report',
        summary: '₹${expense.toStringAsFixed(0)} total',
        type: 'expense',
      ),
      _ReportItem(
        icon: Icons.payment,
        color: const Color(0xFFF59E0B),
        title: 'Payment Report',
        summary: '₹${pendingPayments.toStringAsFixed(0)} pending',
        type: 'payment',
      ),
      _ReportItem(
        icon: Icons.card_membership,
        color: const Color(0xFF8B5CF6),
        title: 'Membership Report',
        summary: '$membersCount members',
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
        summary: '$staffCount staff members',
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
        summary: '$ptCount PT members',
        type: 'pt',
      ),
      _ReportItem(
        icon: Icons.assignment_ind_outlined,
        color: Colors.deepOrange,
        title: 'Trial Member Report',
        summary: '$trialsCount trials',
        type: 'trial',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadReportStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReportStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                            '₹${revenue.toStringAsFixed(0)}',
                            Icons.arrow_upward,
                            AppTheme.success,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _summaryCard(
                            'Total Expense',
                            '₹${expense.toStringAsFixed(0)}',
                            Icons.arrow_downward,
                            AppTheme.danger,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _summaryCard(
                            'Net Profit',
                            '₹${profit.toStringAsFixed(0)}',
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
