import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';
import 'member_guided_workout_screen.dart';
import 'member_exercise_library_screen.dart';

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
                          muscle.contains('Rest') 
                              ? 'Rest day — recovery is part of training!'
                              : 'Ready to crush ${muscle.toLowerCase()}?',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 🏋️ START GUIDED WORKOUT BUTTON
                        if (!muscle.contains('Rest'))
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              icon: const Text('🏋️', style: TextStyle(fontSize: 18)),
                              label: Text(
                                vm.isTrainingCompleted ? 'Workout Done 🎉' : 'Start Guided Workout',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: vm.isTrainingCompleted ? const Color(0xFF15803D) : Colors.white,
                                ),
                              ),
                              onPressed: vm.isTrainingCompleted ? null : () async {
                                // Build exercise list for today's muscle group
                                final prefs = await SharedPreferences.getInstance();
                                final gymInfoStr = prefs.getString('gymos_gym_info');
                                String gymId = '';
                                String memberId = vm.memberId;
                                if (gymInfoStr != null) {
                                  try {
                                    final gi = jsonDecode(gymInfoStr) as Map<String, dynamic>;
                                    gymId = gi['id'] ?? '';
                                  } catch (_) {}
                                }
                                final exercisesCache = prefs.getString('gymos_exercises_cache');
                                List<Map<String, dynamic>> todayExercises = [];
                                if (exercisesCache != null) {
                                  try {
                                    final all = (jsonDecode(exercisesCache) as List)
                                        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
                                    todayExercises = all
                                        .where((e) => (e['muscle_group'] as String? ?? '')
                                            .toLowerCase() == muscle.toLowerCase())
                                        .take(5)
                                        .toList();
                                  } catch (_) {}
                                }
                                if (context.mounted) {
                                  final result = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MemberGuidedWorkoutScreen(
                                        memberId: memberId,
                                        gymId: gymId,
                                        muscleGroup: muscle,
                                        exercises: todayExercises,
                                      ),
                                    ),
                                  );
                                  if (result == true && context.mounted) {
                                    final res = await vm.completeTodayWorkout(context);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(res['message']?.toString() ?? ''),
                                          backgroundColor: res['success'] == true ? AppTheme.success : AppTheme.danger,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          margin: const EdgeInsets.all(12),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: vm.isTrainingCompleted ? const Color(0xFFDCFCE7) : AppTheme.primary,
                                foregroundColor: vm.isTrainingCompleted ? const Color(0xFF15803D) : Colors.white,
                                disabledBackgroundColor: const Color(0xFFDCFCE7),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ═══════ QUICK ACCESS CARDS ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickActionCard(
                          emoji: '📚',
                          title: 'Exercise Library',
                          subtitle: '40+ exercises',
                          color: AppTheme.info,
                          onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const MemberExerciseLibraryScreen())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionCard(
                          emoji: '🏆',
                          title: 'My PRs',
                          subtitle: 'Personal records',
                          color: const Color(0xFFF59E0B),
                          onTap: () => _showPRsSheet(context, vm),
                        ),
                      ),
                    ],
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

  void _showPRsSheet(BuildContext context, MemberAppViewModel vm) {
    final prefs = SharedPreferences.getInstance();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FutureBuilder<SharedPreferences>(
        future: prefs,
        builder: (ctx, snap) {
          if (!snap.hasData) return const SizedBox();
          final cached = snap.data!.getString('member_prs_${vm.memberId}');
          Map<String, double> prs = {};
          if (cached != null) {
            try {
              prs = (jsonDecode(cached) as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, (v as num).toDouble()));
            } catch (_) {}
          }
          return Container(
            margin: const EdgeInsets.only(top: 80),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    '🏆 Personal Records',
                    style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                ),
                if (prs.isEmpty)
                  Expanded(child: Center(
                    child: Text('No PRs yet — start your first guided workout!',
                      style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted),
                      textAlign: TextAlign.center),
                  ))
                else
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: prs.entries.map((e) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          children: [
                            const Text('🏆', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(e.key,
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
                            Text('${e.value}kg',
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFD97706))),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Quick Action Card widget
class _QuickActionCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            Text(title,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            Text(subtitle,
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}
