import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';
import 'member_diet_plan_detail_screen.dart';

class MemberDietScreen extends StatelessWidget {
  const MemberDietScreen({super.key});

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
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20, color: AppTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Today's Diet",
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

                // ═══════ MAIN DIET CARD (Image 9) ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Column(
                      children: [
                        // Salad and bottle illustration
                        Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('🥗', style: TextStyle(fontSize: 56)),
                                const SizedBox(width: 12),
                                const Text('🥤', style: TextStyle(fontSize: 48)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        Text(
                          'Diet Plan Available',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Subtitle
                        Text(
                          'Follow your diet plan and eat healthy.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // View Diet Plan Button
                        SizedBox(
                          width: 180,
                          height: 42,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MemberDietPlanDetailScreen(),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: const BorderSide(color: AppTheme.primary, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: Text(
                              'View Diet Plan',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ═══════ TODAY'S SUMMARY (Image 9 bottom) ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Today's Summary",
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 3 Column Grid Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryColumn('Calories', '${vm.caloriesIntake} kcal', const Color(0xFFF59E0B)),
                        _buildVerticalDivider(),
                        _buildSummaryColumn('Protein', '${vm.proteinIntake}g', const Color(0xFFEF4444)),
                        _buildVerticalDivider(),
                        _buildSummaryColumn('Water', '${vm.waterIntake} L', const Color(0xFF3B82F6)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Interactive Logs Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Log Daily Intake",
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildLogButton('💧 +250ml', () => vm.addWater(0.25)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildLogButton('🍎 +100 kcal', () => vm.addCalories(100)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildLogButton('🍗 +10g Pro', () => vm.addProtein(10)),
                      ),
                    ],
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

  Widget _buildSummaryColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppTheme.border,
    );
  }

  Widget _buildLogButton(String text, VoidCallback onTap) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          side: const BorderSide(color: AppTheme.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
