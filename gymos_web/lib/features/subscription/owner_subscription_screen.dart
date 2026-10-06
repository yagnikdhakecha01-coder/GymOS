import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/subscription_plans_service.dart';
import '../../core/services/web_razorpay_service.dart';
import '../authentication/auth_viewmodel.dart';

class OwnerSubscriptionScreen extends StatefulWidget {
  const OwnerSubscriptionScreen({super.key});

  @override
  State<OwnerSubscriptionScreen> createState() => _OwnerSubscriptionScreenState();
}

class _OwnerSubscriptionScreenState extends State<OwnerSubscriptionScreen> {
  List<SubscriptionPlanModel> _plans = [];

  @override
  void initState() {
    super.initState();
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    _plans = SubscriptionPlansService.getPlans(authVm.storage);
    SubscriptionPlansService.fetchAndCachePlans(authVm.storage).then((updated) {
      if (mounted && updated.isNotEmpty) {
        setState(() => _plans = updated);
      }
    });

    _loadTrialSettings();
  }

  String _queuedPlanName = '';
  String _planEndStr = '';
  int _trialDaysLeft = 0;
  String? _currentPurchasedPlanId;
  bool _isTrialExpired = false;
  bool _autoPayEnabled = true;
  bool _cancelAtPeriodEnd = false;
  bool _isCancellingAutoPay = false;

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

            final gymRes = await SupabaseService.client
                .from('gyms')
                .select('plan, status, expiry_date, trial_end_date')
                .eq('id', gymId)
                .maybeSingle();

