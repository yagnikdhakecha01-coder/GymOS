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

  Future<void> _loadTrialSettings() async {
    try {
      if (SupabaseService.isInitialized) {
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

  Future<void> _verifyPayment(String orderId, String paymentId, String signature) async {
    setState(() => _isProcessing = true);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(color: Color(0xFF6C4EFF)),
            const SizedBox(width: 20),
            Expanded(
              child: Text('Verifying secure signature...', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
    
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      final ownerId = authVm.currentUser?.id;
      
      if (gymId == null || ownerId == null) {
        throw Exception('Missing gym/owner context.');
      }
      
      if (!SupabaseService.isInitialized) {
        await Future.delayed(const Duration(milliseconds: 1500));
        Navigator.pop(context); // Close loading dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment Verified (Mock Mode)'), backgroundColor: Colors.green),
        );
        
        Navigator.pop(context); // Exit subscription screen
        return;
      }
      
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
      
      Navigator.pop(context); // Close loading dialog
      
      final data = response.data;
      final success = data != null && data['success'] == true;
      
      if (success) {
        await authVm.fetchSubscriptionStatus();
        
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
                const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Subscription Active',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your gym has been successfully unlocked!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary),
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
        throw Exception(data?['error'] ?? 'Signature verification rejected by backend');
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
        Navigator.pop(context); // Close loading dialog
        
        _verifyPayment('mock_order_123', 'mock_pay_123', 'mock_sig_123');
        return;
      }
      
      final razorpayPlanId = AppConfig.getRazorpayPlanId(planId);
      final response = await SupabaseService.client.functions.invoke(
        'create-subscription',
        body: {
          'gym_id': gymId,
          'plan_id': planId,
          'razorpay_plan_id': razorpayPlanId,
          'owner_id': ownerId,
        },
      );
      
      Navigator.pop(context); // Close loading dialog
      
      final data = response.data;
      if (data == null || data['success'] != true) {
        throw Exception(data?['error'] ?? 'Order creation failed');
      }
      
      final orderId = data['order_id'] as String;
      final keyId = data['key_id'] as String;
      final amount = data['amount'] as num;
      
      _pendingOrderId = orderId;
      
      var options = {
        'key': keyId,
        'amount': amount,
        'name': 'Gym OS',
        'order_id': orderId,
        'description': 'Subscription for ${planId.toUpperCase()} Plan',
        'timeout': 300,
        'prefill': {
          'contact': ownerPhone.isNotEmpty ? ownerPhone : '9999999999',
          'email': ownerEmail,
        },
        'notes': {
          'gym_id': gymId,
          'plan_id': planId,
          'razorpay_plan_id': razorpayPlanId,
          'owner_id': ownerId,
        },
        'theme': {
          'color': '#6C4EFF',
        }
      };
      
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
            // Trial Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDDD6FE), width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFF6C4EFF),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _trialTitleText,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF6C4EFF),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _trialSubtitleText,
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
