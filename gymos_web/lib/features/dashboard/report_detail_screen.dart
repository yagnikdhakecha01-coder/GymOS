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
import '../authentication/auth_viewmodel.dart';
import '../../core/services/supabase_service.dart';

class ReportDetailScreen extends StatefulWidget {
  final String reportType;
  final String reportTitle;

  const ReportDetailScreen({super.key, required this.reportType, required this.reportTitle});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  String _dateRange = 'This Month';
  Map<String, dynamic>? _trialStats;
  bool _loadingTrialStats = false;

  @override
  void initState() {
    super.initState();
    if (widget.reportType == 'trial') {
      _loadTrialStats();
    }
  }

  Future<void> _loadTrialStats() async {
    setState(() => _loadingTrialStats = true);
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId != null && SupabaseService.isInitialized) {
        final response = await SupabaseService.client.rpc(
          'get_trial_report_stats',
          params: {'p_gym_id': gymId},
        );
        if (mounted) {
          setState(() {
            _trialStats = Map<String, dynamic>.from(response as Map);
            _loadingTrialStats = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingTrialStats = false);
      }
    } catch (e) {
      print('Error loading trial stats: $e');
      if (mounted) {
        setState(() => _loadingTrialStats = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);
    final financeVm = Provider.of<FinanceViewModel>(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.reportTitle, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share, size: 20),
            onSelected: (val) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Exporting as $val...'), backgroundColor: AppTheme.primary),
              );
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'PDF', child: Row(children: [Icon(Icons.picture_as_pdf, size: 18, color: Colors.red), SizedBox(width: 8), Text('Export PDF')])),
              const PopupMenuItem(value: 'Excel', child: Row(children: [Icon(Icons.table_chart, size: 18, color: Colors.green), SizedBox(width: 8), Text('Export Excel')])),
              const PopupMenuItem(value: 'CSV', child: Row(children: [Icon(Icons.file_present, size: 18, color: Colors.blue), SizedBox(width: 8), Text('Export CSV')])),
              const PopupMenuItem(value: 'Print', child: Row(children: [Icon(Icons.print, size: 18, color: Colors.grey), SizedBox(width: 8), Text('Print')])),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date filter
            CustomCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _dateRange,
                        isExpanded: true,
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                        items: ['Today', 'This Week', 'This Month', 'Last 3 Months', 'Last 6 Months', 'This Year', 'All Time']
                            .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _dateRange = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Report-specific content
            _buildReportContent(membersVm, staffVm, financeVm),
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent(MembersViewModel membersVm, StaffViewModel staffVm, FinanceViewModel financeVm) {
    switch (widget.reportType) {
      case 'revenue':
        return _buildFinanceReport(financeVm, 'Revenue');
      case 'expense':
        return _buildFinanceReport(financeVm, 'Expense');
      case 'payment':
        return _buildPaymentReport(membersVm);
      case 'membership':
        return _buildMembershipReport(membersVm);
      case 'attendance':
        return _buildGenericReport('Attendance', Icons.calendar_today, [
          _StatRow('Total Check-ins Today', '24'),
          _StatRow('Average Daily', '18'),
          _StatRow('Peak Hour', '7:00 AM - 9:00 AM'),
          _StatRow('Lowest Hour', '2:00 PM - 4:00 PM'),
        ]);
      case 'staff':
        return _buildStaffReport(staffVm);
      case 'growth':
        return _buildGrowthReport(membersVm);
      case 'workout':
        return _buildGenericReport('Workout', Icons.fitness_center, [
          _StatRow('Total Plans', '${membersVm.allMembers.where((m) => m.assignedWorkoutId.isNotEmpty).length} assigned'),
          _StatRow('Most Popular', 'Full Body Strength'),
          _StatRow('Unassigned Members', '${membersVm.allMembers.where((m) => m.assignedWorkoutId.isEmpty).length}'),
        ]);
      case 'diet':
        return _buildGenericReport('Diet', Icons.restaurant_menu, [
          _StatRow('Total Plans', '${membersVm.allMembers.where((m) => m.assignedDietId.isNotEmpty).length} assigned'),
          _StatRow('Most Popular', 'High Protein Plan'),
          _StatRow('Unassigned Members', '${membersVm.allMembers.where((m) => m.assignedDietId.isEmpty).length}'),
        ]);
      case 'pt':
        return _buildPTReport(membersVm, staffVm);
      case 'trial':
        return _buildTrialReport(Provider.of<TrialMembersViewModel>(context));
      default:
        return const SizedBox();
    }
  }

  Widget _buildFinanceReport(FinanceViewModel financeVm, String type) {
    final transactions = financeVm.transactions.where((t) => t.type == type).toList();
    final total = transactions.fold<double>(0.0, (s, t) => s + t.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary cards
        Row(
          children: [
            Expanded(child: _statCard('Total $type', '₹${total.toStringAsFixed(0)}', type == 'Revenue' ? AppTheme.success : AppTheme.danger)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Transactions', '${transactions.length}', AppTheme.primary)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Average', transactions.isNotEmpty ? '₹${(total / transactions.length).toStringAsFixed(0)}' : '₹0', AppTheme.info)),
          ],
        ),
        const SizedBox(height: 16),

        Text('TRANSACTIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...transactions.map((t) => _transactionRow(t.title, t.date, '₹${t.amount.toStringAsFixed(0)}', t.category, type == 'Revenue' ? AppTheme.success : AppTheme.danger)),
        if (transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No $type transactions found', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted))),
          ),
      ],
    );
  }

