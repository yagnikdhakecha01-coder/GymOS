import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  late TabController _tabController;

  // Stat counters
  int _totalTransactions = 0;
  int _activeSubscriptions = 0;
  int _failedPayments = 0;

  // Dynamic Lists
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _failedTransactions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchPaymentsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return names[month - 1];
    return '';
  }

  Future<void> _fetchPaymentsData() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      if (!AdminSupabaseService.isInitialized) {
        _setEmptyState();
        return;
      }
      final client = AdminSupabaseService.client;

      // 1. Fetch Transactions (Payments)
      final paymentsRes = await client
          .from('payments')
          .select('amount, status, payment_method, created_at, razorpay_payment_id, gyms(name)')
          .order('created_at', ascending: false);

      final paymentsList = paymentsRes as List;
      final List<Map<String, dynamic>> loadedTransactions = [];
      final List<Map<String, dynamic>> loadedFailed = [];

      int failedCount = 0;

      for (var item in paymentsList) {
        final payment = Map<String, dynamic>.from(item);
        final gymData = payment['gyms'];
        final gymName = (gymData != null) ? gymData['name'] : 'Active Gym';
        final amt = double.tryParse(payment['amount'].toString()) ?? 0.0;
        final cAt = DateTime.tryParse(payment['created_at'] ?? '') ?? DateTime.now();
        final status = payment['status'] ?? 'Success';

        final mapItem = {
          'gym': gymName,
          'amount': '₹${amt.toStringAsFixed(0)}',
          'method': payment['payment_method'] ?? 'Razorpay',
          'status': status,
          'id': payment['razorpay_payment_id'] ?? 'PAY-REF-${cAt.millisecondsSinceEpoch.toString().substring(6)}',
          'date': '${cAt.day} ${_getMonthName(cAt.month)}, ${cAt.year}',
        };

        if (status == 'Failed') {
          failedCount++;
          loadedFailed.add(mapItem);
        }
        loadedTransactions.add(mapItem);
      }

      // 2. Fetch Subscriptions
      final subsRes = await client
          .from('subscriptions')
          .select('status, start_date, end_date, gyms(name), subscription_plans(name)')
          .order('created_at', ascending: false);

      final subsList = subsRes as List;
      final List<Map<String, dynamic>> loadedSubscriptions = [];
      int activeSubsCount = 0;

      for (var item in subsList) {
        final sub = Map<String, dynamic>.from(item);
        final gymData = sub['gyms'];
        final gymName = (gymData != null) ? gymData['name'] : 'Active Gym';
        final planData = sub['subscription_plans'];
        final planName = (planData != null) ? planData['name'] : 'Pro Plan';
        final status = sub['status'] ?? 'active';

        if (status == 'active' || status == 'trial') {
          activeSubsCount++;
        }

        final start = DateTime.tryParse(sub['start_date'] ?? '') ?? DateTime.now();
        final end = DateTime.tryParse(sub['end_date'] ?? '') ?? DateTime.now();

        loadedSubscriptions.add({
          'gym': gymName,
          'plan': planName,
          'status': status,
          'details': '${start.day} ${_getMonthName(start.month)} - ${end.day} ${_getMonthName(end.month)} ${end.year}',
        });
      }

      if (mounted) {
        setState(() {
          _totalTransactions = loadedTransactions.length;
          _failedPayments = failedCount;
          _activeSubscriptions = activeSubsCount;

          _transactions = loadedTransactions;
          _failedTransactions = loadedFailed;
          _subscriptions = loadedSubscriptions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading payments data: $e');
      if (mounted) {
        _setEmptyState();
      }
    }
  }

  void _setEmptyState() {
    setState(() {
      _totalTransactions = 0;
      _activeSubscriptions = 0;
      _failedPayments = 0;
      _transactions = [];
      _failedTransactions = [];
      _subscriptions = [];
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
              Row(
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Payments', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                    const SizedBox(height: 4),
                    Text('Razorpay integration and billing logs from Database', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                  ]),
                  const Spacer(),
                  IconButton(
                    onPressed: _fetchPaymentsData,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Payments',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildStatCards(context),
              const SizedBox(height: 24),
              _buildTabSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCards(BuildContext context) {
    final cols = AdminResponsive.isDesktop(context) ? 5 : (AdminResponsive.isTablet(context) ? 3 : 2);
    final cards = [
      AdminStatCard(icon: Icons.receipt_long_rounded, iconColor: AdminTheme.primary, value: '$_totalTransactions', label: 'Total Transactions'),
      AdminStatCard(icon: Icons.autorenew_rounded, iconColor: AdminTheme.success, value: '$_activeSubscriptions', label: 'Active Subscriptions'),
      AdminStatCard(icon: Icons.error_outline_rounded, iconColor: AdminTheme.danger, value: '$_failedPayments', label: 'Failed Payments', isPositiveChange: false),
      const AdminStatCard(icon: Icons.replay_rounded, iconColor: AdminTheme.orange, value: '0', label: 'Refunds'),
      AdminStatCard(icon: Icons.webhook_rounded, iconColor: AdminTheme.teal, value: 'Active', label: 'Webhook Status', iconBgColor: AdminTheme.teal.withOpacity(0.1)),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final w = (c.maxWidth - (16.0 * (cols - 1))) / cols;
      return Wrap(spacing: 16, runSpacing: 16, children: cards.map((c) => SizedBox(width: w, child: c)).toList());
    });
  }

  Widget _buildTabSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
            labelColor: AdminTheme.primary, unselectedLabelColor: AdminTheme.secondaryTextColor(context),
            indicatorColor: AdminTheme.primary, dividerColor: AdminTheme.borderColor(context),
            tabs: const [Tab(text: 'Transactions'), Tab(text: 'Subscriptions'), Tab(text: 'Failed'), Tab(text: 'Refunds')],
            onTap: (_) => setState(() {}),
          ),
          SizedBox(
            height: 400,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPaymentList(context, _transactions, 'No transaction history found'),
                _buildSubscriptionList(context),
                _buildPaymentList(context, _failedTransactions, 'No failed transactions found'),
                _buildEmptyTab(context, 'No refunds recorded'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentList(BuildContext context, List<Map<String, dynamic>> items, String emptyMsg) {
    if (items.isEmpty) {
      return _buildEmptyTab(context, emptyMsg);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(color: AdminTheme.borderColor(context), height: 1),
      itemBuilder: (ctx, i) {
        final t = items[i];
        final isFailed = t['status'] == 'Failed';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: (isFailed ? AdminTheme.danger : AdminTheme.primary).withOpacity(0.1), 
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.payment_rounded, color: isFailed ? AdminTheme.danger : AdminTheme.primary, size: 20),
          ),
          title: Text('${t['gym']}  •  ${t['amount']}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          subtitle: Text('${t['method']}  •  ${t['date']}  •  ID: ${t['id']}', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
          trailing: isFailed
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AdminTheme.dangerLight, borderRadius: BorderRadius.circular(4)),
                  child: Text('Failed', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AdminTheme.danger)),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AdminTheme.successLight, borderRadius: BorderRadius.circular(4)),
                  child: Text('Success', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AdminTheme.success)),
                ),
        );
      },
    );
  }

  Widget _buildSubscriptionList(BuildContext context) {
    if (_subscriptions.isEmpty) {
      return _buildEmptyTab(context, 'No subscriptions registered');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _subscriptions.length,
      separatorBuilder: (_, _) => Divider(color: AdminTheme.borderColor(context), height: 1),
      itemBuilder: (ctx, i) {
        final s = _subscriptions[i];
        final isTrial = s['status'] == 'trial';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: (isTrial ? AdminTheme.warning : AdminTheme.success).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.autorenew_rounded, color: isTrial ? AdminTheme.warning : AdminTheme.success, size: 20),
          ),
          title: Text(s['gym'], style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          subtitle: Text('Plan: ${s['plan']}  •  Period: ${s['details']}', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isTrial ? AdminTheme.warningLight : AdminTheme.successLight,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              s['status'].toString().toUpperCase(),
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isTrial ? const Color(0xFFD97706) : AdminTheme.success),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyTab(BuildContext context, String msg) {
    return Center(
      child: Text(
        msg,
        style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context)),
      ),
    );
  }
}
