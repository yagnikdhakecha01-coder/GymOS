import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';
import 'member_membership_details.dart';

class MemberMembershipScreen extends StatefulWidget {
  const MemberMembershipScreen({super.key});

  @override
  State<MemberMembershipScreen> createState() => _MemberMembershipScreenState();
}

class _MemberMembershipScreenState extends State<MemberMembershipScreen> {
  bool _isHistoryExpanded = false;

  String getWeekdayName(String dateStr) {
    try {
      final parsed = DateFormat('dd MMM yyyy').parse(dateStr);
      return DateFormat('EEEE').format(parsed);
    } catch (_) {
      return '';
    }
  }

  int getTotalPlanDays(String duration) {
    if (duration.contains('1')) return 30;
    if (duration.contains('3')) return 90;
    if (duration.contains('6')) return 180;
    if (duration.contains('12')) return 365;
    return 30; // fallback
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        final isExpired = vm.membershipDaysLeft <= 0 || vm.membershipStatus.toLowerCase() == 'expired';
        final totalPlanDays = getTotalPlanDays(vm.planDuration);
        final progressPercent = totalPlanDays > 0 
            ? ((vm.membershipDaysLeft / totalPlanDays).clamp(0.0, 1.0) * 100).toInt()
            : 0;
        
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
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header section with Purple Gradient
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF7C3AED), // Violet
                                Color(0xFF6366F1), // Indigo
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFF1C40F).withOpacity(0.7),
                                        width: 1.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text('👑', style: TextStyle(fontSize: 26)),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          vm.membershipPlan.isNotEmpty ? vm.membershipPlan : '1 Month Plan',
                                          style: GoogleFonts.inter(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Gym Membership Plan',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.white.withOpacity(0.8),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
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
                            ],
                          ),
                        ),

                        // Downward Pointer Arrow
                        _buildTrianglePointer(),

                        // Fields section inside white area
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Column 1
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldCell(
                                          label: 'Start Date',
                                          value: vm.membershipStartDate.isNotEmpty ? vm.membershipStartDate : '01 Jan 2026',
                                          subLabel: getWeekdayName(vm.membershipStartDate.isNotEmpty ? vm.membershipStartDate : '01 Jan 2026'),
                                          icon: Icons.calendar_today_outlined,
                                          iconColor: const Color(0xFF7C3AED),
                                          iconBgColor: const Color(0xFFF3E8FF),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 16),
                                          child: Divider(color: Color(0xFFF1F5F9), height: 1, thickness: 1),
                                        ),
                                        _buildFieldCell(
                                          label: 'Amount Paid',
                                          value: vm.amountPaid.isNotEmpty ? vm.amountPaid : '₹799.0',
                                          subLabel: 'Paid',
                                          icon: Icons.account_balance_wallet_outlined,
                                          iconColor: const Color(0xFF10B981),
                                          iconBgColor: const Color(0xFFD1FAE5),
                                          valueColor: const Color(0xFF059669),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Vertical Divider
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 12),
                                    width: 1,
                                    height: 140,
                                    color: const Color(0xFFF1F5F9),
                                  ),

                                  // Column 2
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldCell(
                                          label: 'End Date',
                                          value: vm.membershipEndDate.isNotEmpty ? vm.membershipEndDate : '29 May 2026',
                                          subLabel: getWeekdayName(vm.membershipEndDate.isNotEmpty ? vm.membershipEndDate : '29 May 2026'),
                                          icon: Icons.calendar_today_outlined,
                                          iconColor: const Color(0xFF7C3AED),
                                          iconBgColor: const Color(0xFFF3E8FF),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 16),
                                          child: Divider(color: Color(0xFFF1F5F9), height: 1, thickness: 1),
                                        ),
                                        _buildFieldCell(
                                          label: 'Next Due',
                                          value: vm.nextDue.isNotEmpty ? vm.nextDue : '30 May 2026',
                                          subLabel: getWeekdayName(vm.nextDue.isNotEmpty ? vm.nextDue : '30 May 2026'),
                                          icon: Icons.sync_rounded,
                                          iconColor: const Color(0xFF3B82F6),
                                          iconBgColor: const Color(0xFFDBEAFE),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Vertical Divider
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 12),
                                    width: 1,
                                    height: 140,
                                    color: const Color(0xFFF1F5F9),
                                  ),

                                  // Column 3
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldCell(
                                          label: 'Remaining',
                                          value: '',
                                          subLabel: '',
                                          icon: Icons.hourglass_empty_rounded,
                                          iconColor: const Color(0xFFF59E0B),
                                          iconBgColor: const Color(0xFFFEF3C7),
                                          customValueWidget: Container(
                                            margin: const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                        const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 16),
                                          child: Divider(color: Color(0xFFF1F5F9), height: 1, thickness: 1),
                                        ),
                                        _buildFieldCell(
                                          label: 'Pending',
                                          value: '₹${vm.pendingAmount.toStringAsFixed(0)}',
                                          subLabel: 'Due Amount',
                                          icon: Icons.receipt_long_outlined,
                                          iconColor: const Color(0xFFEF4444),
                                          iconBgColor: const Color(0xFFFEE2E2),
                                          valueColor: const Color(0xFFEF4444),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // Progress bar
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
                                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.6)),
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
                                      value: totalPlanDays > 0 ? (vm.membershipDaysLeft / totalPlanDays).clamp(0.0, 1.0) : 0.0,
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                      minHeight: 6,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '$progressPercent%',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          color: const Color(0xFF94A3B8),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${totalPlanDays - vm.membershipDaysLeft} / $totalPlanDays Days',
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
                            ],
                          ),
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
                            icon: const Icon(Icons.info_outline, size: 18),
                            label: Text(
                              'View Details',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: const BorderSide(color: AppTheme.primary, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
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
                              // Action to renew plan
                            },
                            icon: const Icon(Icons.bolt, size: 18),
                            label: Text(
                              'Renew Plan',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ═══════ PAYMENT HISTORY EXPANDABLE TILE ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.015),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isHistoryExpanded = !_isHistoryExpanded;
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF3E8FF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long_rounded,
                                    color: Color(0xFF9333EA),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Payment History',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Icon(
                                  _isHistoryExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.chevron_right_rounded,
                                  color: const Color(0xFF64748B),
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isHistoryExpanded) ...[
                          const Divider(color: Color(0xFFF1F5F9), height: 1, thickness: 1),
                          if (vm.paymentHistory.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Center(
                                child: Text(
                                  'No payment history found',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
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
                          const SizedBox(height: 10),
                        ],
                      ],
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

  Widget _buildTrianglePointer() {
    return Center(
      child: ClipPath(
        clipper: TriangleClipper(),
        child: Container(
          width: 16,
          height: 8,
          color: const Color(0xFF6366F1), // Matches bottom color of header gradient
        ),
      ),
    );
  }

  Widget _buildFieldCell({
    required String label,
    required String value,
    required String subLabel,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    Color? valueColor,
    Widget? customValueWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(8),
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
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              customValueWidget ?? Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: valueColor ?? const Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subLabel,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
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

class TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
