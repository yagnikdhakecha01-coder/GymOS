import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/status_badge.dart';
import 'diet_viewmodel.dart';
import 'diet_detail_screen.dart';
import '../../core/navigation/app_router.dart';
import '../../core/models/diet_plan.dart';
import '../gym_settings/gym_settings_viewmodel.dart';

class DietPlansScreen extends StatelessWidget {
  const DietPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dietVm = Provider.of<DietViewModel>(context);
    final settingsVm = Provider.of<GymSettingsViewModel>(context);
    final fitnessGoalsList = ['All', ...settingsVm.goals.map((e) => e.name)];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Diet Plans'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, AppRouter.slideRoute(const DietDetailScreen(dietPlan: null)));
        },
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search & Filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        onChanged: dietVm.setSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'Search diet plans...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Chips
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 6),
                children: fitnessGoalsList.map((goal) {
                  final isSelected = (goal == 'All' && dietVm.selectedGoal == '') ||
                      (dietVm.selectedGoal.toLowerCase() == goal.toLowerCase());
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(goal),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                      ),
                      onSelected: (val) {
                        if (val) {
                          dietVm.setGoalFilter(goal == 'All' ? '' : goal);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),

            // Diet List
            Expanded(
              child: dietVm.filteredDiets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.restaurant_outlined, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          Text('No Diet Plans found', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                      itemCount: dietVm.filteredDiets.length,
                      itemBuilder: (context, index) {
                        final plan = dietVm.filteredDiets[index];
                        return CustomCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          onTap: () {
                            Navigator.push(context, AppRouter.slideRoute(DietDetailScreen(dietPlan: plan)));
                          },
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppTheme.radiusThumbnail),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  color: AppTheme.successLight,
                                  child: const Icon(Icons.restaurant_rounded, color: AppTheme.success, size: 24),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      plan.title,
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${plan.calories} kcal/day • Goal: ${plan.goal}',
                                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              // Status badge (mocking plan status as active or matching membership status styles)
                              StatusBadge.fromStatus('Active'),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    Navigator.push(context, AppRouter.slideRoute(DietDetailScreen(dietPlan: plan)));
                                  } else if (action == 'delete') {
                                    _confirmDelete(context, dietVm, plan);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Edit')])),
                                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: AppTheme.danger), SizedBox(width: 8), Text('Delete')])),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, DietViewModel vm, DietPlan plan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Diet Plan'),
        content: Text('Are you sure you want to delete "${plan.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              await vm.deleteDiet(plan.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Diet plan deleted'), backgroundColor: AppTheme.danger),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
