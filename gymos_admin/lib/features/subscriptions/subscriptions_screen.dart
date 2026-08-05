import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/skeleton_loader.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});
  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              Text('Subscription Management', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              const SizedBox(height: 4),
              Text('Manage platform plans, coupons, and gym subscriptions', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
              const SizedBox(height: 24),
              // Plans grid
              _buildPlansGrid(context),
              const SizedBox(height: 28),
              // Tabs
              _buildTabSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlansGrid(BuildContext context) {
    final columns = AdminResponsive.isDesktop(context) ? 4 : (AdminResponsive.isTablet(context) ? 2 : 1);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = (constraints.maxWidth - (16.0 * (columns - 1))) / columns;
        return Wrap(
          spacing: 16, runSpacing: 16,
          children: _plans.map((p) => SizedBox(width: w, child: _buildPlanCard(context, p))).toList(),
        );
      },
    );
  }

  Widget _buildPlanCard(BuildContext context, Map<String, dynamic> plan) {
    final isPopular = plan['popular'] == true;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(
          color: isPopular ? AdminTheme.primary : AdminTheme.borderColor(context),
          width: isPopular ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(plan['name'] as String, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminTheme.textColor(context))),
              const Spacer(),
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AdminTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AdminTheme.radiusXs)),
                  child: Text('Popular', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminTheme.primary)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(plan['price'] as String, style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              Text('/mo', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context))),
            ],
          ),
          const SizedBox(height: 8),
          Text('${plan['gyms']} gyms on this plan', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
          const SizedBox(height: 16),
          ...(plan['features'] as List<String>).map((f) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: AdminTheme.success),
                const SizedBox(width: 8),
                Expanded(child: Text(f, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)))),
              ],
            ),
          )),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    side: BorderSide(color: AdminTheme.borderColor(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
                  ),
                  child: Text('Edit', style: GoogleFonts.inter(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
            labelColor: AdminTheme.primary,
            unselectedLabelColor: AdminTheme.secondaryTextColor(context),
            indicatorColor: AdminTheme.primary,
            dividerColor: AdminTheme.borderColor(context),
            tabs: const [
              Tab(text: 'Active Subscriptions'),
              Tab(text: 'Coupons'),
              Tab(text: 'Offers'),
            ],
          ),
          SizedBox(
            height: 400,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSubscriptionsList(context),
                _buildCouponsList(context),
                _buildOffersList(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionsList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, _) => Divider(color: AdminTheme.borderColor(context), height: 1),
      itemBuilder: (ctx, i) {
        final items = ['Iron Paradise', 'FitZone Premium', 'Elite Fitness', 'Spartan Club', 'Thunder Gym', 'Power House'];
        final plans = ['Pro', 'Business', 'Business', 'Pro', 'Starter', 'Free Trial'];
        final days = ['245', '180', '365', '120', '60', '45'];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AdminTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(items[i][0], style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AdminTheme.primary, fontSize: 16))),
          ),
          title: Text(items[i], style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          subtitle: Text('${plans[i]} Plan  •  ${days[i]} days remaining', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
          trailing: OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(minimumSize: const Size(80, 32), side: BorderSide(color: AdminTheme.borderColor(context))),
            child: Text('Manage', style: GoogleFonts.inter(fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildCouponsList(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_offer_outlined, size: 48, color: AdminTheme.mutedTextColor(context)),
          const SizedBox(height: 16),
          Text('No coupons created yet', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.add, size: 18), label: const Text('Create Coupon')),
        ],
      ),
    );
  }

  Widget _buildOffersList(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.celebration_outlined, size: 48, color: AdminTheme.mutedTextColor(context)),
          const SizedBox(height: 16),
          Text('No offers available', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.add, size: 18), label: const Text('Create Offer')),
        ],
      ),
    );
  }
}

const List<Map<String, dynamic>> _plans = [
  {'name': 'Free Trial', 'price': '₹0', 'gyms': 14, 'popular': false, 'features': ['3 Months Free', 'All Features', 'Up to 50 Members', '2 Staff']},
  {'name': 'Starter', 'price': '₹499', 'gyms': 45, 'popular': false, 'features': ['100 Members', '5 Staff', 'QR Attendance', 'Basic Reports']},
  {'name': 'Pro', 'price': '₹999', 'gyms': 52, 'popular': true, 'features': ['500 Members', '15 Staff', 'All Attendance', 'AI Features', 'Priority Support']},
  {'name': 'Business', 'price': '₹1,999', 'gyms': 20, 'popular': false, 'features': ['Unlimited Members', 'Unlimited Staff', 'All Features', 'Custom Branding', 'Dedicated Support']},
];
