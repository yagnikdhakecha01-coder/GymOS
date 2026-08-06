import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';
import 'member_membership_details.dart';

class MemberMembershipScreen extends StatelessWidget {
  const MemberMembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        final isExpired = vm.membershipDaysLeft <= 0 || vm.membershipStatus.toLowerCase() == 'expired';
        
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              'My Membership',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ═══════ PREMIUM MEMBERSHIP CARD ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0F172A), // Deep Slate Navy
                          Color(0xFF1E1B4B), // Royal Indigo
                          Color(0xFF312E81), // Deep Violet
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isExpired
                            ? Colors.redAccent.withValues(alpha: 0.5)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF312E81).withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card Header: Plan Name, Status Badge & Duration
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: const Text('👑', style: TextStyle(fontSize: 22)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vm.membershipPlan.isNotEmpty ? vm.membershipPlan : 'Gold Plan',
                                    style: GoogleFonts.inter(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    vm.planDuration.isNotEmpty ? '${vm.planDuration} Plan' : 'Active Plan',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: isExpired
                                    ? Colors.redAccent.withValues(alpha: 0.25)
                                    : const Color(0xFF10B981).withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isExpired ? Colors.redAccent : const Color(0xFF34D399),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                isExpired ? 'Expired' : 'Active',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isExpired ? Colors.redAccent : const Color(0xFF34D399),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Divider(color: Colors.white.withValues(alpha: 0.15), height: 1, thickness: 1),
                        const SizedBox(height: 16),

                        // Line 1: Start Date, End Date, Days Remaining
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildCardDataColumn('Start Date', vm.membershipStartDate.isNotEmpty ? vm.membershipStartDate : '01 Jan 2026', Colors.white),
                            _buildCardDataColumn('End Date', vm.membershipEndDate.isNotEmpty ? vm.membershipEndDate : '29 May 2026', Colors.white),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Remaining',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isExpired ? Colors.redAccent : const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (isExpired ? Colors.redAccent : const Color(0xFFF59E0B)).withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${vm.membershipDaysLeft} Days',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: isExpired ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Divider(color: Colors.white.withValues(alpha: 0.15), height: 1, thickness: 1),
                        const SizedBox(height: 16),

                        // Line 2: Amount Paid, Next Due, Pending Amount
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildCardDataColumn('Amount Paid', vm.amountPaid.isNotEmpty ? vm.amountPaid : '₹12,000', Colors.white),
                            _buildCardDataColumn('Next Due', vm.nextDue.isNotEmpty ? vm.nextDue : '30 May 2026', Colors.white),
                            _buildCardDataColumn(
                              'Pending',
                              '₹${vm.pendingAmount.toStringAsFixed(0)}',
                              vm.pendingAmount > 0 ? const Color(0xFFF87171) : const Color(0xFF34D399),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Line 3: Membership Timeline Progress Bar
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Membership Days Remaining',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  '${vm.membershipDaysLeft} Days Left',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFFBBF24), fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (vm.membershipDaysLeft / 90).clamp(0.0, 1.0),
                                backgroundColor: Colors.white.withValues(alpha: 0.15),
                                color: isExpired ? Colors.redAccent : const Color(0xFFF59E0B),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ═══════ QUICK ACTIONS BUTTONS ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MemberMembershipDetails(
                                    plan: vm.membershipPlan,
                                    status: vm.membershipStatus,
                                    startDate: vm.membershipStartDate,
                                    endDate: vm.membershipEndDate,
                                    daysRemaining: vm.membershipDaysLeft,
                                    planDuration: vm.planDuration,
                                    amountPaid: vm.amountPaid,
                                    nextDue: vm.nextDue,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.info_outline_rounded, size: 18),
                            label: Text('View Details', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: const BorderSide(color: AppTheme.primary, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('⚡ Membership Renewal request sent to Gym Owner!'),
                                  backgroundColor: AppTheme.success,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: const Icon(Icons.bolt_rounded, size: 18),
                            label: Text('Renew Plan', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ═══════ PAYMENT HISTORY SECTION ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Payment History',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: vm.paymentHistory.length,
                      separatorBuilder: (_, __) => _divider(),
                      itemBuilder: (context, index) {
                        final payment = vm.paymentHistory[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.receipt_long_rounded,
                                  color: Color(0xFF16A34A),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      payment['invoice'] as String? ?? 'INV-2026-004',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      payment['date'] as String? ?? '01 Jan 2026',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AppTheme.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    payment['amount'] as String? ?? '₹12,000',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    payment['status'] as String? ?? 'Paid',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.success,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardDataColumn(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 0.5,
      color: AppTheme.border,
    );
  }
}
