import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';

class MemberMembershipScreen extends StatelessWidget {
  const MemberMembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            title: Text('Membership', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 16),

                // ═══════ GOLD PLAN CARD (Image 10 top) ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('🥇', style: TextStyle(fontSize: 28)),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(vm.membershipPlan, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                                Text('Valid till ${vm.membershipEndDate}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(vm.membershipStatus, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ═══════ DAYS REMAINING (Image 10) ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Text(
                            '${vm.membershipDaysLeft} Days Remaining',
                            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ═══════ PLAN DETAILS (Image 10 center) ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('Plan Duration', vm.planDuration),
                        _divider(),
                        _buildDetailRow('Amount Paid', vm.amountPaid),
                        _divider(),
                        _buildDetailRow('Next Due', vm.nextDue),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ═══════ VIEW DETAILS BUTTON (Image 10) ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('View Details', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ═══════ RENEW MEMBERSHIP BUTTON (Image 10) ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Renew Membership', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
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

  Widget _divider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 0.5,
      color: AppTheme.border,
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }
}
