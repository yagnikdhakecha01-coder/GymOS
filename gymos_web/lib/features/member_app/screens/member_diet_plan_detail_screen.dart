import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../../core/models/diet_plan.dart';
import '../member_app_viewmodel.dart';

class MemberDietPlanDetailScreen extends StatefulWidget {
  final DietPlan? dietPlan;

  const MemberDietPlanDetailScreen({super.key, this.dietPlan});

  @override
  State<MemberDietPlanDetailScreen> createState() =>
      _MemberDietPlanDetailScreenState();
}

class _MemberDietPlanDetailScreenState
    extends State<MemberDietPlanDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<MemberAppViewModel>(context);
    final plan = widget.dietPlan ?? vm.assignedDietPlan;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          plan?.title.isNotEmpty == true ? plan!.title : 'My Diet Plan',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: AppTheme.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: plan == null
          ? _buildEmptyState(context)
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Hero Goal Card
                  _buildHeroGoalCard(plan),
                  const SizedBox(height: 18),

                  // 2. Nutrition & Macros Targets
                  _buildMacrosRow(plan),
                  const SizedBox(height: 24),

                  // 3. Meal Schedule Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Meal Schedule',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${plan.meals.length} Meals Daily',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 4. Meal List Timeline
                  if (plan.meals.isEmpty)
                    _buildNoMealsCard()
                  else
                    ...plan.meals.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final meal = entry.value;
                      return _buildMealCard(idx + 1, meal);
                    }),

                  const SizedBox(height: 20),

                  // 5. Notes & Advice Card
                  if (plan.notes.isNotEmpty) _buildNotesCard(plan.notes),
                  const SizedBox(height: 16),

                  // 6. Healthy Lifestyle Tip
                  _buildHealthyTipCard(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.restaurant_menu_rounded,
                color: AppTheme.primary,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Diet Plan Assigned Yet',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your trainer or gym administrator hasn\'t assigned a customized meal plan to your account yet. Please contact gym staff to configure your nutrition targets.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(
                'Back to Dashboard',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroGoalCard(DietPlan plan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag_rounded,
                        color: AppTheme.primary, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      plan.goal.isNotEmpty ? plan.goal : 'Nutrition Plan',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Active Plan',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF34D399),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            plan.title,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          if (plan.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              plan.notes,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF94A3B8),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacrosRow(DietPlan plan) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMacroItem('Calories', '${plan.calories}', 'kcal',
              const Color(0xFFF59E0B), Icons.local_fire_department_rounded),
          _buildDivider(),
          _buildMacroItem(
              'Protein',
              plan.protein > 0 ? '${plan.protein}g' : 'Balanced',
              plan.protein > 0 ? 'target' : '',
              const Color(0xFFEF4444),
              Icons.fitness_center_rounded),
          _buildDivider(),
          _buildMacroItem(
              'Carbs',
              plan.carbs > 0 ? '${plan.carbs}g' : 'Controlled',
              plan.carbs > 0 ? 'target' : '',
              const Color(0xFF3B82F6),
              Icons.grain_rounded),
          _buildDivider(),
          _buildMacroItem(
              'Healthy Fat',
              plan.fat > 0 ? '${plan.fat}g' : 'Essential',
              plan.fat > 0 ? 'target' : '',
              const Color(0xFF10B981),
              Icons.water_drop_rounded),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 38,
      color: AppTheme.border.withValues(alpha: 0.8),
    );
  }

  Widget _buildMacroItem(String label, String value, String unit, Color color,
      IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 5),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          unit.isNotEmpty ? '$label ($unit)' : label,
          style: GoogleFonts.inter(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildMealCard(int order, Meal meal) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Accent Strip
              Container(
                width: 5,
                color: _getMealAccentColor(meal.name),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _getMealAccentColor(meal.name)
                                      .withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$order',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _getMealAccentColor(meal.name),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                meal.name.isNotEmpty ? meal.name : 'Meal $order',
                                style: GoogleFonts.inter(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          if (meal.time.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.access_time_rounded,
                                      size: 11,
                                      color: AppTheme.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    meal.time,
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        meal.items.isNotEmpty
                            ? meal.items
                            : 'No specific items recorded.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: const Color(0xFF334155),
                          height: 1.45,
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
    );
  }

  Color _getMealAccentColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('morning') || lower.contains('early')) {
      return const Color(0xFFF59E0B); // Amber
    } else if (lower.contains('breakfast')) {
      return const Color(0xFFE11D48); // Rose
    } else if (lower.contains('lunch')) {
      return const Color(0xFF10B981); // Emerald
    } else if (lower.contains('snack') || lower.contains('pre')) {
      return const Color(0xFF8B5CF6); // Purple
    } else if (lower.contains('dinner')) {
      return const Color(0xFF3B82F6); // Blue
    } else if (lower.contains('bed') || lower.contains('night')) {
      return const Color(0xFF6366F1); // Indigo
    }
    return AppTheme.primary;
  }

  Widget _buildNoMealsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Center(
        child: Text(
          'No meal timetable registered for this plan yet.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildNotesCard(String notes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.primary, size: 16),
              const SizedBox(width: 6),
              Text(
                'Dietary Guidelines',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            notes,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthyTipCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.water_drop_rounded,
              color: Color(0xFF2563EB), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hydration Goal: Drink at least 3 to 4 liters of water throughout the day for optimal energy, recovery, and digestion.',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1E40AF),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
