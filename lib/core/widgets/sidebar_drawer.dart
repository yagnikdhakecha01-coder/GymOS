import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../theme/theme.dart';
import '../services/supabase_service.dart';
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
  int _daysLeft = 0;
  String _planName = 'Free Trial';
  bool _isTrial = true;

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

  bool _isQueuedPlan = false;
  String _queuedPlanName = '';
  String _trialEndStr = '';
  String _planEndStr = '';

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

      if (subRes != null && mounted) {
        final planId = (subRes['plan_id'] ?? 'free_trial').toString();
        final String status = (subRes['status'] ?? 'trial').toString().toLowerCase();

        DateTime? trialEnd = subRes['trial_end'] != null ? DateTime.tryParse(subRes['trial_end'].toString()) : null;
        DateTime? planEnd = subRes['end_date'] != null ? DateTime.tryParse(subRes['end_date'].toString()) : null;

        if (trialEnd == null && authVm.gymInfo?['trial_end_date'] != null) {
          trialEnd = DateTime.tryParse(authVm.gymInfo!['trial_end_date'].toString());
        }

        final bool isTrialActive = trialEnd != null && trialEnd.isAfter(DateTime.now());
        final bool hasPurchasedPlan = planId.toLowerCase() != 'free_trial';
        final bool isQueued = isTrialActive && hasPurchasedPlan;

        int daysLeft = 0;
        if (isTrialActive) {
          daysLeft = trialEnd!.difference(DateTime.now()).inDays;
          if (daysLeft < 0) daysLeft = 0;
        } else if (planEnd != null && planEnd.isAfter(DateTime.now())) {
          daysLeft = planEnd.difference(DateTime.now()).inDays;
          if (daysLeft < 0) daysLeft = 0;
        }

        String formattedPlanName = 'Free Trial';
        if (planId.toLowerCase() == 'starter') formattedPlanName = 'Starter Plan';
        if (planId.toLowerCase() == 'pro') formattedPlanName = 'Pro Plan';
        if (planId.toLowerCase() == 'business') formattedPlanName = 'Business Plan';

        setState(() {
          _subscription = subRes;
          _daysLeft = daysLeft;
          _planName = isQueued ? 'Free Trial Active' : (hasPurchasedPlan && !isTrialActive ? formattedPlanName : 'Free Trial');
          _isTrial = isTrialActive || !hasPurchasedPlan;
          _isQueuedPlan = isQueued;
          _queuedPlanName = formattedPlanName;
          _trialEndStr = trialEnd != null ? trialEnd.toLocal().toString().split(' ')[0] : '-';
          _planEndStr = planEnd != null ? planEnd.toLocal().toString().split(' ')[0] : '-';
          _isLoading = false;
        });
      } else {
        _setFallbackStats();
      }
    } catch (_) {
      _setFallbackStats();
    }
  }

  void _setFallbackStats() {
    if (!mounted) return;
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymInfo = authVm.gymInfo;
    int days = 90;
    if (gymInfo != null && gymInfo['trial_end_date'] != null) {
      final expiryDate = DateTime.tryParse(gymInfo['trial_end_date']);
      if (expiryDate != null) {
        days = expiryDate.difference(DateTime.now()).inDays;
        if (days < 0) days = 0;
      }
    }
    setState(() {
      _subscription = null;
      _daysLeft = days;
      _planName = 'Free Trial';
      _isTrial = true;
      _isQueuedPlan = false;
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
              _planOptionCard(sheetCtx, 'starter', 'Starter Plan', '₹699/month', '100 Members  •  3 Staff  •  1 Gym', gymId),
              const SizedBox(height: 12),
              _planOptionCard(sheetCtx, 'pro', 'Pro Plan', '₹1,499/month', '1,000 Members  •  10 Staff  •  1 Gym', gymId),
              const SizedBox(height: 12),
              _planOptionCard(sheetCtx, 'business', 'Business Plan', '₹2,999/month', '2,000 Members/Gym  •  50 Staff  •  3 Gyms', gymId),
              const SizedBox(height: 24),
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
      if (planId == 'pro') amount = 149900;
      if (planId == 'business') amount = 299900;

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
          'amount': data['amount'],
          'name': 'GymOS Enterprise',
          'description': 'Subscription Plan Upgrade',
          'order_id': data['order_id'],
          if (prefillMap.isNotEmpty) 'prefill': prefillMap,
          'notes': {
            'gym_id': gymId,
            'plan_id': planId,
            'razorpay_plan_id': razorpayPlanId,
            'owner_id': ownerId,
          }
        };
      } catch (e) {
        debugPrint("Edge function invoke failed: $e. Opening standard Razorpay Checkout fallback.");
        final razorpayPlanId = AppConfig.getRazorpayPlanId(planId);
        options = {
          'key': AppConfig.razorpayKeyId,
          'amount': amount,
          'name': 'GymOS Enterprise (Test Mode)',
          'description': 'Subscription Plan Upgrade Fallback',
          if (prefillMap.isNotEmpty) 'prefill': prefillMap,
          'notes': {
            'gym_id': gymId,
            'plan_id': planId,
            'razorpay_plan_id': razorpayPlanId,
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

      // Call verify-payment Edge Function (Strict Backend Verification)
      try {
        final verifyRes = await SupabaseService.client.functions.invoke(
          'verify-payment',
          body: {
            'razorpay_order_id': response.orderId ?? '',
            'razorpay_payment_id': response.paymentId ?? '',
            'razorpay_signature': response.signature ?? '',
            'gym_id': _pendingGymId,
            'plan_id': _pendingPlanId,
            'owner_id': _pendingOwnerId,
          },
        );

        final data = verifyRes.data as Map<String, dynamic>?;
        if (data == null || data['success'] != true) {
          throw Exception(data?['error'] ?? "Payment signature verification failed. Plan was not activated.");
        }
      } catch (e) {
        debugPrint("Edge function 'verify-payment' failed/missing ($e). Falling back to direct database update.");
        await _updateDatabaseDirectly(_pendingPlanId!);
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

      final DateTime endDate = durationUnit.toLowerCase() == 'months'
          ? DateTime.now().add(Duration(days: durationVal * 30))
          : DateTime.now().add(Duration(days: durationVal));

      await client
          .from('subscriptions')
          .update({
            'plan_id': planId,
            'status': 'trial',
            'end_date': endDate.toIso8601String(),
          })
          .eq('gym_id', gymId);

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

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final gymName = authVm.gymInfo?['name'] ?? 'FitZone Gym';
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
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.primaryLight,
                    backgroundImage: logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                    child: logoUrl.isEmpty
                        ? const Icon(Icons.fitness_center_rounded, color: AppTheme.primary, size: 28)
                        : null,
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
            const Divider(),

            // Plan Status Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _isQueuedPlan ? const Color(0xFFF5F3FF) : (_isTrial ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isQueuedPlan ? const Color(0xFFDDD6FE) : (_isTrial ? const Color(0xFFFFEDD5) : const Color(0xFFDCFCE7)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isQueuedPlan ? Icons.hourglass_top_rounded : (_isTrial ? Icons.warning_amber_rounded : Icons.verified_user_rounded),
                          color: _isQueuedPlan ? const Color(0xFF6C4EFF) : (_isTrial ? const Color(0xFFD97706) : AppTheme.success),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _planName,
                          style: GoogleFonts.inter(
                            fontSize: 14, 
                            fontWeight: FontWeight.bold, 
                            color: _isQueuedPlan ? const Color(0xFF6C4EFF) : (_isTrial ? const Color(0xFFC2410C) : const Color(0xFF15803D)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isTrial 
                          ? '$_daysLeft Days Left in Free Trial' 
                          : 'Valid for another $_daysLeft Days',
                      style: GoogleFonts.inter(
                        fontSize: 12, 
                        fontWeight: FontWeight.w600,
                        color: _isQueuedPlan ? const Color(0xFF4C1D95) : (_isTrial ? const Color(0xFF9A3412) : const Color(0xFF166534)),
                      ),
                    ),
                    if (_isQueuedPlan) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFC4B5FD)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Purchased: $_queuedPlanName',
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Starts: $_trialEndStr\nExpires: $_planEndStr',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _showChangePlanDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isQueuedPlan ? const Color(0xFF6C4EFF) : (_isTrial ? const Color(0xFFEA580C) : AppTheme.primary),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          _isQueuedPlan ? 'View Plans' : 'Change Plan',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),
            const Divider(),

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
