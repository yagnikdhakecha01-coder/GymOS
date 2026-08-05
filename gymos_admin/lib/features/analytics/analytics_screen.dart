import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/chart_card.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;

  // Chart Data Spots
  List<FlSpot> _activeUsersSpots = [];
  List<double> _newGymsValues = [];
  List<FlSpot> _revenueSpots = [];
  List<FlSpot> _trialConversionSpots = [];
  List<double> _attendanceValues = [];
  List<FlSpot> _growthRateSpots = [];

  // Plan distribution metrics
  double _starterPct = 0;
  double _proPct = 0;
  double _businessPct = 0;
  double _trialPct = 0;
  int _starterCount = 0;
  int _proCount = 0;
  int _businessCount = 0;
  int _trialCount = 0;

  // Month Labels for bottom axis
  List<String> _monthLabels = [];

  @override
  void initState() {
    super.initState();
    _fetchAnalyticsData();
  }

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return names[month - 1];
    return '';
  }

  Future<void> _fetchAnalyticsData() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      if (!AdminSupabaseService.isInitialized) {
        _setEmptyState();
        return;
      }
      final client = AdminSupabaseService.client;

      final now = DateTime.now();
      final labels = List<String>.generate(12, (_) => '');
      for (int i = 0; i < 12; i++) {
        final targetMonth = DateTime(now.year, now.month - (11 - i), 1);
        labels[i] = _getMonthName(targetMonth.month);
      }

      // 1. Fetch Gyms (Registrations, Growth, Plans)
      final gymsRes = await client.from('gyms').select('plan, status, created_at');
      final gymsList = gymsRes as List;

      final monthlyGymRegistrations = List<double>.generate(12, (_) => 0.0);
      final cumulativeGymCounts = List<double>.generate(12, (_) => 0.0);

      int starterCount = 0;
      int proCount = 0;
      int businessCount = 0;
      int trialCount = 0;

      for (var item in gymsList) {
        final gym = Map<String, dynamic>.from(item);
        final status = gym['status']?.toString();
        final plan = gym['plan']?.toString().toLowerCase() ?? '';
        final cAt = DateTime.tryParse(gym['created_at'] ?? '');

        // Plan distribution
        if (status == 'trial') {
          trialCount++;
        } else if (plan.contains('starter')) {
          starterCount++;
        } else if (plan.contains('pro')) {
          proCount++;
        } else if (plan.contains('business') || plan.contains('enterprise')) {
          businessCount++;
        } else {
          starterCount++;
        }

        // Registrations trend
        if (cAt != null) {
          final monthDiff = (now.year - cAt.year) * 12 + (now.month - cAt.month);
          if (monthDiff >= 0 && monthDiff < 12) {
            monthlyGymRegistrations[11 - monthDiff] += 1.0;
          }
        }
      }

      // Calculate cumulative gym count per month to find Growth Rate MoM
      double runningSum = 0;
      for (int i = 0; i < 12; i++) {
        runningSum += monthlyGymRegistrations[i];
        cumulativeGymCounts[i] = runningSum;
      }

      final List<FlSpot> growthRateSpots = [];
      for (int i = 0; i < 12; i++) {
        if (i == 0) {
          growthRateSpots.add(FlSpot(i.toDouble(), 0.0));
        } else {
          final prevVal = cumulativeGymCounts[i - 1];
          if (prevVal > 0) {
            final rate = ((cumulativeGymCounts[i] - prevVal) / prevVal) * 100;
            growthRateSpots.add(FlSpot(i.toDouble(), rate));
          } else {
            growthRateSpots.add(FlSpot(i.toDouble(), 0.0));
          }
        }
      }

      int totalPlans = starterCount + proCount + businessCount + trialCount;
      double starterPct = totalPlans > 0 ? (starterCount / totalPlans) * 100 : 0.0;
      double proPct = totalPlans > 0 ? (proCount / totalPlans) * 100 : 0.0;
      double businessPct = totalPlans > 0 ? (businessCount / totalPlans) * 100 : 0.0;
      double trialPct = totalPlans > 0 ? (trialCount / totalPlans) * 100 : 0.0;

      // 2. Fetch Payments (Revenue Trend, Conversion metrics)
      final monthlyRevenueTotals = List<double>.generate(12, (_) => 0.0);
      try {
        final paymentsRes = await client.from('payments').select('amount, status, created_at');
        for (var item in paymentsRes as List) {
          if (item['status'] == 'Success') {
            final amt = double.tryParse(item['amount'].toString()) ?? 0.0;
            final cAt = DateTime.tryParse(item['created_at'] ?? '');
            if (cAt != null) {
              final monthDiff = (now.year - cAt.year) * 12 + (now.month - cAt.month);
              if (monthDiff >= 0 && monthDiff < 12) {
                monthlyRevenueTotals[11 - monthDiff] += amt;
              }
            }
          }
        }
      } catch (_) {}

      final List<FlSpot> revenueSpots = [];
      for (int i = 0; i < 12; i++) {
        revenueSpots.add(FlSpot(i.toDouble(), monthlyRevenueTotals[i]));
      }

      // Calculate conversion rate dynamically: Active / Total ratio per month
      final List<FlSpot> conversionSpots = [];
      for (int i = 0; i < 12; i++) {
        double rate = totalPlans > 0 ? ((starterCount + proCount + businessCount) / totalPlans) * 100 : 0.0;
        conversionSpots.add(FlSpot(i.toDouble(), rate));
      }

      // 3. Fetch Members (Active Users Trend over 12 months)
      final monthlyMemberSignups = List<double>.generate(12, (_) => 0.0);
      try {
        final membersRes = await client.from('members').select('created_at');
        for (var item in membersRes as List) {
          final cAt = DateTime.tryParse(item['created_at'] ?? '');
          if (cAt != null) {
            final monthDiff = (now.year - cAt.year) * 12 + (now.month - cAt.month);
            if (monthDiff >= 0 && monthDiff < 12) {
              monthlyMemberSignups[11 - monthDiff] += 1.0;
            }
          }
        }
      } catch (_) {}

      final List<FlSpot> activeUsersSpots = [];
      double runningMembers = 0;
      for (int i = 0; i < 12; i++) {
        runningMembers += monthlyMemberSignups[i];
        activeUsersSpots.add(FlSpot(i.toDouble(), runningMembers));
      }

      // 4. Fetch Attendance logs (Attendance Count monthly)
      final monthlyAttendanceCounts = List<double>.generate(12, (_) => 0.0);
      try {
        final attendanceRes = await client.from('attendance_logs').select('created_at');
        for (var item in attendanceRes as List) {
          final cAt = DateTime.tryParse(item['created_at'] ?? '');
          if (cAt != null) {
            final monthDiff = (now.year - cAt.year) * 12 + (now.month - cAt.month);
            if (monthDiff >= 0 && monthDiff < 12) {
              monthlyAttendanceCounts[11 - monthDiff] += 1.0;
            }
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _activeUsersSpots = activeUsersSpots;
          _newGymsValues = monthlyGymRegistrations;
          _revenueSpots = revenueSpots;
          _trialConversionSpots = conversionSpots;
          _attendanceValues = monthlyAttendanceCounts;
          _growthRateSpots = growthRateSpots;

          _starterPct = starterPct;
          _proPct = proPct;
          _businessPct = businessPct;
          _trialPct = trialPct;
          _starterCount = starterCount;
          _proCount = proCount;
          _businessCount = businessCount;
          _trialCount = trialCount;

          _monthLabels = labels;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      if (mounted) {
        _setEmptyState();
      }
    }
  }

  void _setEmptyState() {
    final now = DateTime.now();
    final labels = List<String>.generate(12, (_) => '');
    for (int i = 0; i < 12; i++) {
      final targetMonth = DateTime(now.year, now.month - (11 - i), 1);
      labels[i] = _getMonthName(targetMonth.month);
    }

    setState(() {
      _activeUsersSpots = List.generate(12, (i) => FlSpot(i.toDouble(), 0.0));
      _newGymsValues = List.generate(12, (_) => 0.0);
      _revenueSpots = List.generate(12, (i) => FlSpot(i.toDouble(), 0.0));
      _trialConversionSpots = List.generate(12, (i) => FlSpot(i.toDouble(), 0.0));
      _attendanceValues = List.generate(12, (_) => 0.0);
      _growthRateSpots = List.generate(12, (i) => FlSpot(i.toDouble(), 0.0));

      _starterPct = 0;
      _proPct = 0;
      _businessPct = 0;
      _trialPct = 0;
      _starterCount = 0;
      _proCount = 0;
      _businessCount = 0;
      _trialCount = 0;

      _monthLabels = labels;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 3));
    final isDesktop = AdminResponsive.isDesktop(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Analytics', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                      const SizedBox(height: 4),
                      Text('Platform-wide growth and conversion metrics from Database', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _fetchAnalyticsData,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Analytics',
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Row 1
              if (isDesktop) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _activeUsersChart()), const SizedBox(width: 16), Expanded(child: _newGymsChart()),
              ]) else ...[_activeUsersChart(), const SizedBox(height: 16), _newGymsChart()],
              const SizedBox(height: 16),
              // Row 2
              if (isDesktop) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _revenueChart()), const SizedBox(width: 16), Expanded(child: _trialConversionChart()),
              ]) else ...[_revenueChart(), const SizedBox(height: 16), _trialConversionChart()],
              const SizedBox(height: 16),
              // Row 3
              if (isDesktop) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _attendanceChart()), const SizedBox(width: 16), Expanded(child: _growthRateChart()),
              ]) else ...[_attendanceChart(), const SizedBox(height: 16), _growthRateChart()],
              const SizedBox(height: 16),
              _planDistributionChart(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeUsersChart() {
    double maxVal = 100.0;
    for (var s in _activeUsersSpots) {
      if (s.y > maxVal) maxVal = s.y;
    }
    return ChartCard(title: 'Total Active Users', subtitle: 'Cumulative user signups trend', chart: AdminLineChart(
      spots: _activeUsersSpots,
      bottomLabels: _monthLabels,
      maxY: maxVal * 1.1,
      color: AdminTheme.primary,
    ));
  }

  Widget _newGymsChart() {
    return ChartCard(title: 'New Gym Registrations', subtitle: 'Monthly new gym signups', chart: AdminBarChart(
      values: _newGymsValues,
      labels: _monthLabels,
      color: AdminTheme.teal,
    ));
  }

  Widget _revenueChart() {
    double maxVal = 1000.0;
    for (var s in _revenueSpots) {
      if (s.y > maxVal) maxVal = s.y;
    }
    return ChartCard(title: 'Revenue Growth', subtitle: 'Monthly platform revenue in ₹', chart: AdminLineChart(
      spots: _revenueSpots,
      bottomLabels: _monthLabels,
      maxY: maxVal * 1.1,
      color: AdminTheme.success,
    ));
  }

  Widget _trialConversionChart() {
    return ChartCard(title: 'Trial to Paid Conversion', subtitle: 'Paid vs Trial conversion rate %', chart: AdminLineChart(
      spots: _trialConversionSpots,
      bottomLabels: _monthLabels,
      maxY: 105,
      color: AdminTheme.orange,
    ));
  }

  Widget _attendanceChart() {
    return ChartCard(title: 'Attendance Count', subtitle: 'Total monthly attendance check-ins', chart: AdminBarChart(
      values: _attendanceValues,
      labels: _monthLabels,
      color: AdminTheme.info,
    ));
  }

  Widget _growthRateChart() {
    double maxVal = 10.0;
    for (var s in _growthRateSpots) {
      if (s.y > maxVal) maxVal = s.y;
    }
    return ChartCard(title: 'Growth Rate', subtitle: 'Month-over-month cumulative growth %', chart: AdminLineChart(
      spots: _growthRateSpots,
      bottomLabels: _monthLabels,
      maxY: maxVal * 1.1,
      color: AdminTheme.pink,
    ));
  }

  List<DonutChartSection> _buildDonutSections() {
    List<DonutChartSection> list = [];
    if (_starterCount > 0) {
      list.add(DonutChartSection(value: _starterPct, color: AdminTheme.primary, label: 'Starter'));
    }
    if (_proCount > 0) {
      list.add(DonutChartSection(value: _proPct, color: AdminTheme.info, label: 'Pro'));
    }
    if (_businessCount > 0) {
      list.add(DonutChartSection(value: _businessPct, color: AdminTheme.success, label: 'Business'));
    }
    if (_trialCount > 0) {
      list.add(DonutChartSection(value: _trialPct, color: AdminTheme.warning, label: 'Trial'));
    }

    if (list.isEmpty) {
      list.add(const DonutChartSection(value: 100, color: Colors.grey, label: 'No Data', showTitle: false));
    }
    return list;
  }

  Widget _planDistributionChart() {
    return ChartCard(title: 'Plan Distribution', subtitle: 'Active gyms by subscription plan', height: 300, chart: Row(children: [
      Expanded(child: AdminDonutChart(
        sections: _buildDonutSections(), 
        centerRadius: 50,
      )),
      const SizedBox(width: 32),
      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _legend('Starter', AdminTheme.primary, '$_starterCount gyms (${_starterPct.toStringAsFixed(0)}%)'),
        const SizedBox(height: 8), _legend('Pro', AdminTheme.info, '$_proCount gyms (${_proPct.toStringAsFixed(0)}%)'),
        const SizedBox(height: 8), _legend('Business', AdminTheme.success, '$_businessCount gyms (${_businessPct.toStringAsFixed(0)}%)'),
        const SizedBox(height: 8), _legend('Trial', AdminTheme.warning, '$_trialCount gyms (${_trialPct.toStringAsFixed(0)}%)'),
      ]),
    ]));
  }

  Widget _legend(String label, Color color, String value) {
    return Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Text('$label  ', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
      Text(value, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
    ]);
  }
}