  Widget _buildPaymentReport(MembersViewModel membersVm) {
    final pendingMembers = membersVm.allMembers.where((m) => m.pendingAmount > 0).toList();
    final totalPending = pendingMembers.fold<double>(0.0, (s, m) => s + m.pendingAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statCard('Total Pending', '₹${totalPending.toStringAsFixed(0)}', AppTheme.danger)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Members', '${pendingMembers.length}', AppTheme.warning)),
          ],
        ),
        const SizedBox(height: 16),
        Text('PENDING PAYMENTS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...pendingMembers.map((m) => _memberPaymentRow(m.name, '₹${m.pendingAmount.toStringAsFixed(0)}')),
        if (pendingMembers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('All payments are up to date!', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted))),
          ),
      ],
    );
  }

  Widget _buildMembershipReport(MembersViewModel membersVm) {
    final active = membersVm.allMembers.where((m) => m.status == 'Active').length;
    final inactive = membersVm.allMembers.where((m) => m.status == 'Inactive').length;
    final total = membersVm.allMembers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statCard('Total', '$total', AppTheme.primary)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Active', '$active', AppTheme.success)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Inactive', '$inactive', AppTheme.danger)),
          ],
        ),
        const SizedBox(height: 16),
        Text('MEMBER LIST', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...membersVm.allMembers.map((m) => _memberRow(m.name, m.status, m.joinDate)),
      ],
    );
  }

  Widget _buildStaffReport(StaffViewModel staffVm) {
    final active = staffVm.allStaff.where((s) => s.status == 'Active').length;
    final totalSalary = staffVm.allStaff.fold<double>(0.0, (s, st) => s + st.salary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statCard('Total Staff', '${staffVm.allStaff.length}', AppTheme.primary)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Active', '$active', AppTheme.success)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Total Salary', '₹${totalSalary.toStringAsFixed(0)}', AppTheme.warning)),
          ],
        ),
        const SizedBox(height: 16),
        Text('STAFF LIST', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...staffVm.allStaff.map((s) => _staffRow(s.name, s.role, '₹${s.salary.toStringAsFixed(0)}')),
      ],
    );
  }

  Widget _buildGrowthReport(MembersViewModel membersVm) {
    final total = membersVm.allMembers.length;
    final pt = membersVm.allMembers.where((m) => m.ptMember).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statCard('Total Members', '$total', AppTheme.primary)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('PT Members', '$pt', AppTheme.warning)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Growth', '+12%', AppTheme.success)),
          ],
        ),
        const SizedBox(height: 16),
        _buildGenericReport('Member Growth', Icons.show_chart, [
          _StatRow('This Month', '+5 new'),
          _StatRow('Last Month', '+8 new'),
          _StatRow('Retention Rate', '87%'),
          _StatRow('Churn Rate', '13%'),
        ]),
      ],
    );
  }

  Widget _buildPTReport(MembersViewModel membersVm, StaffViewModel staffVm) {
    final ptMembers = membersVm.allMembers.where((m) => m.ptMember).toList();
    final trainers = staffVm.allStaff.where((s) => s.role == 'Trainer').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statCard('PT Members', '${ptMembers.length}', AppTheme.primary)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Trainers', '${trainers.length}', AppTheme.warning)),
          ],
        ),
        const SizedBox(height: 16),
        Text('PT MEMBERS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...ptMembers.map((m) {
          final trainer = staffVm.allStaff.where((s) => s.id == m.ptTrainer).firstOrNull;
          return _ptMemberRow(m.name, trainer?.name ?? 'Unassigned');
        }),
        if (ptMembers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No PT members', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted))),
          ),
      ],
    );
  }

  Widget _buildGenericReport(String title, IconData icon, List<_StatRow> stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STATISTICS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: stats.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(s.label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                  Text(s.value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                ],
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _transactionRow(String title, String date, String amount, String category, Color amountColor) {
    return CustomCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: amountColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(amountColor == AppTheme.success ? Icons.arrow_downward : Icons.arrow_upward, size: 16, color: amountColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('$category • $date', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Text(amount, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: amountColor)),
        ],
      ),
    );
  }

  Widget _memberPaymentRow(String name, String pending) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: CustomCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: AppTheme.primaryLight, child: Text(name[0], style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary))),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
            Text(pending, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.danger)),
          ],
        ),
      ),
    );
  }

  Widget _memberRow(String name, String status, String date) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: CustomCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: AppTheme.primaryLight, child: Text(name[0], style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary))),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: status == 'Active' ? AppTheme.successLight : AppTheme.dangerLight, borderRadius: BorderRadius.circular(10)),
              child: Text(status, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: status == 'Active' ? AppTheme.success : AppTheme.danger)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _staffRow(String name, String role, String salary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: CustomCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: AppTheme.primaryLight, child: Text(name[0], style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(role, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            Text(salary, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _ptMemberRow(String memberName, String trainerName) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: CustomCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(radius: 16, backgroundColor: AppTheme.primaryLight, child: Text(memberName[0], style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(memberName, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('Trainer: $trainerName', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.sports_martial_arts, size: 18, color: AppTheme.warning),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildTrialReport(TrialMembersViewModel trialsVm) {
    if (_loadingTrialStats) {
      return const Center(child: CircularProgressIndicator());
    }

    final allTrials = trialsVm.allTrials;
    final stats = _trialStats ?? {
      'total': allTrials.length,
      'active': allTrials.where((t) => t.calculatedStatus == 'Active').length,
      'expired': allTrials.where((t) => t.calculatedStatus == 'Expired').length,
      'converted': allTrials.where((t) => t.calculatedStatus == 'Converted').length,
      'free': allTrials.where((t) => t.trialType == 'Free').length,
      'paid': allTrials.where((t) => t.trialType == 'Paid').length,
      'revenue': allTrials.where((t) => t.trialType == 'Paid').fold(0.0, (sum, t) => sum + t.receivedAmount),
    };

    final total = stats['total'] as int? ?? 0;
    final active = stats['active'] as int? ?? 0;
    final expired = stats['expired'] as int? ?? 0;
    final converted = stats['converted'] as int? ?? 0;
    final free = stats['free'] as int? ?? 0;
    final paid = stats['paid'] as int? ?? 0;
    final double revenue = (stats['revenue'] as num?)?.toDouble() ?? 0.0;
    
    final double conversionRate = total > 0 ? (converted / total) * 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statCard('Total Trials', '$total', AppTheme.primary)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Active', '$active', AppTheme.success)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Expired', '$expired', AppTheme.danger)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statCard('Converted', '$converted', const Color(0xFF8B5CF6))),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Revenue', '₹${revenue.toStringAsFixed(0)}', const Color(0xFFF59E0B))),
            const SizedBox(width: 10),
            Expanded(child: _statCard('Conv. Rate', '${conversionRate.toStringAsFixed(1)}%', Colors.teal)),
          ],
        ),
        const SizedBox(height: 16),

        Text('TRIAL STATS SUMMARY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildRow('Free Trials', '$free'),
              const Divider(height: 16),
              _buildRow('Paid Trials', '$paid'),
              const Divider(height: 16),
              _buildRow('Total Generated Revenue', '₹${revenue.toStringAsFixed(2)}'),
              const Divider(height: 16),
              _buildRow('Success Conversion Rate', '${conversionRate.toStringAsFixed(2)}%'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Text('TRIAL MEMBERS LIST', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 8),
        ...allTrials.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: CustomCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16, 
                  backgroundColor: AppTheme.primaryLight, 
                  backgroundImage: t.avatar.isNotEmpty ? NetworkImage(t.avatar) : null,
                  child: t.avatar.isEmpty ? Text(t.name[0], style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary)) : null
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(t.trialType == 'Paid' ? 'Paid Trial • ₹${t.receivedAmount.toStringAsFixed(0)}' : 'Free Trial', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  )
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.calculatedStatus == 'Converted' 
                        ? const Color(0xFFEEF2FF)
                        : (t.calculatedStatus == 'Expired' ? const Color(0xFFFEF2F2) : const Color(0xFFE6F4EA)), 
                    borderRadius: BorderRadius.circular(10)
                  ),
                  child: Text(
                    t.calculatedStatus, 
                    style: GoogleFonts.inter(
                      fontSize: 10, 
                      fontWeight: FontWeight.w600, 
                      color: t.calculatedStatus == 'Converted' 
                          ? const Color(0xFF4F46E5) 
                          : (t.calculatedStatus == 'Expired' ? const Color(0xFFEF4444) : const Color(0xFF16A34A))
                    )
                  ),
                ),
              ],
            ),
          ),
        )),
        if (allTrials.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No trial members found', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted))),
          ),
      ],
    );
  }
}

class _StatRow {
  final String label;
  final String value;
  _StatRow(this.label, this.value);
}
