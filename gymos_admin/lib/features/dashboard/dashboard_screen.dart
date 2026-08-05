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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;

  int _totalGyms = 0;
  int _activeGyms = 0;
  int _trialGyms = 0;
  int _gracePeriodGyms = 0;
  int _suspendedGyms = 0;
  int _disabledGyms = 0;
  int _todayNewGyms = 0;
  double _monthlyRevenue = 0;
  double _totalRevenue = 0;
  int _activeMembers = 0;
  int _activeStaff = 0;
  String _latestAppVersion = '1.0.0';

  // Chart Data
  List<FlSpot> _revenueSpots = [];
  List<String> _revenueMonthLabels = [];
  List<double> _newGymsValues = [];
  List<String> _newGymsLabels = [];
  
  // Donut values
  double _starterPct = 0;
  double _proPct = 0;
  double _businessPct = 0;
  double _trialPct = 0;
  int _starterCount = 0;
  int _proCount = 0;
  int _businessCount = 0;
  int _trialCount = 0;

  // Activities list
  List<_ActivityItem> _activities = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return names[month - 1];
    return '';
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.isNegative) return 'Just now';
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dateTime.day} ${_getMonthName(dateTime.month)}';
  }

  Future<void> _fetchStats() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      if (!AdminSupabaseService.isInitialized) {
        _setEmptyState();
        return;
      }
      final client = AdminSupabaseService.client;

      // 1. Fetch Gyms
      final gymsRes = await client.from('gyms').select('status, created_at, plan, name');
      final gymsList = gymsRes as List;
      
      int total = gymsList.length;
      int active = 0;
      int trial = 0;
      int grace = 0;
      int suspended = 0;
      int disabled = 0;
      int todayNew = 0;
      
      final now = DateTime.now();
      final todayStr = now.toIso8601String().split('T')[0];
      
      // Donut variables
      int starterVal = 0;
      int proVal = 0;
      int businessVal = 0;
      int trialVal = 0;

      // Monthly new gym counts (last 12 months)
      final monthlyGymCounts = List<double>.generate(12, (_) => 0.0);
      final monthLabels = List<String>.generate(12, (_) => '');

      for (int i = 0; i < 12; i++) {
        final targetMonth = DateTime(now.year, now.month - (11 - i), 1);
        monthLabels[i] = _getMonthName(targetMonth.month);
      }

      for (var gym in gymsList) {
        final status = gym['status'];
        if (status == 'active') {
          active++;
        } else if (status == 'trial') {
          trial++;
        } else if (status == 'grace_period') {
          grace++;
        } else if (status == 'suspended') {
          suspended++;
        } else if (status == 'disabled') {
          disabled++;
        }
        
        // Count today's gyms
        final createdAtStr = gym['created_at'];
        if (createdAtStr != null && createdAtStr.toString().startsWith(todayStr)) {
          todayNew++;
        }

        // Plan distribution
        final plan = gym['plan']?.toString().toLowerCase() ?? '';
        if (status == 'trial') {
          trialVal++;
        } else if (plan.contains('starter')) {
          starterVal++;
        } else if (plan.contains('pro')) {
          proVal++;
        } else if (plan.contains('business') || plan.contains('enterprise')) {
          businessVal++;
        } else {
          starterVal++; // Default fallback for active gyms without explicit plan tags
        }

        // Populate dynamic bar chart
        if (createdAtStr != null) {
          final createdAt = DateTime.tryParse(createdAtStr);
          if (createdAt != null) {
            final monthDiff = (now.year - createdAt.year) * 12 + (now.month - createdAt.month);
            if (monthDiff >= 0 && monthDiff < 12) {
              monthlyGymCounts[11 - monthDiff] += 1.0;
            }
          }
        }
      }

      int totalChart = starterVal + proVal + businessVal + trialVal;
      double starterPct = totalChart > 0 ? (starterVal / totalChart) * 100 : 0.0;
      double proPct = totalChart > 0 ? (proVal / totalChart) * 100 : 0.0;
      double businessPct = totalChart > 0 ? (businessVal / totalChart) * 100 : 0.0;
      double trialPct = totalChart > 0 ? (trialVal / totalChart) * 100 : 0.0;

      // 2. Fetch Members
      final membersRes = await client.from('members').select('id');
      final membersCount = (membersRes as List).length;

      // 3. Fetch Staff
      final staffRes = await client.from('staff').select('id');
      final staffCount = (staffRes as List).length;

      // 4. Fetch Payments & Monthly Revenue
      double totalRev = 0;
      double monthlyRev = 0;
      final monthlyRevenueTotals = List<double>.generate(12, (_) => 0.0);

      try {
        final paymentsRes = await client.from('payments').select('amount, status, created_at');
        final paymentsList = paymentsRes as List;
        
        for (var p in paymentsList) {
          if (p['status'] == 'Success') {
            final amt = double.tryParse(p['amount'].toString()) ?? 0.0;
            totalRev += amt;
            
            final createdAt = DateTime.tryParse(p['created_at'] ?? '');
            if (createdAt != null) {
              if (createdAt.year == now.year && createdAt.month == now.month) {
                monthlyRev += amt;
              }
              
              final monthDiff = (now.year - createdAt.year) * 12 + (now.month - createdAt.month);
              if (monthDiff >= 0 && monthDiff < 12) {
                monthlyRevenueTotals[11 - monthDiff] += amt;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Payments query failed or empty: $e');
      }

      List<FlSpot> spots = [];
      for (int i = 0; i < 12; i++) {
        spots.add(FlSpot(i.toDouble(), monthlyRevenueTotals[i]));
      }

      // 5. Fetch Latest App Version
      String latestVersion = '1.0.0';
      try {
        final versionRes = await client
            .from('app_versions')
            .select('version_name')
            .eq('platform', 'android')
            .eq('status', 'published')
            .order('build_number', ascending: false)
            .limit(1);
        if ((versionRes as List).isNotEmpty) {
          latestVersion = versionRes.first['version_name'] ?? '1.0.0';
        }
      } catch (e) {
        debugPrint('App versions query failed: $e');
      }

      // 6. Build Recent Activity Feed Dynamically
      final List<_ActivityItem> loadedActivities = [];
      
      // Fetch latest 3 gyms
      try {
        final latestGyms = await client
            .from('gyms')
            .select('name, created_at')
            .order('created_at', ascending: false)
            .limit(3);
            
        for (var g in latestGyms as List) {
          final cAt = DateTime.tryParse(g['created_at'] ?? '');
          loadedActivities.add(_ActivityItem(
            icon: Icons.add_business_rounded,
            color: AdminTheme.success,
            title: 'New gym registered',
            subtitle: g['name'] ?? 'FitZone Gym',
            time: cAt != null ? _formatRelativeTime(cAt) : 'Just now',
            timestamp: cAt ?? DateTime.now(),
          ));
        }
      } catch (_) {}

      // Fetch latest 3 payments
      try {
        final latestPayments = await client
            .from('payments')
            .select('amount, created_at, status, gyms(name)')
            .eq('status', 'Success')
            .order('created_at', ascending: false)
            .limit(3);

        for (var p in latestPayments as List) {
          final cAt = DateTime.tryParse(p['created_at'] ?? '');
          final gymData = p['gyms'];
          final gymName = (gymData != null) ? gymData['name'] : 'Active Gym';
          final amt = double.tryParse(p['amount'].toString()) ?? 0.0;
          
          loadedActivities.add(_ActivityItem(
            icon: Icons.payment_rounded,
            color: AdminTheme.primary,
            title: 'Payment received',
            subtitle: '$gymName — ₹${amt.toStringAsFixed(0)} (Subscription)',
            time: cAt != null ? _formatRelativeTime(cAt) : 'Just now',
            timestamp: cAt ?? DateTime.now(),
          ));
        }
      } catch (_) {}

      // Sort activity feed by date descending
      loadedActivities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Limit to 6 items
      final finalActivities = loadedActivities.take(6).toList();

      if (mounted) {
        setState(() {
          _totalGyms = total;
          _activeGyms = active;
          _trialGyms = trial;
          _gracePeriodGyms = grace;
          _suspendedGyms = suspended;
          _disabledGyms = disabled;
          _todayNewGyms = todayNew;
          _activeMembers = membersCount;
          _activeStaff = staffCount;
          _totalRevenue = totalRev;
          _monthlyRevenue = monthlyRev;
          _latestAppVersion = latestVersion;
          
          _revenueSpots = spots;
          _revenueMonthLabels = monthLabels;
          _newGymsValues = monthlyGymCounts;
          _newGymsLabels = monthLabels;

          _starterPct = starterPct;
          _proPct = proPct;
          _businessPct = businessPct;
          _trialPct = trialPct;
          _starterCount = starterVal;
          _proCount = proVal;
          _businessCount = businessVal;
          _trialCount = trialVal;

          _activities = finalActivities;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      if (mounted) {
        _setEmptyState();
      }
    }
  }

  void _setEmptyState() {
    final now = DateTime.now();
    final monthLabels = List<String>.generate(12, (_) => '');
    for (int i = 0; i < 12; i++) {
      final targetMonth = DateTime(now.year, now.month - (11 - i), 1);
      monthLabels[i] = _getMonthName(targetMonth.month);
    }

    setState(() {
      _totalGyms = 0;
      _activeGyms = 0;
      _trialGyms = 0;
      _gracePeriodGyms = 0;
      _suspendedGyms = 0;
      _disabledGyms = 0;
      _todayNewGyms = 0;
      _monthlyRevenue = 0.0;
      _totalRevenue = 0.0;
      _activeMembers = 0;
      _activeStaff = 0;
      _latestAppVersion = '1.0.0';

      _revenueSpots = List.generate(12, (i) => FlSpot(i.toDouble(), 0.0));
      _revenueMonthLabels = monthLabels;
      _newGymsValues = List.generate(12, (_) => 0.0);
      _newGymsLabels = monthLabels;

      _starterPct = 0;
      _proPct = 0;
      _businessPct = 0;
      _trialPct = 0;
      _starterCount = 0;
      _proCount = 0;
      _businessCount = 0;
      _trialCount = 0;

      _activities = [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);

    if (_isLoading) {
      return _buildSkeletonView(padding);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 375),
            childAnimationBuilder: (widget) => SlideAnimation(
              verticalOffset: 30,
              child: FadeInAnimation(child: widget),
            ),
            children: [
              // Page header
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back, Admin 👋',
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AdminTheme.textColor(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Here\'s what\'s happening across your platform today.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AdminTheme.secondaryTextColor(context),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _buildRefreshButton(context),
                ],
              ),
              const SizedBox(height: 28),

              // ── Stat Cards Grid ──
              _buildStatCardsGrid(context),
              const SizedBox(height: 28),

              // ── Charts Row ──
              _buildChartsSection(context),
              const SizedBox(height: 28),

              // ── Bottom Section: Activity + Quick Stats ──
              _buildBottomSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _fetchStats,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Refresh'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        side: BorderSide(color: AdminTheme.borderColor(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
      ),
    );
  }

  Widget _buildStatCardsGrid(BuildContext context) {
    final columns = AdminResponsive.statCardColumns(context);
    final stats = _getStatCards();

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - (16.0 * (columns - 1))) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: stats.map((card) => SizedBox(width: itemWidth, child: card)).toList(),
        );
      },
    );
  }

  String _formatRevenue(double value) {
    if (value >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(1)}K';
    }
    return '₹${value.toStringAsFixed(0)}';
  }

  List<Widget> _getStatCards() {
    return [
      AdminStatCard(
        icon: Icons.fitness_center_rounded,
        iconColor: AdminTheme.primary,
        value: '$_totalGyms',
        label: 'Total Gyms',
        change: _totalGyms > 0 ? '+$_totalGyms' : '0',
        isPositiveChange: true,
      ),
      AdminStatCard(
        icon: Icons.check_circle_outline_rounded,
        iconColor: AdminTheme.success,
        value: '$_activeGyms',
        label: 'Active Gyms',
        change: _activeGyms > 0 ? '+$_activeGyms' : '0',
        isPositiveChange: true,
      ),
      AdminStatCard(
        icon: Icons.hourglass_top_rounded,
        iconColor: AdminTheme.info,
        value: '$_trialGyms',
        label: 'Trial Gyms',
        change: _trialGyms > 0 ? '+$_trialGyms' : '0',
        isPositiveChange: true,
      ),
      AdminStatCard(
        icon: Icons.warning_amber_rounded,
        iconColor: AdminTheme.warning,
        value: '$_gracePeriodGyms',
        label: 'Grace Period',
      ),
      AdminStatCard(
        icon: Icons.pause_circle_outline_rounded,
        iconColor: AdminTheme.orange,
        value: '$_suspendedGyms',
        label: 'Suspended Gyms',
      ),
      AdminStatCard(
        icon: Icons.block_rounded,
        iconColor: AdminTheme.danger,
        value: '$_disabledGyms',
        label: 'Disabled Gyms',
      ),
      AdminStatCard(
        icon: Icons.add_business_rounded,
        iconColor: AdminTheme.teal,
        value: '$_todayNewGyms',
        label: "Today's New Gyms",
        change: _todayNewGyms > 0 ? '+$_todayNewGyms' : '0',
        isPositiveChange: true,
      ),
      AdminStatCard(
        icon: Icons.currency_rupee_rounded,
        iconColor: AdminTheme.success,
        value: _formatRevenue(_monthlyRevenue),
        label: 'Monthly Revenue',
        change: _monthlyRevenue > 0 ? '+100%' : '0%',
        isPositiveChange: true,
      ),
      AdminStatCard(
        icon: Icons.account_balance_wallet_rounded,
        iconColor: AdminTheme.indigo,
        value: _formatRevenue(_totalRevenue),
        label: 'Total Revenue',
      ),
      AdminStatCard(
        icon: Icons.people_outline_rounded,
        iconColor: AdminTheme.pink,
        value: '$_activeMembers',
        label: 'Active Members',
        change: _activeMembers > 0 ? '+$_activeMembers' : '0',
        isPositiveChange: true,
      ),
      AdminStatCard(
        icon: Icons.badge_outlined,
        iconColor: AdminTheme.teal,
        value: '$_activeStaff',
        label: 'Active Staff',
      ),
      const AdminStatCard(
        icon: Icons.dns_rounded,
        iconColor: AdminTheme.success,
        value: 'Online',
        label: 'Server Status',
      ),
      AdminStatCard(
        icon: Icons.phone_android_rounded,
        iconColor: AdminTheme.info,
        value: 'v$_latestAppVersion',
        label: 'App Version',
      ),
    ];
  }

  Widget _buildChartsSection(BuildContext context) {
    final isDesktop = AdminResponsive.isDesktop(context);

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _buildRevenueChart(context)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: _buildPlanDistribution(context)),
        ],
      );
    }

    return Column(
      children: [
        _buildRevenueChart(context),
        const SizedBox(height: 16),
        _buildPlanDistribution(context),
      ],
    );
  }

  Widget _buildRevenueChart(BuildContext context) {
    double maxVal = 1000.0;
    for (var s in _revenueSpots) {
      if (s.y > maxVal) maxVal = s.y;
    }

    return ChartCard(
      title: 'Monthly Revenue',
      subtitle: 'Last 12 months trend',
      height: 260,
      chart: AdminLineChart(
        spots: _revenueSpots.isEmpty 
            ? List.generate(12, (i) => FlSpot(i.toDouble(), 0.0)) 
            : _revenueSpots,
        bottomLabels: _revenueMonthLabels,
        maxY: maxVal * 1.1,
        color: AdminTheme.primary,
      ),
    );
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

  Widget _buildPlanDistribution(BuildContext context) {
    return ChartCard(
      title: 'Plan Distribution',
      subtitle: 'Active subscriptions by plan',
      height: 260,
      chart: Row(
        children: [
          Expanded(
            child: AdminDonutChart(
              sections: _buildDonutSections(),
              centerRadius: 40,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendItem('Starter', AdminTheme.primary, '$_starterCount (${_starterPct.toStringAsFixed(0)}%)'),
              const SizedBox(height: 8),
              _legendItem('Pro', AdminTheme.info, '$_proCount (${_proPct.toStringAsFixed(0)}%)'),
              const SizedBox(height: 8),
              _legendItem('Business', AdminTheme.success, '$_businessCount (${_businessPct.toStringAsFixed(0)}%)'),
              const SizedBox(height: 8),
              _legendItem('Trial', AdminTheme.warning, '$_trialCount (${_trialPct.toStringAsFixed(0)}%)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(
          '$label  ',
          style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
        ),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context)),
        ),
      ],
    );
  }

  Widget _buildBottomSection(BuildContext context) {
    final isDesktop = AdminResponsive.isDesktop(context);

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _buildNewGymsChart(context)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: _buildRecentActivity(context)),
        ],
      );
    }

    return Column(
      children: [
        _buildNewGymsChart(context),
        const SizedBox(height: 16),
        _buildRecentActivity(context),
      ],
    );
  }

  Widget _buildNewGymsChart(BuildContext context) {
    return ChartCard(
      title: 'New Gyms',
      subtitle: 'Monthly registrations',
      height: 240,
      chart: AdminBarChart(
        values: _newGymsValues.isEmpty 
            ? List.generate(12, (_) => 0.0) 
            : _newGymsValues,
        labels: _newGymsLabels,
        color: AdminTheme.teal,
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'Recent Activity',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textColor(context),
              ),
            ),
          ),
          if (_activities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Center(
                child: Text(
                  'No recent activity found',
                  style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context)),
                ),
              ),
            )
          else
            ..._activities.map((a) => _activityTile(context, a)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _activityTile(BuildContext context, _ActivityItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: item.color.withOpacity(AdminTheme.isDark(context) ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
            ),
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.textColor(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            item.time,
            style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonView(double padding) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonLoader(width: 280, height: 28),
          const SizedBox(height: 8),
          const SkeletonLoader(width: 360, height: 16),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: List.generate(10, (_) => const SizedBox(
              width: 220,
              child: SkeletonCard(),
            )),
          ),
          const SizedBox(height: 28),
          const SkeletonLoader(height: 300),
        ],
      ),
    );
  }
}

class _ActivityItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;
  final DateTime timestamp;

  const _ActivityItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.timestamp,
  });
}
