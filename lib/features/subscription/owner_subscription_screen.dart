import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme/theme.dart';
import '../../core/config/app_config.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/auth_viewmodel.dart';

class OwnerSubscriptionScreen extends StatefulWidget {
  const OwnerSubscriptionScreen({super.key});

  @override
  State<OwnerSubscriptionScreen> createState() => _OwnerSubscriptionScreenState();
}

class _OwnerSubscriptionScreenState extends State<OwnerSubscriptionScreen> {
  late Razorpay _razorpay;
  bool _isProcessing = false;
  String? _selectedPlanId;
  String? _pendingOrderId;
  double? _selectedPrice;

  // Dynamic free trial settings
  int _trialDuration = 30;
  String _trialUnit = 'days';
  bool _isLoadingSettings = true;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _loadTrialSettings();
  }

  bool _isQueuedPlan = false;
  String _queuedPlanName = '';
  String _trialEndStr = '';
  String _planEndStr = '';
  int _trialDaysLeft = 0;

  Future<void> _loadTrialSettings() async {
    try {
      if (SupabaseService.isInitialized) {
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];

        if (gymId != null) {
          try {
            final subRes = await SupabaseService.client
                .from('subscriptions')
                .select('*')
                .eq('gym_id', gymId)
                .maybeSingle();

            if (subRes != null && mounted) {
              final planId = (subRes['plan_id'] ?? 'free_trial').toString();
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
              }

              String formattedPlanName = 'Free Trial';
              if (planId.toLowerCase() == 'starter') formattedPlanName = 'Starter Plan';
              if (planId.toLowerCase() == 'pro') formattedPlanName = 'Pro Plan';
              if (planId.toLowerCase() == 'business') formattedPlanName = 'Business Plan';

              String formatDate(DateTime? dt) {
                if (dt == null) return '-';
                final local = dt.toLocal();
                final day = local.day.toString().padLeft(2, '0');
                final month = local.month.toString().padLeft(2, '0');
                final year = local.year.toString().padLeft(4, '0');
                return '$day/$month/$year';
              }

              if (isQueued) {
                if (planEnd == null || !planEnd.isAfter(trialEnd!)) {
                  planEnd = trialEnd!.add(const Duration(days: 30));
                }
              }

              setState(() {
                _isQueuedPlan = isQueued;
                _queuedPlanName = formattedPlanName;
                _trialDaysLeft = daysLeft;
                _trialEndStr = formatDate(trialEnd);
                _planEndStr = formatDate(planEnd);
              });
            }
          } catch (e) {
            debugPrint('Error fetching subscription details: $e');
          }
        }

        final res = await SupabaseService.client
            .from('platform_settings')
            .select('value')
            .eq('key', 'default_free_trial')
            .maybeSingle();

        if (res != null && res['value'] != null) {
          final Map<String, dynamic> val = Map<String, dynamic>.from(res['value']);
          if (mounted) {
            setState(() {
              _trialDuration = int.tryParse(val['duration_value']?.toString() ?? '30') ?? 30;
              _trialUnit = val['duration_unit']?.toString() ?? 'days';
              _isLoadingSettings = false;
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading dynamic trial settings: $e');
    }
    if (mounted) {
      setState(() {
        _isLoadingSettings = false;
      });
    }
  }

  String get _trialTitleText {
    final unitStr = _trialUnit.toLowerCase();
    if (unitStr == 'months') {
      return '$_trialDuration ${_trialDuration == 1 ? "Month" : "Month"} Free Trial';
    } else {
      return '$_trialDuration ${_trialDuration == 1 ? "Day" : "Days"} Free Trial';
    }
  }

  String get _trialSubtitleText {
    final unitStr = _trialUnit.toLowerCase();
    if (unitStr == 'months') {
      return 'Try all premium features free for $_trialDuration ${_trialDuration == 1 ? "month" : "months"}. Cancel anytime.';
    } else {
      return 'Try all premium features free for $_trialDuration ${_trialDuration == 1 ? "day" : "days"}. Cancel anytime.';
    }
  }

  String get _trialFooterText {
    final unitStr = _trialUnit.toLowerCase();
    if (unitStr == 'months') {
      return 'All plans include $_trialDuration ${_trialDuration == 1 ? "month" : "months"} free trial. Cancel anytime.';
    } else {
      return 'All plans include $_trialDuration ${_trialDuration == 1 ? "day" : "days"} free trial. Cancel anytime.';
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    _verifyPayment(
      response.orderId ?? _pendingOrderId ?? '',
      response.paymentId ?? '',
      response.signature ?? '',
    );
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment Failed: ${response.message ?? "User cancelled payment"}'),
        backgroundColor: AppTheme.danger,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    // Handle external wallet
  }

  Future<void> _updateDatabaseDirectly(
    String planId,
    String gymId,
    String ownerId, {
    String? paymentId,
    String? orderId,
  }) async {
    double price = 699.0;
    if (planId == 'pro') price = 999.0;
    if (planId == 'business') price = 1999.0;

    try {
      final planRes = await SupabaseService.client
          .from('subscription_plans')
          .select('price')
          .eq('id', planId)
          .maybeSingle();
      if (planRes != null && planRes['price'] != null) {
        price = (planRes['price'] as num).toDouble();
      }
    } catch (e) {
      debugPrint('Failed to fetch plan price from DB, using default price $price: $e');
    }

    // 1. Calculate new end date (extend existing trial / active subscription end date if still valid)
    DateTime newEndDate = DateTime.now().add(const Duration(days: 30));
    try {
      final currentSub = await SupabaseService.client
          .from('subscriptions')
          .select('end_date, trial_end, status')
          .eq('gym_id', gymId)
          .maybeSingle();

      if (currentSub != null) {
        DateTime? existingEnd;
        if (currentSub['end_date'] != null) {
          existingEnd = DateTime.tryParse(currentSub['end_date'].toString());
        }
        if (currentSub['trial_end'] != null) {
          final trialEnd = DateTime.tryParse(currentSub['trial_end'].toString());
          if (trialEnd != null && (existingEnd == null || trialEnd.isAfter(existingEnd))) {
            existingEnd = trialEnd;
          }
        }
        if (existingEnd != null && existingEnd.isAfter(DateTime.now())) {
          newEndDate = existingEnd.add(const Duration(days: 30));
        }
      }
    } catch (e) {
      debugPrint('Could not fetch existing subscription dates for extension: $e');
    }

    // 2. Activate Subscription & Enable AutoPay in DB
    final subRes = await SupabaseService.client
        .from('subscriptions')
        .upsert(
          {
            'gym_id': gymId,
            'owner_id': ownerId,
            'plan_id': planId,
            'status': 'active',
            'auto_pay': true,
            'next_billing_date': newEndDate.toIso8601String(),
            'start_date': DateTime.now().toIso8601String(),
            'end_date': newEndDate.toIso8601String(),
            if (orderId != null && orderId.isNotEmpty) 'razorpay_subscription_id': orderId,
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'gym_id',
        )
        .select('id')
        .single();

    final String subId = subRes['id'] as String;

    try {
      await SupabaseService.client.from('gyms').update({
        'plan': planId,
        'status': 'active',
        'expiry_date': newEndDate.toIso8601String(),
      }).eq('id', gymId);
    } catch (e) {
      debugPrint('Warning: Could not update gyms table: $e');
    }

    // 3. Create Invoice (Safe block)
    String? invoiceId;
    try {
      final invoiceNumber = 'INV-${DateTime.now().millisecondsSinceEpoch}';
      final invoiceRes = await SupabaseService.client
          .from('invoices')
          .insert({
            'gym_id': gymId,
            'subscription_id': subId,
            'invoice_number': invoiceNumber,
            'amount': price,
            'status': 'paid',
            'billing_date': DateTime.now().toIso8601String(),
            'due_date': DateTime.now().toIso8601String(),
          })
          .select('id')
          .maybeSingle();

      invoiceId = invoiceRes != null ? invoiceRes['id'] as String : null;
    } catch (e) {
      debugPrint('Warning: Could not insert invoice due to RLS policy ($e). Subscription activated successfully.');
    }

    // 4. Create Payment Record (Safe block)
    try {
      await SupabaseService.client.from('payments').insert({
        'gym_id': gymId,
        'subscription_id': subId,
        if (invoiceId != null) 'invoice_id': invoiceId,
        'amount': price,
        'status': 'Success',
        'payment_method': 'Razorpay Gateway',
        if (paymentId != null) 'razorpay_payment_id': paymentId,
      });
    } catch (e) {
      debugPrint('Warning: Could not insert payment record due to RLS policy ($e). Subscription activated successfully.');
    }

    // 5. Create Subscription History Record (Safe block)
    try {
      await SupabaseService.client.from('subscription_history').insert({
        'gym_id': gymId,
        'new_plan_id': planId,
        'action': 'upgrade',
        'changed_by': ownerId,
        'notes': 'Upgraded to ${planId.toUpperCase()} plan via Razorpay checkout (Fallback).',
      });
    } catch (e) {
      debugPrint('Warning: Could not insert subscription history due to RLS policy ($e). Subscription activated successfully.');
    }
  }

  Future<void> _verifyPayment(String orderId, String paymentId, String signature) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(color: Color(0xFF6C4EFF)),
            const SizedBox(width: 20),
            Expanded(child: Text('Verifying payment details...', style: GoogleFonts.inter())),
          ],
        ),
      ),
    );
    
    setState(() => _isProcessing = true);
    
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      final ownerId = authVm.currentUser?.id;
      
      if (gymId == null || ownerId == null) {
        throw Exception('Missing gym/owner context.');
      }
      
      if (!SupabaseService.isInitialized) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (Navigator.canPop(context)) Navigator.pop(context); // Close loading dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment Verified (Mock Mode)'), backgroundColor: Colors.green),
        );
        
        Navigator.pop(context); // Exit subscription screen
        return;
      }
      
      bool verified = false;
      final response = await SupabaseService.client.functions.invoke(
        'verify-payment',
        body: {
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
          'gym_id': gymId,
          'plan_id': _selectedPlanId,
          'owner_id': ownerId,
        },
      );
      
      final data = response.data;
      if (data != null && data['success'] == true) {
        verified = true;
      } else {
        throw Exception(data?['error'] ?? 'Backend payment signature verification failed');
      }
      
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Close loading dialog
      }
      
      if (verified) {
        await authVm.fetchSubscriptionStatus();
        await authVm.loadCurrentProfile();
        
        if (!mounted) return;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                Text(
                  'AutoPay Subscription Active! 🎉',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDCFCE7)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.autorenew_rounded, color: Colors.green, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AutoPay Enabled via Razorpay.\nNext auto-debit trigger: After 30 days on plan expiry (Auto-debits ₹${_selectedPrice?.toInt() ?? 699}/mo).',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF166534), fontWeight: FontWeight.w500, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your gym plan will seamlessly renew automatically without any manual payment steps!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx); // Close success dialog
                      Navigator.pop(context); // Close subscription screen
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C4EFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Get Started', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        throw Exception('Signature verification failed');
      }
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification Failed: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handlePayment(String planId, double price) async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final ownerId = authVm.currentUser?.id;
    final ownerEmail = authVm.currentUser?.email ?? 'owner@gymos.com';
    final ownerPhone = authVm.currentProfile?.phoneNumber ?? '';
    
    if (gymId == null || ownerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing owner or gym profile context.'), backgroundColor: AppTheme.danger),
      );
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _selectedPlanId = planId;
      _selectedPrice = price;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(color: Color(0xFF6C4EFF)),
            const SizedBox(width: 20),
            Expanded(child: Text('Generating Razorpay checkout...', style: GoogleFonts.inter())),
          ],
        ),
      ),
    );
    
    try {
      if (!SupabaseService.isInitialized) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (Navigator.canPop(context)) Navigator.pop(context); // Close loading dialog
        
        _verifyPayment('mock_order_123', 'mock_pay_123', 'mock_sig_123');
        return;
      }
      
      final razorpayPlanId = AppConfig.getRazorpayPlanId(planId);
      Map<String, dynamic> options;

      try {
        final response = await SupabaseService.client.functions.invoke(
          'create-subscription',
          body: {
            'gym_id': gymId,
            'plan_id': planId,
            'razorpay_plan_id': razorpayPlanId,
            'owner_id': ownerId,
          },
        );
        
        final data = response.data;
        if (data == null || data['success'] != true) {
          throw Exception(data?['error'] ?? 'Order creation failed');
        }
        
        final orderId = data['order_id'] as String;
        final keyId = data['key_id'] as String;
        final amount = data['amount'] as num;
        
        _pendingOrderId = orderId;
        
        options = {
          'key': keyId,
          if (amount > 0) 'amount': amount,
          'name': 'Gym OS',
          'description': 'AutoPay Monthly Subscription (${planId.toUpperCase()} Plan)',
          'recurring': 1,
          if (orderId.isNotEmpty) 'order_id': orderId,
          'timeout': 300,
          'prefill': {
            'contact': ownerPhone.isNotEmpty ? ownerPhone : '9999999999',
            'email': ownerEmail,
          },
          'notes': {
            'gym_id': gymId,
            'plan_id': planId,
            'razorpay_plan_id': razorpayPlanId,
            'auto_pay': 'true',
            'owner_id': ownerId,
          },
          'theme': {
            'color': '#6C4EFF',
          }
        };
      } catch (e) {
        debugPrint("Edge function 'create-subscription' failed or missing ($e). Falling back to direct Razorpay Checkout.");
        final int amountInPaise = (price * 100).toInt();
        options = {
          'key': AppConfig.razorpayKeyId,
          'amount': amountInPaise,
          'name': 'Gym OS',
          'description': 'AutoPay Monthly Subscription (${planId.toUpperCase()} Plan)',
          'recurring': 1,
          'timeout': 300,
          'prefill': {
            'contact': ownerPhone.isNotEmpty ? ownerPhone : '9999999999',
            'email': ownerEmail,
          },
          'notes': {
            'gym_id': gymId,
            'plan_id': planId,
            'razorpay_plan_id': razorpayPlanId,
            'auto_pay': 'true',
            'owner_id': ownerId,
          },
          'theme': {
            'color': '#6C4EFF',
          }
        };
      }

      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Close loading dialog
      }
      
      _razorpay.open(options);
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transaction Initiation Failed: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              'Choose Your Plan',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Pick the perfect plan for your gym',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // Trial & Upcoming Plan Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDDD6FE), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isQueuedPlan ? Icons.hourglass_top_rounded : Icons.shield_outlined,
                          color: const Color(0xFF6C4EFF),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isQueuedPlan ? 'Free Trial Active ($_trialDaysLeft Days Left)' : _trialTitleText,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF6C4EFF),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isQueuedPlan ? 'Free trial ends on $_trialEndStr' : _trialSubtitleText,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF5B21B6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_isQueuedPlan) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC4B5FD)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Purchased Plan: $_queuedPlanName',
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Auto-activates on $_trialEndStr • Valid till $_planEndStr',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Starter Plan Card
            _buildPlanCard(
              planId: 'starter',
              title: 'Starter',
              price: '₹699',
              badge: 'Popular',
              badgeColor: const Color(0xFFDCFCE7),
              badgeTextColor: const Color(0xFF15803D),
              features: [
                'Up to 50 Members',
                'Basic Reports',
                'Support (Email)',
                '1 Staff Account',
              ],
            ),
            const SizedBox(height: 20),

            // Pro Plan Card
            _buildPlanCard(
              planId: 'pro',
              title: 'Pro',
              price: '₹999',
              badge: 'Best Value',
              badgeColor: const Color(0xFFF5F3FF),
              badgeTextColor: const Color(0xFF6C4EFF),
              isRecommended: true,
              features: [
                'Up to 200 Members',
                'Advanced Reports',
                'Priority Support',
                '5 Staff Accounts',
                'Custom Branding',
              ],
            ),
            const SizedBox(height: 20),

            // Business Plan Card
            _buildPlanCard(
              planId: 'business',
              title: 'Business',
              price: '₹1999',
              features: [
                'Unlimited Members',
                'Advanced Reports',
                'Priority Support',
                'Unlimited Staff',
                'Custom Branding',
                'API Access',
              ],
            ),
            const SizedBox(height: 32),

            // Footer info
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF3F3F3)),
              ),
              child: Column(
                children: [
                  Text(
                    'All Plans Include',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFooterFeature(Icons.lock_rounded, 'Secure Data'),
                      _buildFooterFeature(Icons.sync_rounded, 'Regular Updates'),
                      _buildFooterFeature(Icons.devices_rounded, 'Multi-platform'),
                      _buildFooterFeature(Icons.headset_mic_rounded, '24/7 Support'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                _trialFooterText,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required String planId,
    required String title,
    required String price,
    String? badge,
    Color? badgeColor,
    Color? badgeTextColor,
    bool isRecommended = false,
    required List<String> features,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRecommended ? const Color(0xFF6C4EFF) : const Color(0xFFE2E8F0),
          width: isRecommended ? 2.2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isRecommended 
                ? const Color(0xFF6C4EFF).withOpacity(0.04)
                : Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeTextColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E293B),
                ),
              ),
              Text(
                ' / month',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 20),

          // Features Checklist
          ...features.map((feature) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF22C55E),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  feature,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 24),

          // Choose Plan Button with press scale animation
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ScaleButton(
              onTap: () => _handlePayment(planId, double.parse(price.replaceAll('₹', ''))),
              child: Container(
                decoration: BoxDecoration(
                  color: isRecommended ? const Color(0xFF6C4EFF) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF6C4EFF),
                    width: 1.5,
                  ),
                  boxShadow: isRecommended
                      ? [
                          BoxShadow(
                            color: const Color(0xFF6C4EFF).withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'Choose Plan',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isRecommended ? Colors.white : const Color(0xFF6C4EFF),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterFeature(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF64748B), size: 20),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const ScaleButton({Key? key, required this.child, required this.onTap}) : super(key: key);

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}
