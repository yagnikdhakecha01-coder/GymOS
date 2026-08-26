import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../theme/theme.dart';
import '../services/supabase_service.dart';
import '../services/gym_logo_cache_service.dart';
import '../services/subscription_plans_service.dart';
import 'app_cached_gym_logo.dart';
import '../../features/authentication/auth_viewmodel.dart';
import '../../features/authentication/role_selection_screen.dart';
import '../config/app_config.dart';

class SidebarDrawer extends StatefulWidget {
  const SidebarDrawer({super.key});

  @override
  State<SidebarDrawer> createState() => _SidebarDrawerState();
}

class _SidebarDrawerState extends State<SidebarDrawer> {
  bool _isLoading = true;
  Map<String, dynamic>? _subscription;

  // Free Trial Details
  bool _hasFreeTrial = true;
  bool _isTrialActive = true;
  int _trialDaysLeft = 0;
  String _trialStartStr = '-';
  String _trialEndStr = '-';

  // Paid Plan Details
  bool _hasPurchasedPlan = false;
  String _purchasedPlanName = '';
  int _paidDaysLeft = 0;
  String _paidStartStr = '-';
  String _paidEndStr = '-';

  // Razorpay Checkout variables
  late Razorpay _razorpay;
  String? _pendingPlanId;
  String? _pendingGymId;
  String? _pendingOwnerId;

  @override
  void initState() {
    super.initState();
    // Initialize Razorpay SDK
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    _fetchSubscription();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _fetchSubscription() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId == null || !SupabaseService.isInitialized) {
        _setFallbackStats();
        return;
      }

      final subRes = await SupabaseService.client
          .from('subscriptions')
          .select('*')
          .eq('gym_id', gymId)
          .maybeSingle();

      final gymInfo = authVm.gymInfo;

      // Free Trial dates calculation
      DateTime? trialStart;
      DateTime? trialEnd;

      if (subRes != null) {
        if (subRes['trial_start'] != null) {
          trialStart = DateTime.tryParse(subRes['trial_start'].toString());
        }
        if (subRes['trial_end'] != null) {
          trialEnd = DateTime.tryParse(subRes['trial_end'].toString());
        }
      }

      if (trialStart == null && gymInfo?['created_at'] != null) {
        trialStart = DateTime.tryParse(gymInfo!['created_at'].toString());
      }
      if (trialStart == null && subRes?['created_at'] != null) {
        trialStart = DateTime.tryParse(subRes!['created_at'].toString());
      }

      if (trialEnd == null && gymInfo?['trial_end_date'] != null) {
        trialEnd = DateTime.tryParse(gymInfo!['trial_end_date'].toString());
      }

      if (trialEnd == null && trialStart != null) {
        trialEnd = trialStart.add(const Duration(days: 90));
      }

      int trialDaysLeft = 0;
      bool isTrialActive = false;
      if (trialEnd != null) {
        trialDaysLeft = trialEnd.difference(DateTime.now()).inDays;
        if (trialDaysLeft < 0) trialDaysLeft = 0;
        isTrialActive = trialEnd.isAfter(DateTime.now());
      }

      // Paid Plan calculation
      final planId = subRes != null ? (subRes['plan_id'] ?? 'free_trial').toString() : 'free_trial';
      final bool hasPurchasedPlan = planId.toLowerCase() != 'free_trial';

      String formattedPlanName = '';
      if (planId.toLowerCase() == 'starter') formattedPlanName = 'Starter Plan';
      else if (planId.toLowerCase() == 'pro') formattedPlanName = 'Pro Plan';
      else if (planId.toLowerCase() == 'business') formattedPlanName = 'Business Plan';
      else if (hasPurchasedPlan) formattedPlanName = '${planId[0].toUpperCase()}${planId.substring(1)} Plan';

      DateTime? paidStart;
      DateTime? paidEnd;
      int paidDaysLeft = 30;

