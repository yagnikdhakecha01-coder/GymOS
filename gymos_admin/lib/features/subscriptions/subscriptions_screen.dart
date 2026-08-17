import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  late TabController _tabController;
  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _coupons = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      if (!AdminSupabaseService.isInitialized) {
        await AdminSupabaseService.initialize();
      }

      if (!AdminSupabaseService.isInitialized) {
        _loadFallbackData();
        return;
      }

      final client = AdminSupabaseService.client;

      // 1. Fetch Subscriptions from DB
      final List<Map<String, dynamic>> loadedSubscriptions = [];
      try {
        final response = await client
            .from('subscriptions')
            .select('''
              id,
              gym_id,
              owner_id,
              plan_id,
              status,
              start_date,
              end_date,
              trial_start,
              trial_end,
              created_at,
              gyms:gym_id (id, name, city, logo_url, phone),
              profiles:owner_id (id, full_name, email, phone_number)
            ''')
            .order('created_at', ascending: false);

        for (var item in response as List) {
          final map = Map<String, dynamic>.from(item);
          final gymMap = map['gyms'] != null ? Map<String, dynamic>.from(map['gyms']) : null;
          final profileMap = map['profiles'] != null ? Map<String, dynamic>.from(map['profiles']) : null;

          final String gymName = gymMap?['name'] ?? 'Unnamed Gym';
          final String ownerName = profileMap?['full_name'] ?? 'Gym Owner';
          final String ownerEmail = profileMap?['email'] ?? '';
          final String ownerPhone = profileMap?['phone_number'] ?? gymMap?['phone'] ?? '';
          final String planId = (map['plan_id'] ?? 'free_trial').toString().toLowerCase();
          final String status = (map['status'] ?? 'active').toString();

          String daysRemainingStr = '30 days';
          final String? effectiveEndStr = map['end_date'] ?? map['trial_end'];
          if (effectiveEndStr != null) {
            final endDate = DateTime.tryParse(effectiveEndStr);
            if (endDate != null) {
              final diff = endDate.difference(DateTime.now()).inDays;
              daysRemainingStr = diff > 0 ? '$diff days' : 'Expired';
            }
          }

          loadedSubscriptions.add({
            'id': map['id'],
            'gym_id': map['gym_id'],
            'gym_name': gymName,
            'owner_name': ownerName,
            'owner_email': ownerEmail,
            'owner_phone': ownerPhone,
            'plan_id': planId,
            'status': status,
            'days_remaining': daysRemainingStr,
            'start_date': map['start_date'] ?? map['created_at'],
            'end_date': map['end_date'] ?? map['trial_end'],
            'created_at': map['created_at'],
          });
        }
      } catch (e) {
        debugPrint("Primary subscriptions query error: $e");
      }

      // If subscriptions table query was empty or incomplete, fallback to gyms table
      if (loadedSubscriptions.isEmpty) {
        try {
          final gymsRes = await client
              .from('gyms')
              .select('id, name, city, plan, status, trial_end_date, expiry_date, user_gym_associations(role, profiles(full_name, email, phone_number))');

          for (var item in gymsRes as List) {
            final gymMap = Map<String, dynamic>.from(item);
            String ownerName = 'Gym Owner';
            String ownerEmail = '';
            String ownerPhone = '';

            final assoc = gymMap['user_gym_associations'] as List?;
            if (assoc != null) {
              for (var a in assoc) {
                if (a['role'] == 'owner' && a['profiles'] != null) {
                  final p = a['profiles'];
                  ownerName = p['full_name'] ?? ownerName;
                  ownerEmail = p['email'] ?? ownerEmail;
                  ownerPhone = p['phone_number'] ?? ownerPhone;
                  break;
                }
              }
            }

            final String planId = (gymMap['plan'] ?? 'free_trial').toString().toLowerCase();
            final String status = (gymMap['status'] ?? 'trial').toString();
            final String? endStr = gymMap['expiry_date'] ?? gymMap['trial_end_date'];
            String daysLeft = '90 days';
            if (endStr != null) {
              final endDate = DateTime.tryParse(endStr);
              if (endDate != null) {
                final diff = endDate.difference(DateTime.now()).inDays;
                daysLeft = diff > 0 ? '$diff days' : 'Expired';
              }
            }

            loadedSubscriptions.add({
              'id': gymMap['id'],
              'gym_id': gymMap['id'],
              'gym_name': gymMap['name'] ?? 'Gym',
              'owner_name': ownerName,
              'owner_email': ownerEmail,
              'owner_phone': ownerPhone,
              'plan_id': planId,
              'status': status,
              'days_remaining': daysLeft,
              'end_date': endStr,
            });
          }
        } catch (e) {
          debugPrint("Gyms query error: $e");
        }
      }

      // 2. Query subscription_plans directly from Database
      final Map<String, int> counts = {
        'free_trial': 0,
        'starter': 0,
        'pro': 0,
        'business': 0,
      };

      for (var sub in loadedSubscriptions) {
        final p = (sub['plan_id'] as String).toLowerCase();
        if (p.contains('trial')) {
          counts['free_trial'] = (counts['free_trial'] ?? 0) + 1;
        } else if (p.contains('starter')) {
          counts['starter'] = (counts['starter'] ?? 0) + 1;
        } else if (p.contains('pro')) {
          counts['pro'] = (counts['pro'] ?? 0) + 1;
        } else if (p.contains('business')) {
          counts['business'] = (counts['business'] ?? 0) + 1;
        } else {
          counts['free_trial'] = (counts['free_trial'] ?? 0) + 1;
        }
      }

      List<Map<String, dynamic>> loadedPlans = [];
      try {
        final plansRes = await client.from('subscription_plans').select('*').order('price', ascending: true);
        if (plansRes.isNotEmpty) {
          for (var p in plansRes) {
            final map = Map<String, dynamic>.from(p);
            final String pid = (map['id'] ?? '').toString().toLowerCase();
            final int gymsCount = counts[pid] ?? 0;

            final int? maxMembers = map['max_members'] as int?;
            final int? maxStaff = map['max_staff'] as int?;
            final int? maxGyms = map['max_gyms'] as int?;

            final List<String> features = [];
            features.add(maxMembers == null || maxMembers <= -1 ? 'Unlimited Members' : 'Up to $maxMembers Members');
            features.add(maxStaff == null || maxStaff <= -1 ? 'Unlimited Staff' : 'Up to $maxStaff Staff');
            features.add(maxGyms == null || maxGyms <= -1 ? 'Unlimited Gyms' : 'Up to $maxGyms Gym(s)');
            if (pid == 'pro' || pid == 'business') {
              features.add('AI Features & Attendance');
            }
            if (pid == 'business') {
              features.add('Custom Branding & Priority Support');
            }

            loadedPlans.add({
              'id': map['id'],
              'name': map['name'] ?? pid.toUpperCase(),
              'price_num': (map['price'] as num? ?? 0.0).toDouble(),
              'price': '₹${(map['price'] as num? ?? 0.0).toInt()}',
              'max_members': maxMembers ?? -1,
              'max_staff': maxStaff ?? -1,
              'max_gyms': maxGyms ?? 1,
              'razorpay_plan_id': map['razorpay_plan_id'] ?? '',
              'gyms': gymsCount,
              'popular': pid == 'pro',
              'features': features,
              'raw': map,
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading subscription_plans table: $e');
      }

      if (loadedPlans.isEmpty) {
        loadedPlans = [
          {'id': 'free_trial', 'name': 'Free Trial', 'price_num': 0.0, 'price': '₹0', 'max_members': 50, 'max_staff': 5, 'max_gyms': 1, 'gyms': counts['free_trial'] ?? 0, 'popular': false, 'features': ['50 Members', '5 Staff', '1 Gym', '3 Months Free']},
          {'id': 'starter', 'name': 'Starter', 'price_num': 699.0, 'price': '₹699', 'max_members': 100, 'max_staff': 5, 'max_gyms': 1, 'gyms': counts['starter'] ?? 0, 'popular': false, 'features': ['100 Members', '5 Staff', '1 Gym', 'Basic Reports']},
          {'id': 'pro', 'name': 'Pro', 'price_num': 999.0, 'price': '₹999', 'max_members': 500, 'max_staff': 15, 'max_gyms': 2, 'gyms': counts['pro'] ?? 0, 'popular': true, 'features': ['500 Members', '15 Staff', '2 Gyms', 'AI Features']},
          {'id': 'business', 'name': 'Business', 'price_num': 1999.0, 'price': '₹1,999', 'max_members': -1, 'max_staff': -1, 'max_gyms': 5, 'gyms': counts['business'] ?? 0, 'popular': false, 'features': ['Unlimited Members', 'Unlimited Staff', '5 Gyms', 'Custom Branding']},
        ];
      }

      // 3. Fetch Coupons
      List<Map<String, dynamic>> loadedCoupons = [];
      try {
        final couponsRes = await client.from('platform_coupons').select('*').order('created_at', ascending: false);
        if (couponsRes.isNotEmpty) {
          loadedCoupons = couponsRes.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _subscriptions = loadedSubscriptions;
        _plans = loadedPlans;
        _coupons = loadedCoupons;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching subscription data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadFallbackData() {
    setState(() {
      _plans = const [
        {'id': 'free_trial', 'name': 'Free Trial', 'price': '₹0', 'gyms': 1, 'popular': false, 'features': ['3 Months Free', 'All Features', 'Up to 50 Members', '2 Staff']},
        {'id': 'starter', 'name': 'Starter', 'price': '₹699', 'gyms': 0, 'popular': false, 'features': ['100 Members', '5 Staff', 'QR Attendance', 'Basic Reports']},
        {'id': 'pro', 'name': 'Pro', 'price': '₹999', 'gyms': 0, 'popular': true, 'features': ['500 Members', '15 Staff', 'All Attendance', 'AI Features', 'Priority Support']},
        {'id': 'business', 'name': 'Business', 'price': '₹1,999', 'gyms': 0, 'popular': false, 'features': ['Unlimited Members', 'Unlimited Staff', 'All Features', 'Custom Branding', 'Dedicated Support']},
      ];
      _isLoading = false;
    });
  }

  Future<void> _updateGymPlan(String gymId, String newPlanId, String newStatus, int extendDays) async {
    try {
      if (!AdminSupabaseService.isInitialized) return;
      final client = AdminSupabaseService.client;
      final DateTime newEndDate = DateTime.now().add(Duration(days: extendDays));

      // Update Subscriptions Table
      await client.from('subscriptions').upsert(
        {
          'gym_id': gymId,
          'plan_id': newPlanId,
          'status': newStatus,
          'end_date': newEndDate.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'gym_id',
      );

      // Update Gyms Table
      await client.from('gyms').update({
        'plan': newPlanId,
        'status': newStatus,
        'expiry_date': newEndDate.toIso8601String(),
      }).eq('id', gymId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Plan updated to ${newPlanId.toUpperCase()} successfully!'), backgroundColor: Colors.green),
        );
      }
      _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update plan: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showManageDialog(Map<String, dynamic> sub) {
    String selectedPlan = (sub['plan_id'] ?? 'starter').toString().toLowerCase();
    if (!['free_trial', 'starter', 'pro', 'business'].contains(selectedPlan)) {
      selectedPlan = 'starter';
    }
    String selectedStatus = (sub['status'] ?? 'active').toString().toLowerCase();
    if (!['active', 'trial', 'expired', 'suspended'].contains(selectedStatus)) {
      selectedStatus = 'active';
    }
    int extendDays = 30;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.stars_rounded, color: AdminTheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Manage Subscription - ${sub['gym_name']}',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Owner: ${sub['owner_name']} (${sub['owner_phone']})', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[700])),
                const SizedBox(height: 16),
                Text('Select Subscription Plan', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedPlan,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  items: const [
                    DropdownMenuItem(value: 'free_trial', child: Text('Free Trial (₹0)')),
                    DropdownMenuItem(value: 'starter', child: Text('Starter (₹699/mo)')),
                    DropdownMenuItem(value: 'pro', child: Text('Pro (₹999/mo)')),
                    DropdownMenuItem(value: 'business', child: Text('Business (₹1,999/mo)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedPlan = val);
                  },
                ),
                const SizedBox(height: 16),
                Text('Subscription Status', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'trial', child: Text('Trial')),
                    DropdownMenuItem(value: 'expired', child: Text('Expired')),
                    DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedStatus = val);
                  },
                ),
                const SizedBox(height: 16),
                Text('Validity Duration', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('30 Days'),
                      selected: extendDays == 30,
                      onSelected: (_) => setDialogState(() => extendDays = 30),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('90 Days'),
                      selected: extendDays == 90,
                      onSelected: (_) => setDialogState(() => extendDays = 90),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('365 Days'),
                      selected: extendDays == 365,
                      onSelected: (_) => setDialogState(() => extendDays = 365),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary),
              onPressed: () {
                Navigator.pop(ctx);
                _updateGymPlan(sub['gym_id'], selectedPlan, selectedStatus, extendDays);
              },
              child: Text('Save Changes', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Subscription Management', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                      const SizedBox(height: 4),
                      Text('Manage platform plans, gym subscriptions & live revenue status', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _fetchData,
                    tooltip: 'Refresh Subscriptions',
                  ),
                ],
              ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AdminTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
            child: Text('${plan['gyms']} Gyms Subscribed', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminTheme.primary)),
          ),
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showEditPlanLimitsDialog(context, plan),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: Text('Edit Plan & Limits', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminTheme.primary,
                side: const BorderSide(color: AdminTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPlanLimitsDialog(BuildContext context, Map<String, dynamic> plan) {
    final String pid = (plan['id'] ?? '').toString();
    final String planName = (plan['name'] ?? pid).toString();
    
    final priceController = TextEditingController(text: (plan['price_num'] ?? 0.0).toString());
    final razorpayController = TextEditingController(text: (plan['razorpay_plan_id'] ?? '').toString());

    int? maxMembers = plan['max_members'] as int?;
    int? maxStaff = plan['max_staff'] as int?;
    int? maxGyms = plan['max_gyms'] as int?;

    bool isUnlimitedMembers = maxMembers == null || maxMembers <= -1;
    bool isUnlimitedStaff = maxStaff == null || maxStaff <= -1;
    bool isUnlimitedGyms = maxGyms == null || maxGyms <= -1;

    final membersController = TextEditingController(text: isUnlimitedMembers ? '' : maxMembers.toString());
    final staffController = TextEditingController(text: isUnlimitedStaff ? '' : maxStaff.toString());
    final gymsController = TextEditingController(text: isUnlimitedGyms ? '' : maxGyms.toString());

    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AdminTheme.cardColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusCard)),
          title: Row(
            children: [
              const Icon(Icons.tune_rounded, color: AdminTheme.primary),
              const SizedBox(width: 8),
              Text('Edit $planName Plan Limits', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configure permissions, pricing & maximum allowed resources for this plan:', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                const SizedBox(height: 16),
                
                // Monthly Price (₹)
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.inter(color: AdminTheme.textColor(context)),
                  decoration: InputDecoration(
                    labelText: 'Monthly Price (₹)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
                  ),
                ),
                const SizedBox(height: 16),

                // Max Members Limit
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: membersController,
                        enabled: !isUnlimitedMembers,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.inter(color: AdminTheme.textColor(context)),
                        decoration: InputDecoration(
                          labelText: 'Max Members Limit',
                          hintText: isUnlimitedMembers ? 'Unlimited (-1)' : 'e.g. 50',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('Unlimited', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      selected: isUnlimitedMembers,
                      selectedColor: AdminTheme.primary.withValues(alpha: 0.2),
                      onSelected: (val) {
                        setDialogState(() {
                          isUnlimitedMembers = val;
                          if (val) membersController.clear();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Max Staff Limit
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: staffController,
                        enabled: !isUnlimitedStaff,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.inter(color: AdminTheme.textColor(context)),
                        decoration: InputDecoration(
                          labelText: 'Max Staff Limit',
                          hintText: isUnlimitedStaff ? 'Unlimited (-1)' : 'e.g. 5',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('Unlimited', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      selected: isUnlimitedStaff,
                      selectedColor: AdminTheme.primary.withValues(alpha: 0.2),
                      onSelected: (val) {
                        setDialogState(() {
                          isUnlimitedStaff = val;
                          if (val) staffController.clear();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Max Gyms Limit
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: gymsController,
                        enabled: !isUnlimitedGyms,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.inter(color: AdminTheme.textColor(context)),
                        decoration: InputDecoration(
                          labelText: 'Max Gyms Allowed',
                          hintText: isUnlimitedGyms ? 'Unlimited (-1)' : 'e.g. 1',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('Unlimited', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      selected: isUnlimitedGyms,
                      selectedColor: AdminTheme.primary.withValues(alpha: 0.2),
                      onSelected: (val) {
                        setDialogState(() {
                          isUnlimitedGyms = val;
                          if (val) gymsController.clear();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Razorpay Plan ID
                TextField(
                  controller: razorpayController,
                  style: GoogleFonts.inter(color: AdminTheme.textColor(context)),
                  decoration: InputDecoration(
                    labelText: 'Razorpay Plan ID (Optional)',
                    hintText: 'e.g. plan_N123456789',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.inter(color: AdminTheme.secondaryTextColor(context))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
              onPressed: isSaving ? null : () async {
                setDialogState(() => isSaving = true);
                try {
                  final double priceVal = double.tryParse(priceController.text.trim()) ?? (plan['price_num'] ?? 0.0);
                  final int? finalMaxMembers = isUnlimitedMembers ? -1 : int.tryParse(membersController.text.trim());
                  final int? finalMaxStaff = isUnlimitedStaff ? -1 : int.tryParse(staffController.text.trim());
                  final int? finalMaxGyms = isUnlimitedGyms ? -1 : int.tryParse(gymsController.text.trim());
                  final String rzPlanId = razorpayController.text.trim();

                  if (AdminSupabaseService.isInitialized) {
                    await AdminSupabaseService.client.from('subscription_plans').upsert({
                      'id': pid,
                      'name': planName,
                      'price': priceVal,
                      'max_members': finalMaxMembers,
                      'max_staff': finalMaxStaff,
                      'max_gyms': finalMaxGyms,
                      'razorpay_plan_id': rzPlanId.isNotEmpty ? rzPlanId : null,
                    });
                  }

                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  _fetchData();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Plan limits for "$planName" updated successfully in Database!'),
                      backgroundColor: AdminTheme.success,
                    ),
                  );
                } catch (e) {
                  setDialogState(() => isSaving = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating plan: $e'), backgroundColor: AdminTheme.danger),
                  );
                }
              },
              child: Text(isSaving ? 'Saving...' : 'Save Plan Limits', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
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
            tabs: [
              Tab(text: 'Active Subscriptions (${_subscriptions.length})'),
              Tab(text: 'Coupons (${_coupons.length})'),
              const Tab(text: 'Offers'),
            ],
          ),
          SizedBox(
            height: 450,
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
    if (_subscriptions.isEmpty) {
      return Center(
        child: Text('No subscriptions found in database', style: GoogleFonts.inter(color: Colors.grey)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _subscriptions.length,
      separatorBuilder: (_, _) => Divider(color: AdminTheme.borderColor(context), height: 1),
      itemBuilder: (ctx, i) {
        final item = _subscriptions[i];
        final String gymName = item['gym_name'] ?? 'Gym';
        final String ownerName = item['owner_name'] ?? 'Owner';
        final String ownerContact = item['owner_phone'].toString().isNotEmpty ? item['owner_phone'] : item['owner_email'];
        final String planId = (item['plan_id'] ?? 'free_trial').toString().toUpperCase();
        final String daysRemaining = item['days_remaining'] ?? '-';
        final String status = (item['status'] ?? 'active').toString().toUpperCase();

        Color badgeBg = AdminTheme.primary.withValues(alpha: 0.1);
        Color badgeFg = AdminTheme.primary;
        if (planId.contains('PRO')) {
          badgeBg = const Color(0xFFEDE9FE);
          badgeFg = const Color(0xFF6D28D9);
        } else if (planId.contains('STARTER')) {
          badgeBg = const Color(0xFFDCFCE7);
          badgeFg = const Color(0xFF15803D);
        } else if (planId.contains('BUSINESS')) {
          badgeBg = const Color(0xFFFEF3C7);
          badgeFg = const Color(0xFFB45309);
        }

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: AdminTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(gymName.isNotEmpty ? gymName[0].toUpperCase() : 'G', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AdminTheme.primary, fontSize: 18))),
          ),
          title: Row(
            children: [
              Text(gymName, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6)),
                child: Text(planId, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: badgeFg)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: status == 'ACTIVE' ? Colors.green.withOpacity(0.1) : Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(status, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: status == 'ACTIVE' ? Colors.green[800] : Colors.amber[900])),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Owner: $ownerName ($ownerContact)  •  $daysRemaining remaining',
              style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
            ),
          ),
          trailing: OutlinedButton.icon(
            onPressed: () => _showManageDialog(item),
            icon: const Icon(Icons.settings_rounded, size: 16),
            label: Text('Manage Plan', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(110, 36),
              side: BorderSide(color: AdminTheme.primary),
              foregroundColor: AdminTheme.primary,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCouponsList(BuildContext context) {
    if (_coupons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_offer_outlined, size: 48, color: AdminTheme.mutedTextColor(context)),
            const SizedBox(height: 16),
            Text('No coupons created yet', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _coupons.length,
      separatorBuilder: (_, _) => Divider(color: AdminTheme.borderColor(context), height: 1),
      itemBuilder: (ctx, i) {
        final coupon = _coupons[i];
        return ListTile(
          leading: const Icon(Icons.local_offer, color: AdminTheme.primary),
          title: Text(coupon['code'] ?? 'COUPON', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          subtitle: Text('${coupon['discount_percentage']}% OFF'),
        );
      },
    );
  }

  Widget _buildOffersList(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.celebration_outlined, size: 48, color: AdminTheme.mutedTextColor(context)),
          const SizedBox(height: 16),
          Text('No platform offers active', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        ],
      ),
    );
  }
}
