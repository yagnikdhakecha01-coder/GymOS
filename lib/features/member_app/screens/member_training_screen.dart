import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';

class MemberTrainingScreen extends StatelessWidget {
  const MemberTrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        final muscle = vm.todayMuscleGroup;
        final String illustrationAsset = 'assets/images/member/${muscle.toLowerCase().replaceAll(' ', '_')}.png';

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
              "Today's Training",
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

                // ═══════ MAIN TODAY CARD (Image 8) ═══════
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
                        // Muscle Line Illustration
                        Container(
                          height: 160,
                          width: 160,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Opacity(
                            opacity: 0.85,
                            child: Image.asset(
                              illustrationAsset,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.accessibility_new_rounded,
                                  color: AppTheme.primary,
                                  size: 64,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        Text(
                          muscle,
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: vm.isTrainingCompleted
                                ? AppTheme.successLight
                                : const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            vm.isTrainingCompleted ? 'Completed' : 'Not Completed',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: vm.isTrainingCompleted
                                  ? AppTheme.success
                                  : AppTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Subtitle
                        Text(
                          "Ask your trainer for today's exercises\nand plan.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Ask Trainer Button
                        SizedBox(
                          width: 150,
                          height: 42,
                          child: OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              side: const BorderSide(color: AppTheme.primary, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.forum_outlined, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Ask Trainer',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ═══════ TRAINING HISTORY SECTION ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Training History',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // List Items
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: vm.trainingHistory.length,
                  itemBuilder: (context, index) {
                    final item = vm.trainingHistory[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['date'] as String,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['muscle'] as String,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            item['status'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.textMuted,
                            size: 20,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
