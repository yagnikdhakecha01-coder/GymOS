import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';
import '../screens/member_exercise_library_screen.dart';

class WorkoutCategoryHelper {
  /// Resolves categories according to Exercise Library structure.
  /// For instance, if 'Legs' or 'Leg Day' is present, it decomposes into 'Upper Legs' and 'Lower Legs'.
  /// If multiple splits like 'Back' + 'Legs' exist, returns ['Back', 'Upper Legs', 'Lower Legs'].
  static List<String> resolveCategories(List<String> splits, String muscleGroup) {
    final List<String> categories = [];
    final List<String> inputSplits = [];

    if (splits.isNotEmpty) {
      inputSplits.addAll(splits);
    } else if (muscleGroup.isNotEmpty && !muscleGroup.toLowerCase().contains('rest')) {
      inputSplits.addAll(
        muscleGroup
            .split(RegExp(r'[+,&/]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
      );
    }

    for (final raw in inputSplits) {
      final s = raw.toLowerCase().trim();
      if (s.contains('rest')) continue;

      if (s.contains('upper leg') || s.contains('quad') || s.contains('hamstring') || s.contains('glute')) {
        if (!categories.contains('Upper Legs')) categories.add('Upper Legs');
      } else if (s.contains('lower leg') || s.contains('calve') || s.contains('calf')) {
        if (!categories.contains('Lower Legs')) categories.add('Lower Legs');
      } else if (s.contains('leg')) {
        // Legs decomposes into Upper Legs and Lower Legs as organized in the Exercise Library
        if (!categories.contains('Upper Legs')) categories.add('Upper Legs');
        if (!categories.contains('Lower Legs')) categories.add('Lower Legs');
      } else if (s.contains('back') || s.contains('lat')) {
        if (!categories.contains('Back')) categories.add('Back');
      } else if (s.contains('chest') || s.contains('pec')) {
        if (!categories.contains('Chest')) categories.add('Chest');
      } else if (s.contains('shoulder') || s.contains('delt')) {
        if (!categories.contains('Shoulders')) categories.add('Shoulders');
      } else if (s.contains('bicep') || s.contains('tricep') || s.contains('upper arm') || s.contains('arm')) {
        if (!categories.contains('Upper Arms')) categories.add('Upper Arms');
      } else if (s.contains('forearm') || s.contains('lower arm')) {
        if (!categories.contains('Lower Arms')) categories.add('Lower Arms');
      } else if (s.contains('ab') || s.contains('core') || s.contains('waist')) {
        if (!categories.contains('Waist')) categories.add('Waist');
      } else if (s.contains('cardio')) {
        if (!categories.contains('Cardio')) categories.add('Cardio');
      } else {
        final clean = raw.replaceAll(RegExp(r'\s*day', caseSensitive: false), '').trim();
        if (clean.isNotEmpty && !categories.contains(clean)) {
          categories.add(clean);
        }
      }
    }

    return categories;
  }

  static IconData getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'back':
        return Icons.fitness_center_rounded;
      case 'upper legs':
        return Icons.directions_run_rounded;
      case 'lower legs':
        return Icons.accessibility_new_rounded;
      case 'chest':
        return Icons.sports_kabaddi_rounded;
      case 'shoulders':
        return Icons.accessibility_rounded;
      case 'upper arms':
        return Icons.sports_mma_rounded;
      case 'lower arms':
        return Icons.pan_tool_rounded;
      case 'waist':
        return Icons.self_improvement_rounded;
      case 'cardio':
        return Icons.favorite_rounded;
      case 'neck':
        return Icons.airline_seat_recline_normal_rounded;
      default:
        return Icons.fitness_center_rounded;
    }
  }

  static String getCategorySubtitle(String category) {
    switch (category.toLowerCase()) {
      case 'back':
        return 'Lats, Traps & Spine';
      case 'upper legs':
        return 'Quads, Hamstrings & Glutes';
      case 'lower legs':
        return 'Calves & Shins';
      case 'chest':
        return 'Pectorals & Push Movements';
      case 'shoulders':
        return 'Deltoids & Overhead Press';
      case 'upper arms':
        return 'Biceps & Triceps';
      case 'lower arms':
        return 'Forearms & Grip Strength';
      case 'waist':
        return 'Abs, Obliques & Core';
      case 'cardio':
        return 'Stamina & Heart Rate';
      default:
        return 'Targeted Exercises';
    }
  }

  /// Opens the smart category selection sheet or directly navigates if only one option exists.
  static void openCategoryFlow(
    BuildContext context, {
    required List<String> splits,
    required String muscleGroup,
    required String memberId,
  }) {
    final categories = resolveCategories(splits, muscleGroup);

    if (categories.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MemberExerciseLibraryScreen(
            initialMuscleGroup: 'All',
            memberId: memberId,
          ),
        ),
      );
      return;
    }

    if (categories.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MemberExerciseLibraryScreen(
            initialMuscleGroup: categories.first,
            memberId: memberId,
          ),
        ),
      );
      return;
    }

    // Multiple categories: show modal bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(sheetCtx).padding.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's Muscle Categories",
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select what you want to train first',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...categories.map((cat) {
                final icon = getCategoryIcon(cat);
                final subtitle = getCategorySubtitle(cat);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MemberExerciseLibraryScreen(
                              initialMuscleGroup: cat,
                              memberId: memberId,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                          color: const Color(0xFFF8FAFC),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, color: AppTheme.primary, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cat,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: AppTheme.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