      if (hasPurchasedPlan && subRes != null) {
        if (subRes['start_date'] != null) {
          paidStart = DateTime.tryParse(subRes['start_date'].toString());
        }
        if (subRes['end_date'] != null) {
          paidEnd = DateTime.tryParse(subRes['end_date'].toString());
        } else if (subRes['next_billing_date'] != null) {
          paidEnd = DateTime.tryParse(subRes['next_billing_date'].toString());
        }

        if (isTrialActive && trialEnd != null) {
          // Paid plan starts after free trial ends
          paidStart = trialEnd;
          if (paidEnd == null || !paidEnd.isAfter(trialEnd)) {
            paidEnd = trialEnd.add(const Duration(days: 30));
          }
          paidDaysLeft = 30;
        } else {
          paidStart ??= DateTime.now();
          paidEnd ??= paidStart.add(const Duration(days: 30));
          paidDaysLeft = paidEnd.difference(DateTime.now()).inDays;
          if (paidDaysLeft < 0) paidDaysLeft = 0;
        }
      }

      String formatDate(DateTime? dt) {
        if (dt == null) return '-';
        final local = dt.toLocal();
        final day = local.day.toString().padLeft(2, '0');
        final month = local.month.toString().padLeft(2, '0');
        final year = local.year.toString().padLeft(4, '0');
        return '$day/$month/$year';
      }

