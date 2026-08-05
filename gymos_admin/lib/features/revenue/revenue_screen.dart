import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/chart_card.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';

class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key});
  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  bool _isLoading = true;
  String _period = 'monthly'; // 'daily', 'monthly', 'yearly'

  // Summary Metrics
  double _dailyRevenue = 0;
  double _weeklyRevenue = 0;
  double _monthlyRevenue = 0;
  double _yearlyRevenue = 0;
  double _totalRevenue = 0;
  int _failedCount = 0;
  double _failedAmount = 0;
  double _pendingAmount = 0;

  // Chart spots
  List<FlSpot> _spots = [];
  List<String> _chartLabels = [];

  // Recent transactions list
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _fetchRevenueData();
  }

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return names[month - 1];
    return '';
  }

  Future<void> _fetchRevenueData() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      if (!AdminSupabaseService.isInitialized) {
        _setEmptyState();
        return;
      }
      final client = AdminSupabaseService.client;

      // 1. Fetch successful and pending payments
      final response = await client
          .from('payments')
          .select('amount, status, payment_method, created_at, gyms(name, plan)')
          .order('created_at', ascending: false);

      final paymentsList = response as List;

      double daily = 0;
      double weekly = 0;
      double monthly = 0;
      double yearly = 0;
      double total = 0;
      int failedCount = 0;
      double failedAmount = 0;
      double pendingAmount = 0;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = now.subtract(const Duration(days: 7));

      for (var item in paymentsList) {
        final payment = Map<String, dynamic>.from(item);
        final amt = double.tryParse(payment['amount'].toString()) ?? 0.0;
        final status = payment['status']?.toString();
        final cAt = DateTime.tryParse(payment['created_at'] ?? '');

        if (status == 'Success' && cAt != null) {
          total += amt;
          
          if (cAt.isAfter(todayStart)) {
            daily += amt;
          }
          if (cAt.isAfter(weekStart)) {
            weekly += amt;
          }
          if (cAt.year == now.year && cAt.month == now.month) {
            monthly += amt;
          }
          if (cAt.year == now.year) {
            yearly += amt;
          }
        } else if (status == 'Failed') {
          failedCount++;
          failedAmount += amt;
        } else if (status == 'Pending') {
          pendingAmount += amt;
        }
      }

      // 2. Generate Chart Spots dynamically based on _period
      final List<FlSpot> spots = [];
      final List<String> labels = [];

      if (_period == 'daily') {
        // Last 15 days
        final dailyMap = <int, double>{};
        for (int i = 0; i < 15; i++) {
          dailyMap[i] = 0.0;
          final date = now.subtract(Duration(days: 14 - i));
          labels.add('${date.day}/${date.month}');
        }
        for (var item in paymentsList) {
          final payment = Map<String, dynamic>.from(item);
          final cAt = DateTime.tryParse(payment['created_at'] ?? '');
          if (payment['status'] == 'Success' && cAt != null) {
            final diffDays = now.difference(cAt).inDays;
            if (diffDays >= 0 && diffDays < 15) {
              dailyMap[14 - diffDays] = (dailyMap[14 - diffDays] ?? 0.0) + (double.tryParse(payment['amount'].toString()) ?? 0.0);
            }
          }
        }
        for (int i = 0; i < 15; i++) {
          spots.add(FlSpot(i.toDouble(), dailyMap[i] ?? 0.0));
        }
      } else if (_period == 'monthly') {
        // Last 12 months
        final monthlyMap = <int, double>{};
        for (int i = 0; i < 12; i++) {
          monthlyMap[i] = 0.0;
          final targetMonth = DateTime(now.year, now.month - (11 - i), 1);
          labels.add(_getMonthName(targetMonth.month));
        }
        for (var item in paymentsList) {
          final payment = Map<String, dynamic>.from(item);
          final cAt = DateTime.tryParse(payment['created_at'] ?? '');
          if (payment['status'] == 'Success' && cAt != null) {
            final monthDiff = (now.year - cAt.year) * 12 + (now.month - cAt.month);
            if (monthDiff >= 0 && monthDiff < 12) {
              monthlyMap[11 - monthDiff] = (monthlyMap[11 - monthDiff] ?? 0.0) + (double.tryParse(payment['amount'].toString()) ?? 0.0);
            }
          }
        }
        for (int i = 0; i < 12; i++) {
          spots.add(FlSpot(i.toDouble(), monthlyMap[i] ?? 0.0));
        }
      } else {
        // Last 5 years
        final yearlyMap = <int, double>{};
        for (int i = 0; i < 5; i++) {
          yearlyMap[i] = 0.0;
          labels.add((now.year - (4 - i)).toString());
        }
        for (var item in paymentsList) {
          final payment = Map<String, dynamic>.from(item);
          final cAt = DateTime.tryParse(payment['created_at'] ?? '');
          if (payment['status'] == 'Success' && cAt != null) {
            final yearDiff = now.year - cAt.year;
            if (yearDiff >= 0 && yearDiff < 5) {
              yearlyMap[4 - yearDiff] = (yearlyMap[4 - yearDiff] ?? 0.0) + (double.tryParse(payment['amount'].toString()) ?? 0.0);
            }
          }
        }
        for (int i = 0; i < 5; i++) {
          spots.add(FlSpot(i.toDouble(), yearlyMap[i] ?? 0.0));
        }
      }

      // 3. Format dynamic transactions table
      final List<Map<String, dynamic>> transactionItems = [];
      for (var item in paymentsList) {
        final payment = Map<String, dynamic>.from(item);
        final gymData = payment['gyms'];
        final gymName = (gymData != null) ? gymData['name'] : 'Active Gym';
        final planName = (gymData != null) ? gymData['plan'] : 'Starter';
        final cAt = DateTime.tryParse(payment['created_at'] ?? '') ?? DateTime.now();

        transactionItems.add({
          'gym': gymName,
          'amount': '₹${(double.tryParse(payment['amount'].toString()) ?? 0.0).toStringAsFixed(0)}',
          'plan': planName?.toString() ?? 'Starter',
          'status': payment['status'] ?? 'Success',
          'date': '${cAt.day} ${_getMonthName(cAt.month)} ${cAt.year}',
          'method': payment['payment_method'] ?? 'Razorpay',
        });
      }

      if (mounted) {
        setState(() {
          _dailyRevenue = daily;
          _weeklyRevenue = weekly;
          _monthlyRevenue = monthly;
          _yearlyRevenue = yearly;
          _totalRevenue = total;
          _failedCount = failedCount;
          _failedAmount = failedAmount;
          _pendingAmount = pendingAmount;

          _spots = spots;
          _chartLabels = labels;
          _transactions = transactionItems.take(15).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading revenue data: $e');
      if (mounted) {
        _setEmptyState();
      }
    }
  }

  void _setEmptyState() {
    setState(() {
      _dailyRevenue = 0;
      _weeklyRevenue = 0;
      _monthlyRevenue = 0;
      _yearlyRevenue = 0;
      _totalRevenue = 0;
      _failedCount = 0;
      _failedAmount = 0;
      _pendingAmount = 0;
      _spots = List.generate(12, (i) => FlSpot(i.toDouble(), 0.0));
      _chartLabels = List.generate(12, (_) => '');
      _transactions = [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable());

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              // Header
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Revenue Dashboard', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                      const SizedBox(height: 4),
                      Text('Financial overview and analytics from Database', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _fetchRevenueData,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Revenue',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Revenue stat cards
              _buildStatCards(context),
              const SizedBox(height: 24),
              // Revenue chart
              _buildRevenueChart(context),
              const SizedBox(height: 24),
              // Transactions table
              _buildTransactionsTable(context),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCurrency(double amt) {
    if (amt >= 100000) {
      return '₹${(amt / 100000).toStringAsFixed(1)}L';
    } else if (amt >= 1000) {
      return '₹${(amt / 1000).toStringAsFixed(1)}K';
    }
    return '₹${amt.toStringAsFixed(0)}';
  }

  Widget _buildStatCards(BuildContext context) {
    final cols = AdminResponsive.statCardColumns(context);
    final cards = [
      AdminStatCard(icon: Icons.today_rounded, iconColor: AdminTheme.info, value: _formatCurrency(_dailyRevenue), label: 'Daily Revenue'),
      AdminStatCard(icon: Icons.view_week_rounded, iconColor: AdminTheme.teal, value: _formatCurrency(_weeklyRevenue), label: 'Weekly Revenue'),
      AdminStatCard(icon: Icons.calendar_month_rounded, iconColor: AdminTheme.primary, value: _formatCurrency(_monthlyRevenue), label: 'Monthly Revenue'),
      AdminStatCard(icon: Icons.calendar_today_rounded, iconColor: AdminTheme.success, value: _formatCurrency(_yearlyRevenue), label: 'Yearly Revenue'),
      AdminStatCard(icon: Icons.account_balance_wallet_rounded, iconColor: AdminTheme.indigo, value: _formatCurrency(_totalRevenue), label: 'Total Revenue'),
      AdminStatCard(icon: Icons.error_outline_rounded, iconColor: AdminTheme.danger, value: _formatCurrency(_failedAmount), label: 'Failed Amount', change: '$_failedCount fail', isPositiveChange: false),
      AdminStatCard(icon: Icons.pending_outlined, iconColor: AdminTheme.warning, value: _formatCurrency(_pendingAmount), label: 'Pending Payments'),
      const AdminStatCard(icon: Icons.replay_rounded, iconColor: AdminTheme.orange, value: '₹0', label: 'Refunds'),
    ];
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = (constraints.maxWidth - (16.0 * (cols - 1))) / cols;
        return Wrap(spacing: 16, runSpacing: 16, children: cards.map((c) => SizedBox(width: w, child: c)).toList());
      },
    );
  }

  Widget _buildRevenueChart(BuildContext context) {
    double maxVal = 1000.0;
    for (var s in _spots) {
      if (s.y > maxVal) maxVal = s.y;
    }

    return ChartCard(
      title: 'Revenue Trend',
      subtitle: 'Revenue over chosen period from Database',
      height: 280,
      actions: [
        _PeriodChip(label: 'Daily', isActive: _period == 'daily', onTap: () {
          setState(() => _period = 'daily');
          _fetchRevenueData();
        }),
        _PeriodChip(label: 'Monthly', isActive: _period == 'monthly', onTap: () {
          setState(() => _period = 'monthly');
          _fetchRevenueData();
        }),
        _PeriodChip(label: 'Yearly', isActive: _period == 'yearly', onTap: () {
          setState(() => _period = 'yearly');
          _fetchRevenueData();
        }),
      ],
      chart: AdminLineChart(
        spots: _spots.isEmpty 
            ? List.generate(12, (i) => FlSpot(i.toDouble(), 0.0)) 
            : _spots,
        bottomLabels: _chartLabels,
        maxY: maxVal * 1.1,
        color: AdminTheme.success,
      ),
    );
  }

  Widget _buildTransactionsTable(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Recent Transactions', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          ),
          if (_transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('No transactions found in Database', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context))),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(AdminTheme.surfaceColor(context)),
                headingTextStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminTheme.secondaryTextColor(context)),
                dataTextStyle: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context)),
                columnSpacing: 24, horizontalMargin: 20,
                columns: const [
                  DataColumn(label: Text('GYM')), DataColumn(label: Text('AMOUNT')),
                  DataColumn(label: Text('PLAN')), DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('DATE')), DataColumn(label: Text('METHOD')),
                ],
                rows: _transactions.map((t) => DataRow(cells: [
                  DataCell(Text(t['gym'] as String, style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                  DataCell(Text(t['amount'] as String, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AdminTheme.success))),
                  DataCell(Text(t['plan'] as String)),
                  DataCell(_statusBadge(t['status'] as String)),
                  DataCell(Text(t['date'] as String)),
                  DataCell(Text(t['method'] as String)),
                ])).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color c;
    switch (status) {
      case 'Success': c = AdminTheme.success; break;
      case 'Failed': c = AdminTheme.danger; break;
      case 'Pending': c = AdminTheme.warning; break;
      default: c = AdminTheme.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(AdminTheme.radiusXs)),
      child: Text(status, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label; final bool isActive; final VoidCallback onTap;
  const _PeriodChip({required this.label, required this.isActive, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminTheme.radiusXs),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? AdminTheme.primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(AdminTheme.radiusXs),
          ),
          child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, color: isActive ? AdminTheme.primary : AdminTheme.mutedTextColor(context))),
        ),
      ),
    );
  }
}
