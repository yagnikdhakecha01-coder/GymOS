import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class DietMembershipRow extends StatelessWidget {
  final bool isDietAvailable;
  final String membershipPlan;
  final String membershipStatus;
  final String membershipEndDate;
  final int daysRemaining;
  final VoidCallback? onViewDiet;
  final VoidCallback? onViewMembership;

  const DietMembershipRow({
    super.key,
    required this.isDietAvailable,
    required this.membershipPlan,
    required this.membershipStatus,
    required this.membershipEndDate,
    required this.daysRemaining,
    this.onViewDiet,
    this.onViewMembership,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Today's Diet Card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text('🥗', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Today\'s Diet',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDietAvailable ? 'Diet plan available' : 'No diet plan assigned',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton(
                      onPressed: onViewDiet,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary, width: 1),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'View Diet',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Membership Plan Card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text('👑', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    membershipPlan,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$daysRemaining Days Left',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: ElevatedButton(
                      onPressed: onViewMembership,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Renew Plan',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