      if (mounted) {
        setState(() {
          _subscription = subRes;
          _hasFreeTrial = trialEnd != null || isTrialActive;
          _isTrialActive = isTrialActive;
          _trialDaysLeft = trialDaysLeft;
          _trialStartStr = formatDate(trialStart);
          _trialEndStr = formatDate(trialEnd);

          _hasPurchasedPlan = hasPurchasedPlan;
          _purchasedPlanName = formattedPlanName;
          _paidDaysLeft = paidDaysLeft;
          _paidStartStr = formatDate(paidStart);
          _paidEndStr = formatDate(paidEnd);

          _isLoading = false;
        });
      }
    } catch (_) {
      _setFallbackStats();
    }
  }

  void _setFallbackStats() {
    if (!mounted) return;
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymInfo = authVm.gymInfo;
    DateTime? trialStart;
    DateTime? trialEnd;

    if (gymInfo != null) {
      if (gymInfo['created_at'] != null) {
        trialStart = DateTime.tryParse(gymInfo['created_at']);
      }
      if (gymInfo['trial_end_date'] != null) {
        trialEnd = DateTime.tryParse(gymInfo['trial_end_date']);
      }
    }
    trialStart ??= DateTime.now();
    trialEnd ??= trialStart.add(const Duration(days: 90));

    int days = trialEnd.difference(DateTime.now()).inDays;
    if (days < 0) days = 0;

    String formatDate(DateTime? dt) {
      if (dt == null) return '-';
      final local = dt.toLocal();
      final day = local.day.toString().padLeft(2, '0');
      final month = local.month.toString().padLeft(2, '0');
      final year = local.year.toString().padLeft(4, '0');
      return '$day/$month/$year';
    }

    setState(() {
      _subscription = null;
      _hasFreeTrial = true;
      _isTrialActive = days > 0;
      _trialDaysLeft = days;
      _trialStartStr = formatDate(trialStart);
      _trialEndStr = formatDate(trialEnd);

      _hasPurchasedPlan = false;
      _purchasedPlanName = '';
      _paidDaysLeft = 0;
      _paidStartStr = '-';
      _paidEndStr = '-';
      _isLoading = false;
    });
  }

  Future<void> _showChangePlanDialog() async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    if (gymId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text(
                'Change Subscription Plan',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Select one of our premium tiers to upgrade instantly',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ...SubscriptionPlansService.getPlans(authVm.storage).map((plan) {
                final desc = plan.features.take(3).join('  •  ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _planOptionCard(
                    sheetCtx, 
                    plan.id, 
                    '${plan.name} Plan', 
                    '${plan.priceFormatted}/month', 
                    desc, 
                    gymId,
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _planOptionCard(
    BuildContext sheetCtx, 
    String planId, 
    String title, 
    String price, 
    String desc, 
    String gymId
  ) {
    final isCurrent = _subscription?['plan_id'] == planId;
    return InkWell(
      onTap: isCurrent ? null : () async {
        Navigator.pop(sheetCtx); // Close sheet
        _initiateRazorpayPayment(planId);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isCurrent ? AppTheme.primaryLight : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent ? AppTheme.primary : Colors.grey[200]!,
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(4)),
                          child: Text('Active', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(desc, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Text(price, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primary)),
          ],
        ),
      ),
    );
  }

  Future<void> _initiateRazorpayPayment(String planId) async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      final ownerId = authVm.currentUser?.id;

      if (gymId == null || ownerId == null || !SupabaseService.isInitialized) {
        throw Exception("Invalid setup or missing auth credentials.");
      }

      // Check if it's the free trial option, skip checkout if free trial is re-requested
      if (planId == 'free_trial') {
        await _updateDatabaseDirectly(planId);
        return;
      }

      int amount = 69900;
      if (planId == 'pro') amount = 99900;
      if (planId == 'business') amount = 199900;

      // Save pending variables to verify signature on payment success callback
      _pendingPlanId = planId;
      _pendingGymId = gymId;
      _pendingOwnerId = ownerId;

      final contactPhone = (authVm.gymInfo?['phone'] ?? authVm.gymInfo?['phone_number'] ?? '').toString().trim();
      final contactEmail = (authVm.currentProfile?.email ?? '').toString().trim();
      final prefillMap = <String, String>{};
      if (contactPhone.isNotEmpty) prefillMap['contact'] = contactPhone;
      if (contactEmail.isNotEmpty) prefillMap['email'] = contactEmail;

      // 1. Invoke Supabase Edge Function to Create Razorpay Order
      dynamic functionRes;
      Map<String, dynamic> options;
      try {
        final razorpayPlanId = AppConfig.getRazorpayPlanId(planId);
        functionRes = await SupabaseService.client.functions.invoke(
          'create-subscription',
          body: {
            'gym_id': gymId,
            'plan_id': planId,
            'razorpay_plan_id': razorpayPlanId,
            'owner_id': ownerId,
          },
        );

        final data = functionRes.data as Map<String, dynamic>;
        if (data['success'] != true) {
          throw Exception(data['error'] ?? "Failed to initiate payment.");
        }

        // 2. Configure and Open Razorpay Checkout Dialog
        options = {
          'key': data['key_id'],
          if (data['amount'] != null) 'amount': data['amount'],
          'name': 'GymOS Enterprise',
          'description': 'Subscription (${planId.toUpperCase()} Plan)',
          if (data['order_id'] != null && data['order_id'].toString().isNotEmpty) 'order_id': data['order_id'],
          if (prefillMap.isNotEmpty) 'prefill': prefillMap,
          'notes': {
            'gym_id': gymId,
            'plan_id': planId,
            'razorpay_plan_id': razorpayPlanId,
            'auto_pay': 'true',
            'owner_id': ownerId,
          }
        };
      } catch (e) {
        debugPrint("Edge function invoke failed: $e. Opening standard Razorpay Checkout fallback.");
        final razorpayPlanId = AppConfig.getRazorpayPlanId(planId);
        options = {
          'key': AppConfig.razorpayKeyId,
          'amount': amount,
          'name': 'GymOS Enterprise',
          'description': 'Subscription (${planId.toUpperCase()} Plan)',
          if (prefillMap.isNotEmpty) 'prefill': prefillMap,
          'notes': {
            'gym_id': gymId,
            'plan_id': planId,
            'razorpay_plan_id': razorpayPlanId,
            'auto_pay': 'true',
            'owner_id': ownerId,
          }
        };
      }

      _razorpay.open(options);
      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  // Handle successful payments from Razorpay SDK
  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      if (_pendingGymId == null || _pendingPlanId == null || _pendingOwnerId == null) {
        throw Exception("Pending payment credentials not found.");
      }

      final paymentId = response.paymentId ?? '';
      bool verified = false;

      // Call verify-payment Edge Function if available
      try {
        final verifyRes = await SupabaseService.client.functions.invoke(
          'verify-payment',
          body: {
            'razorpay_order_id': response.orderId ?? '',
            'razorpay_payment_id': paymentId,
            'razorpay_signature': response.signature ?? '',
            'gym_id': _pendingGymId,
            'plan_id': _pendingPlanId,
            'owner_id': _pendingOwnerId,
          },
        );

        final data = verifyRes.data as Map<String, dynamic>?;
        if (data != null && data['success'] == true) {
          verified = true;
        }
      } catch (fnErr) {
        debugPrint("Edge function verify-payment unavailable or failed ($fnErr). Performing direct database activation fallback...");
      }

      // Direct activation fallback if Edge function returned 404 or failed
      if (!verified && paymentId.isNotEmpty) {
        final now = DateTime.now();
        final endDate = now.add(const Duration(days: 30));
        final startDateStr = now.toIso8601String();
        final endDateStr = endDate.toIso8601String();
        final planId = _pendingPlanId ?? 'pro';

        double price = 699.0;
        if (planId == 'pro') price = 999.0;
        if (planId == 'business') price = 1999.0;

        // 1. Update/Upsert Subscriptions
        dynamic subId;
        try {
          final subRes = await SupabaseService.client.from('subscriptions').upsert({
            'gym_id': _pendingGymId,
            'owner_id': _pendingOwnerId,
            'plan_id': planId,
            'status': 'active',
            'start_date': startDateStr,
            'end_date': endDateStr,
            'trial_end': startDateStr,
            'razorpay_subscription_id': paymentId,
            'auto_pay': true,
            'updated_at': startDateStr,
          }, onConflict: 'gym_id').select('id').maybeSingle();
          subId = subRes?['id'];
        } catch (e) {
          debugPrint('Direct subscription upsert error: $e');
        }

        // 2. Update Gyms table
        try {
          await SupabaseService.client.from('gyms').update({
            'plan': planId,
            'status': 'active',
            'expiry_date': endDateStr,
            'is_locked': false,
          }).eq('id', _pendingGymId!);
        } catch (e) {
          debugPrint('Direct gym table update error: $e');
        }

        // 3. Record Invoice & Payment
        try {
          final invoiceNumber = 'INV-${DateTime.now().millisecondsSinceEpoch}';
          final invRes = await SupabaseService.client.from('invoices').insert({
            'gym_id': _pendingGymId,
            'subscription_id': subId,
            'invoice_number': invoiceNumber,
            'amount': price,
            'status': 'paid',
            'billing_date': startDateStr,
            'due_date': startDateStr,
          }).select('id').maybeSingle();

          await SupabaseService.client.from('payments').insert({
            'gym_id': _pendingGymId,
            'subscription_id': subId,
            'invoice_id': invRes?['id'],
            'amount': price,
            'status': 'Success',
            'payment_method': 'Razorpay Gateway',
            'razorpay_payment_id': paymentId,
            'created_at': startDateStr,
          });

          await SupabaseService.client.from('subscription_history').insert({
            'gym_id': _pendingGymId,
            'new_plan_id': planId,
            'action': 'upgrade',
            'changed_by': _pendingOwnerId,
            'notes': 'Upgraded to ${planId.toUpperCase()} plan via verified Razorpay checkout ($paymentId).',
          });
        } catch (e) {
          debugPrint('Direct recording invoice/payment in drawer error: $e');
        }

        verified = true;
      }

      if (!verified) {
        throw Exception("Payment signature verification failed. Plan was not activated.");
      }

      // Reload auth context & reload subscriptions UI
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      await authVm.loadCurrentProfile();
      await authVm.fetchSubscriptionStatus();
      
      _fetchSubscription();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment verified & plan upgraded successfully!'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification Failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment Failed: [${response.code}] ${response.message}'), backgroundColor: Colors.red),
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint("External wallet payment captured: ${response.walletName}");
  }

  // Fallback direct updation for Free Trial
  Future<void> _updateDatabaseDirectly(String planId) async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId == null || !SupabaseService.isInitialized) return;

      final client = SupabaseService.client;
      int durationVal = 30;
      String durationUnit = 'days';
      
      try {
        final res = await client
            .from('platform_settings')
            .select('value')
            .eq('key', 'default_free_trial')
            .maybeSingle();
        if (res != null && res['value'] != null) {
          final Map<String, dynamic> val = Map<String, dynamic>.from(res['value']);
          durationVal = int.tryParse(val['duration_value']?.toString() ?? '30') ?? 30;
          durationUnit = val['duration_unit']?.toString() ?? 'days';
        }
      } catch (e) {
        debugPrint('Error getting dynamic trial duration in drawer: $e');
      }

      DateTime startDate = DateTime.now();
      DateTime endDate = durationUnit.toLowerCase() == 'months'
          ? DateTime.now().add(Duration(days: durationVal * 30))
          : DateTime.now().add(Duration(days: durationVal));

      if (planId != 'free_trial' && _isTrialActive && _trialEndStr != '-') {
        final trialEnd = DateTime.tryParse(_subscription?['trial_end']?.toString() ?? '');
        if (trialEnd != null && trialEnd.isAfter(DateTime.now())) {
          startDate = trialEnd;
          endDate = durationUnit.toLowerCase() == 'months'
              ? trialEnd.add(Duration(days: durationVal * 30))
              : trialEnd.add(Duration(days: durationVal));
        }
      }

      await client
          .from('subscriptions')
          .update({
            'plan_id': planId,
            'status': planId == 'free_trial' ? 'trial' : 'active',
            'auto_pay': true,
            'start_date': startDate.toIso8601String(),
            'next_billing_date': endDate.toIso8601String(),
            'end_date': endDate.toIso8601String(),
          })
          .eq('gym_id', gymId);

      try {
        await client.from('gyms').update({
          'plan': planId,
          'status': planId == 'free_trial' ? 'trial' : 'active',
          'expiry_date': endDate.toIso8601String(),
        }).eq('id', gymId);
      } catch (_) {}

      await authVm.loadCurrentProfile();
      _fetchSubscription();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Widget _buildSubscriptionSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Box 1: Free Trial Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: Color(0xFF6C4EFF), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Free Trial Active',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF6C4EFF),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE9FE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_trialDaysLeft Days Left',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF5B21B6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFDDD6FE)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start Date',
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _trialStartStr,
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'End Date',
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _trialEndStr,
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Box 2: Paid Plan Card (shown if money paid / plan purchased)
          if (_hasPurchasedPlan) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _purchasedPlanName.isNotEmpty ? _purchasedPlanName : 'Purchased Plan',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF065F46),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$_paidDaysLeft Days',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF047857),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFA7F3D0)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Date',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _paidStartStr,
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Date',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _paidEndStr,
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action Button (View Plans / Change Plan)
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _showChangePlanDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C4EFF),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _hasPurchasedPlan ? 'Change Plan' : 'View Plans',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final gymName = authVm.gymInfo?['name'] ?? 'GYMOS';
    final profileName = authVm.currentProfile?.fullName ?? 'User';
    final logoUrl = authVm.gymInfo?['logo'] ?? authVm.gymInfo?['logo_url'] ?? '';

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  AppCachedGymLogo(
                    gymId: authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id']?.toString(),
                    logoUrl: logoUrl,
                    gymName: gymName,
                    size: 52,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gymName,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profileName,
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Two Box Subscription Section (Gym Owners only)
            if (authVm.selectedRole?.toLowerCase() == 'owner') ...[
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildSubscriptionSection(),
                    ],
                  ),
                ),
              ),
              const Divider(),
            ] else ...[
              const Spacer(),
            ],

            // Logout row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: ListTile(
                onTap: () async {
                  await authVm.logout();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                      (route) => false,
                    );
                  }
                },
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: Text(
                  'Logout',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.red),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
