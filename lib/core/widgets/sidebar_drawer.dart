import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../services/supabase_service.dart';
import 'app_cached_gym_logo.dart';
import '../../features/authentication/auth_viewmodel.dart';
import '../../features/authentication/role_selection_screen.dart';
import '../../features/subscription/owner_subscription_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchSubscription();
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

  void _navigateToSubscription() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OwnerSubscriptionScreen()),
    ).then((_) {
      if (mounted) _fetchSubscription();
    });
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
              onPressed: _isLoading ? null : _navigateToSubscription,
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
