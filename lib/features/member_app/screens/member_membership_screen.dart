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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFFF1C40F).withOpacity(0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
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
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFF1C40F).withOpacity(0.7),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF1C40F).withOpacity(0.2),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  )
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const Text('👑', style: TextStyle(fontSize: 28)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vm.membershipPlan.isNotEmpty ? vm.membershipPlan : 'Gold Plan',
                                    style: GoogleFonts.inter(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Gym Membership Plan',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isExpired
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isExpired ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                isExpired ? 'Expired' : 'Active',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isExpired ? const Color(0xFFEF4444) : const Color(0xFF059669),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),
                        // Golden Star Divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: const Color(0xFFF1C40F).withOpacity(0.25), height: 1, thickness: 1)),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.star_rounded, color: Color(0xFFF1C40F), size: 16),
                            ),
                            Expanded(child: Divider(color: const Color(0xFFF1C40F).withOpacity(0.25), height: 1, thickness: 1)),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Grid Row 1: Start Date, End Date, Remaining
                        Row(
                          children: [
                            Expanded(
                              child: _buildGridCard(
                                label: 'Start Date',
                                value: vm.membershipStartDate.isNotEmpty ? vm.membershipStartDate : '01 Jan 2026',
                                icon: Icons.calendar_month_rounded,
                                iconColor: const Color(0xFFD97706),
                                iconBgColor: const Color(0xFFFEF3C7),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildGridCard(
                                label: 'End Date',
                                value: vm.membershipEndDate.isNotEmpty ? vm.membershipEndDate : '29 May 2026',
                                icon: Icons.calendar_month_rounded,
                                iconColor: const Color(0xFFD97706),
                                iconBgColor: const Color(0xFFFEF3C7),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildGridCard(
                                label: 'Remaining',
                                value: '${vm.membershipDaysLeft} Days',
                                icon: Icons.hourglass_empty_rounded,
                                iconColor: const Color(0xFFD97706),
                                iconBgColor: const Color(0xFFFEF3C7),
                                customValueWidget: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isExpired ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${vm.membershipDaysLeft} Days',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: isExpired ? const Color(0xFFEF4444) : const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Grid Row 2: Amount Paid, Next Due, Pending
                        Row(
                          children: [
                            Expanded(
                              child: _buildGridCard(
                                label: 'Amount Paid',
                                value: vm.amountPaid.isNotEmpty ? vm.amountPaid : '₹799.0',
                                icon: Icons.account_balance_wallet_rounded,
                                iconColor: const Color(0xFF059669),
                                iconBgColor: const Color(0xFFD1FAE5),
                                customValueWidget: Text(
                                  vm.amountPaid.isNotEmpty ? vm.amountPaid : '₹799.0',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF059669),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildGridCard(
                                label: 'Next Due',
                                value: vm.nextDue.isNotEmpty ? vm.nextDue : '30 May 2026',
                                icon: Icons.sync_rounded,
                                iconColor: const Color(0xFF3B82F6),
                                iconBgColor: const Color(0xFFDBEAFE),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildGridCard(
                                label: 'Pending',
                                value: '₹${vm.pendingAmount.toStringAsFixed(0)}',
                                icon: Icons.receipt_long_rounded,
                                iconColor: const Color(0xFFEF4444),
                                iconBgColor: const Color(0xFFFEE2E2),
                                customValueWidget: Text(
                                  '₹${vm.pendingAmount.toStringAsFixed(0)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFFEF4444),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
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
                                  'Membership Progress',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF0F172A),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFF1C40F).withOpacity(0.6)),
                                  ),
                                  child: Text(
                                    '${vm.membershipDaysLeft} Days Left',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: const Color(0xFFD97706),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (vm.membershipDaysLeft / 90).clamp(0.0, 1.0),
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF1C40F)),
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${((vm.membershipDaysLeft / 90).clamp(0.0, 1.0) * 100).toInt()}%',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
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

  Widget _buildGridCard({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    Widget? customValueWidget,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                customValueWidget ?? Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