            if (mounted) {
              final rawPlan = (subRes?['plan_id'] ?? gymRes?['plan'] ?? 'free_trial').toString().toLowerCase();
              final rawStatus = (subRes?['status'] ?? gymRes?['status'] ?? 'trial').toString().toLowerCase();

              DateTime? trialEnd = subRes?['trial_end'] != null ? DateTime.tryParse(subRes!['trial_end'].toString()) : null;
              DateTime? planEnd = subRes?['end_date'] != null ? DateTime.tryParse(subRes!['end_date'].toString()) : null;

              if (trialEnd == null && gymRes?['trial_end_date'] != null) {
                trialEnd = DateTime.tryParse(gymRes!['trial_end_date'].toString());
              }
              if (trialEnd == null && authVm.gymInfo?['trial_end_date'] != null) {
                trialEnd = DateTime.tryParse(authVm.gymInfo!['trial_end_date'].toString());
              }

              if (planEnd == null && gymRes?['expiry_date'] != null) {
                planEnd = DateTime.tryParse(gymRes!['expiry_date'].toString());
              }

              final bool hasPurchased = rawPlan != 'free_trial' && 
                  rawPlan != 'trial' && 
                  rawPlan.isNotEmpty && 
                  rawStatus != 'expired';
              
              final bool isTrialActive = !hasPurchased && 
                  (trialEnd == null || trialEnd.isAfter(DateTime.now())) && 
                  rawStatus != 'expired';
              
              final bool isTrialExpired = !hasPurchased && 
                  (rawStatus == 'expired' || (trialEnd != null && trialEnd.isBefore(DateTime.now())));

              int daysLeft = 0;
              if (isTrialActive && trialEnd != null) {
                daysLeft = trialEnd.difference(DateTime.now()).inDays;
                if (daysLeft < 0) daysLeft = 0;
              }

              String formattedPlanName = 'Free Trial';
              if (rawPlan == 'starter') formattedPlanName = 'Starter Plan';
              if (rawPlan == 'pro') formattedPlanName = 'Pro Plan';
              if (rawPlan == 'business') formattedPlanName = 'Business Plan';

              bool isAutoPay = subRes?['auto_pay'] == null ? true : (subRes!['auto_pay'] == true);
              bool isCancelAtEnd = (subRes?['cancel_at_period_end'] ?? false) == true;

              String formatDate(DateTime? dt) {
                if (dt == null) return '-';
                final local = dt.toLocal();
                final day = local.day.toString().padLeft(2, '0');
                final month = local.month.toString().padLeft(2, '0');
                final year = local.year.toString().padLeft(4, '0');
                return '$day/$month/$year';
              }

              setState(() {
                _currentPurchasedPlanId = hasPurchased ? rawPlan : null;
                _isTrialExpired = isTrialExpired;
                _queuedPlanName = formattedPlanName;
                _trialDaysLeft = daysLeft;
                _planEndStr = formatDate(planEnd);
                _autoPayEnabled = isAutoPay && !isCancelAtEnd;
                _cancelAtPeriodEnd = isCancelAtEnd || !isAutoPay;
              });
            }
          } catch (e) {
            debugPrint('Error fetching subscription details: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading trial settings: $e');
    }
  }

  String get _trialTitleText {
    if (_currentPurchasedPlanId != null) {
      return 'Active Plan: $_queuedPlanName';
    }
    if (_isTrialExpired) {
      return 'Free Trial Expired';
    }
    return _trialDaysLeft > 0 
        ? '45 Days Free Trial Active ($_trialDaysLeft Days Left)' 
        : '45 Days Free Trial Active';
  }

  String get _trialSubtitleText {
    if (_currentPurchasedPlanId != null) {
      return 'Valid till $_planEndStr • Full features unlocked';
    }
    if (_isTrialExpired) {
      return 'Your 45 days free trial has ended. Select a plan below to continue full access.';
    }
    return 'Try all premium features free for 45 days. Cancel anytime.';
  }

  String get _trialFooterText {
    return 'All plans include 45 days free trial for new gyms. Cancel anytime.';
  }

  Future<void> _showCancelAutoPayDialog() async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final ownerId = authVm.currentUser?.id;
    if (gymId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cancel AutoPay?',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel your AutoPay subscription?',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your gym plan remains ACTIVE until $_planEndStr.',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.block_rounded, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'AutoPay will be turned OFF immediately. Next month\'s payment will NOT be debited automatically.',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF991B1B), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Cancellation Policy: You will not be charged again unless you manually renew your plan.',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep AutoPay Active', style: GoogleFonts.inter(color: Colors.grey[700], fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Yes, Cancel AutoPay', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isCancellingAutoPay = true);
      try {
        if (SupabaseService.isInitialized) {
          try {
            final res = await SupabaseService.client.rpc('cancel_autopay_subscription', params: {
              'p_gym_id': gymId,
            });
            if (res is Map && res['success'] == false) {
              throw Exception(res['message'] ?? 'Failed to cancel AutoPay');
            }
          } catch (e) {
            await SupabaseService.client.from('subscriptions').update({
              'auto_pay': false,
              'cancel_at_period_end': true,
              'auto_pay_cancelled_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('gym_id', gymId);
            
            try {
              await SupabaseService.client.from('subscription_history').insert({
                'gym_id': gymId,
                'action': 'Subscription Cancelled',
                'changed_by': ownerId,
                'notes': 'User cancelled AutoPay subscription via app.',
                'created_at': DateTime.now().toIso8601String(),
              });
            } catch (_) {}
          }

          await authVm.fetchSubscriptionStatus();
          await _loadTrialSettings();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('AutoPay cancelled successfully! Next month\'s payment will NOT be debited.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not cancel AutoPay: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isCancellingAutoPay = false);
      }
    }
  }

  String? _processingPlanId;

  Future<void> _buyPlan(SubscriptionPlanModel plan) async {
    if (_processingPlanId != null) return;

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final ownerId = authVm.currentUser?.id;

    if (gymId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gym details not found. Please log in again to proceed.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _processingPlanId = plan.id);

    try {
      final customerName = authVm.currentProfile?.fullName ?? authVm.currentUser?.userMetadata?['name']?.toString() ?? authVm.gymInfo?['name']?.toString() ?? 'Gym Owner';
      final customerEmail = authVm.currentUser?.email ?? authVm.currentProfile?.email ?? authVm.gymInfo?['email']?.toString() ?? '';
      final customerPhone = authVm.gymInfo?['phone_number']?.toString() ?? authVm.currentProfile?.phoneNumber ?? authVm.currentUser?.phone ?? '';

      final result = await WebRazorpayService.openCheckout(
        amount: plan.price,
        planName: plan.name,
        gymId: gymId,
        planId: plan.id,
        ownerId: ownerId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
      );

      if (result.dismissed) {
        if (mounted) {
          setState(() => _processingPlanId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Razorpay payment window closed.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      if (!result.success || result.paymentId == null) {
        if (mounted) {
          setState(() => _processingPlanId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Payment transaction was not completed.'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
        return;
      }

      // Payment Succeeded! Atomically activate the plan in Supabase
      final paymentId = result.paymentId!;
      final orderId = result.orderId ?? 'ORD_${DateTime.now().millisecondsSinceEpoch}';

      // 1. Invoke atomic database RPC function process_razorpay_webhook
      await SupabaseService.client.rpc('process_razorpay_webhook', params: {
        'p_event_type': 'payment.authorized',
        'p_gym_id': gymId,
        'p_plan_id': plan.id,
        'p_payment_id': paymentId,
        'p_order_id': orderId,
        'p_amount': plan.price,
      });

      // 2. Safely record payment in payments table
      try {
        await SupabaseService.client.from('payments').insert({
          'gym_id': gymId,
          'amount': plan.price,
          'status': 'Success',
          'payment_method': 'Razorpay Web Checkout',
          'razorpay_payment_id': paymentId,
          if (result.signature != null) 'razorpay_signature': result.signature,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (pe) {
        debugPrint('Non-fatal: payments table record: $pe');
      }

      // 3. Safely record in subscription_history table
      try {
        await SupabaseService.client.from('subscription_history').insert({
          'gym_id': gymId,
          'old_plan_id': _currentPurchasedPlanId,
          'new_plan_id': plan.id,
          'action': 'Subscription Purchased',
          'changed_by': ownerId,
          'notes': 'Activated ${plan.name} plan (₹${plan.price.toInt()}) via Razorpay Web Checkout ($paymentId).',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (he) {
        debugPrint('Non-fatal: subscription_history insert: $he');
      }

      // 4. Refresh global subscription status and local trial settings
      await authVm.fetchSubscriptionStatus();
      await _loadTrialSettings();

      if (mounted) {
        setState(() => _processingPlanId = null);
        _showPaymentSuccessDialog(plan, paymentId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingPlanId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment processed, but error updating records: $e'),
            backgroundColor: AppTheme.danger,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _handlePlanUpgrade(SubscriptionPlanModel plan) async {
    if (_processingPlanId != null) return;

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final ownerId = authVm.currentUser?.id;

    if (gymId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gym details not found. Please log in again to proceed.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    // Show loading indicator dialog while fetching proration preview
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 16)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF6C4EFF)),
              ),
              const SizedBox(width: 16),
              Text(
                'Calculating Prorated Upgrade...',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF1E293B)),
              ),
            ],
          ),
        ),
      ),
    );

    final preview = await WebRazorpayService.getUpgradePreview(
      gymId: gymId,
      newPlanId: plan.id,
      ownerId: ownerId,
    );

    if (mounted) Navigator.pop(context); // Close loading dialog

    if (!preview.success || preview.subscriptionId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(preview.errorMessage ?? 'Could not calculate upgrade preview.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    // Show Upgrade Confirmation Dialog with transparent credit calculation
    if (!mounted) return;
    final bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _buildUpgradeConfirmationDialog(ctx, plan, preview),
    );

    if (proceed != true) return;

    // Proceed to open Razorpay modal for upgrade
    setState(() => _processingPlanId = plan.id);

    try {
      final customerName = authVm.currentProfile?.fullName ?? authVm.currentUser?.userMetadata?['name']?.toString() ?? authVm.gymInfo?['name']?.toString() ?? 'Gym Owner';
      final customerEmail = authVm.currentUser?.email ?? authVm.currentProfile?.email ?? authVm.gymInfo?['email']?.toString() ?? '';
      final customerPhone = authVm.gymInfo?['phone_number']?.toString() ?? authVm.currentProfile?.phoneNumber ?? authVm.currentUser?.phone ?? '';

      final result = await WebRazorpayService.openCheckout(
        amount: preview.payableAmount,
        planName: plan.name,
        gymId: gymId,
        planId: plan.id,
        ownerId: ownerId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
        customSubscriptionId: preview.subscriptionId,
        isUpgrade: true,
        oldPlanId: preview.oldPlanId,
        oldSubId: preview.oldSubId,
        unusedCredit: preview.unusedCredit,
      );

      if (result.dismissed) {
        if (mounted) {
          setState(() => _processingPlanId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Razorpay upgrade window closed.'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }

      if (!result.success || result.paymentId == null) {
        if (mounted) {
          setState(() => _processingPlanId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Upgrade transaction was not completed.'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
        return;
      }

      // Verify payment with is_upgrade flag and trigger atomic DB upgrade & old mandate cancel
      await SupabaseService.client.functions.invoke(
        'verify-payment',
        body: {
          'razorpay_order_id': result.orderId ?? preview.subscriptionId,
          'razorpay_payment_id': result.paymentId,
          'razorpay_signature': result.signature,
          'gym_id': gymId,
          'plan_id': plan.id,
          'owner_id': ownerId,
          'is_upgrade': true,
          'old_plan_id': preview.oldPlanId,
          'old_sub_id': preview.oldSubId,
          'unused_credit': preview.unusedCredit,
        },
      );

      await authVm.fetchSubscriptionStatus();
      await _loadTrialSettings();

      if (mounted) {
        setState(() => _processingPlanId = null);
        _showUpgradeSuccessDialog(plan, preview, result.paymentId!);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingPlanId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error completing plan upgrade: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Widget _buildUpgradeConfirmationDialog(
    BuildContext ctx,
    SubscriptionPlanModel plan,
    PlanUpgradePreviewResult preview,
  ) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.upgrade_rounded, color: Color(0xFF6C4EFF), size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Upgrade to ${plan.name}',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Switch immediately to the ${plan.name} plan. Unused days from your active plan are credited today.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Current Plan:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text(
                        '${preview.oldPlanId?.toUpperCase() ?? "ACTIVE"} (${preview.remainingDays} days left)',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Unused Days Credit:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text(
                        '-₹${preview.unusedCredit.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('New Plan Full Price:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text(
                        '₹${preview.newPlanPrice.toInt()}/mo',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: Color(0xFFE2E8F0)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Payable Today:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                      Text(
                        '₹${preview.payableAmount.toInt()}',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF6C4EFF)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Next Recurring AutoPay:', style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                      Text(
                        '₹${preview.newPlanPrice.toInt()} / month',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your previous AutoPay mandate will be safely cancelled. Your new ₹${preview.newPlanPrice.toInt()} mandate starts in 30 days.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF1E40AF), height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey[700], fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C4EFF),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          child: Text(
            'Confirm Upgrade & Pay ₹${preview.payableAmount.toInt()}',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  void _showUpgradeSuccessDialog(
    SubscriptionPlanModel plan,
    PlanUpgradePreviewResult preview,
    String paymentId,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
            ),
            const SizedBox(height: 18),
            Text(
              'Plan Upgraded Successfully!',
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You are now on the ${plan.name} plan!\nAll features and higher limits are active immediately.',
              style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF64748B), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('New Active Plan:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text(plan.name, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Amount Paid Today:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text('₹${preview.payableAmount.toInt()}', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Unused Credit Adjusted:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text('-₹${preview.unusedCredit.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF2563EB))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('AutoPay Mandate Status:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text('Active (Migrated)', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF15803D))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Done', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentSuccessDialog(SubscriptionPlanModel plan, String paymentId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
            ),
            const SizedBox(height: 18),
            Text(
              'Payment Successful!',
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your ${plan.name} plan is now active for 30 days.\nAll plan features have been instantly unlocked!',
              style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF64748B), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Plan:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text(plan.name, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Amount Paid:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text(plan.priceFormatted, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Payment ID:', style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
                      Text(
                        paymentId.length > 18 ? '${paymentId.substring(0, 18)}...' : paymentId,
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C4EFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  'Continue to Dashboard',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 32.0 : 24.0, 
                vertical: 24.0,
              ),
              children: [
            // Trial & Active Plan Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _isTrialExpired 
                    ? const Color(0xFFFFFBEB) 
                    : (_currentPurchasedPlanId != null && _cancelAtPeriodEnd
                        ? const Color(0xFFFFF7ED)
                        : const Color(0xFFF5F3FF)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isTrialExpired 
                      ? const Color(0xFFFDE68A) 
                      : (_currentPurchasedPlanId != null && _cancelAtPeriodEnd
                          ? const Color(0xFFFFEDD5)
                          : const Color(0xFFDDD6FE)),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_isTrialExpired ? Colors.amber : const Color(0xFF6C4EFF)).withOpacity(0.12),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Icon(
                          _currentPurchasedPlanId != null
                              ? (_cancelAtPeriodEnd ? Icons.event_available_rounded : Icons.verified_rounded)
                              : (_isTrialExpired ? Icons.warning_amber_rounded : Icons.shield_outlined),
                          color: _currentPurchasedPlanId != null
                              ? (_cancelAtPeriodEnd ? const Color(0xFFEA580C) : const Color(0xFF6C4EFF))
                              : (_isTrialExpired ? const Color(0xFFD97706) : const Color(0xFF6C4EFF)),
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
                                color: _isTrialExpired 
                                    ? const Color(0xFFB45309) 
                                    : (_cancelAtPeriodEnd ? const Color(0xFFC2410C) : const Color(0xFF6C4EFF)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _currentPurchasedPlanId != null
                                  ? (_cancelAtPeriodEnd
                                      ? 'Valid till $_planEndStr • AutoPay Disabled (No next debit)'
                                      : 'Valid till $_planEndStr • AutoPay Active (Cancel Anytime)')
                                  : _trialSubtitleText,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _isTrialExpired 
                                    ? const Color(0xFF92400E) 
                                    : (_cancelAtPeriodEnd ? const Color(0xFF9A3412) : const Color(0xFF5B21B6)),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_currentPurchasedPlanId != null) ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _cancelAtPeriodEnd
                            ? const Color(0xFFFFF7ED)
                            : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _cancelAtPeriodEnd
                              ? const Color(0xFFFFEDD5)
                              : const Color(0xFFDCFCE7),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _cancelAtPeriodEnd ? Icons.info_outline_rounded : Icons.bolt_rounded,
                            size: 18,
                            color: _cancelAtPeriodEnd ? const Color(0xFFC2410C) : const Color(0xFF16A34A),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _cancelAtPeriodEnd ? 'AutoPay is OFF' : '⚡ AutoPay Active',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _cancelAtPeriodEnd ? const Color(0xFFC2410C) : const Color(0xFF166534),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _cancelAtPeriodEnd
                                      ? 'Money will not be deducted next month.'
                                      : 'You can cancel anytime before renewal.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _cancelAtPeriodEnd ? const Color(0xFF9A3412) : const Color(0xFF15803D),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_autoPayEnabled && !_cancelAtPeriodEnd) ...[
                            const SizedBox(width: 8),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _isCancellingAutoPay ? null : _showCancelAutoPayDialog,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFCA5A5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_isCancellingAutoPay)
                                        const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                                        )
                                      else ...[
                                        const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Cancel',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red[700],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Razorpay Payment Gateway Information Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C4EFF).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security_rounded, color: Color(0xFF6C4EFF), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Razorpay Secure Payment',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, size: 10, color: Color(0xFF16A34A)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Live API Active',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF15803D),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'UPI, Credit/Debit Cards & NetBanking supported. Instant 30-day plan activation with automated webhook sync.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Dynamic Plan Cards (Instantly loaded from local cache + Supabase sync)
            if (isDesktop && _plans.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _plans.map((plan) {
                    Color badgeColor = const Color(0xFFDCFCE7);
                    Color badgeTextColor = const Color(0xFF15803D);
                    if (plan.id == 'pro' || plan.badge == 'Best Value') {
                      badgeColor = const Color(0xFFF5F3FF);
                      badgeTextColor = const Color(0xFF6C4EFF);
                    } else if (plan.id == 'test' || plan.id.contains('test')) {
                      badgeColor = const Color(0xFFFEF3C7);
                      badgeTextColor = const Color(0xFFB45309);
                    } else if (plan.id == 'business') {
                      badgeColor = const Color(0xFFEFF6FF);
                      badgeTextColor = const Color(0xFF1D4ED8);
                    }
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: _buildPlanCard(
                          plan: plan,
                          badgeColor: badgeColor,
                          badgeTextColor: badgeTextColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              )
            else
              ..._plans.map((plan) {
                Color badgeColor = const Color(0xFFDCFCE7);
                Color badgeTextColor = const Color(0xFF15803D);
                if (plan.id == 'pro' || plan.badge == 'Best Value') {
                  badgeColor = const Color(0xFFF5F3FF);
                  badgeTextColor = const Color(0xFF6C4EFF);
                } else if (plan.id == 'test' || plan.id.contains('test')) {
                  badgeColor = const Color(0xFFFEF3C7);
                  badgeTextColor = const Color(0xFFB45309);
                } else if (plan.id == 'business') {
                  badgeColor = const Color(0xFFEFF6FF);
                  badgeTextColor = const Color(0xFF1D4ED8);
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _buildPlanCard(
                    plan: plan,
                    badgeColor: badgeColor,
                    badgeTextColor: badgeTextColor,
                  ),
                );
              }),
            const SizedBox(height: 12),

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
    ),
  ),
);
  }

  Widget _buildPlanCard({
    required SubscriptionPlanModel plan,
    Color? badgeColor,
    Color? badgeTextColor,
  }) {
    final planId = plan.id;
    final title = plan.name;
    final price = plan.priceFormatted;
    final badge = plan.badge;
    final features = plan.features;
    final bool isPurchased = _currentPurchasedPlanId != null &&
        _currentPurchasedPlanId!.toLowerCase() == planId.toLowerCase();
    final bool isPro = planId.toLowerCase() == 'pro';
    final bool isProcessing = _processingPlanId == planId;
    final bool canUpgrade = _currentPurchasedPlanId != null &&
        _currentPurchasedPlanId != 'free_trial' &&
        !isPurchased;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPurchased ? const Color(0xFF6C4EFF) : const Color(0xFFE2E8F0),
          width: isPurchased ? 2.2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isPurchased 
                ? const Color(0xFF6C4EFF).withOpacity(0.08)
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
          // Top Center "MOST POPULAR" Badge for Pro Plan
          if (isPro) ...[
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C4EFF), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C4EFF).withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      'MOST POPULAR',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

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
              if (badge != null && !isPro) ...[
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

          // Read-Only Status & Razorpay Buy/Upgrade Button
          if (isPurchased) ...[
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF22C55E),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Your Active Plan',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _processingPlanId != null
                    ? null
                    : (canUpgrade ? () => _handlePlanUpgrade(plan) : () => _buyPlan(plan)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPro
                      ? const Color(0xFF6C4EFF)
                      : (planId == 'business' ? const Color(0xFF1E293B) : const Color(0xFF0F172A)),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  elevation: isPro ? 3 : 0,
                  shadowColor: isPro ? const Color(0xFF6C4EFF).withOpacity(0.35) : Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isProcessing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            canUpgrade ? 'Calculating Upgrade...' : 'Opening Razorpay...',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            canUpgrade
                                ? Icons.upgrade_rounded
                                : (isPro ? Icons.bolt_rounded : Icons.lock_outline_rounded),
                            size: 17,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            canUpgrade
                                ? 'Upgrade to $title'
                                : (_currentPurchasedPlanId != null ? 'Switch to $title ($price)' : 'Buy $title ($price)'),
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
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
