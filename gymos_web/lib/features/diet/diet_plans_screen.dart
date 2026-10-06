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

class DietPlansScreen extends StatefulWidget {
  const DietPlansScreen({super.key});

  @override
  State<DietPlansScreen> createState() => _DietPlansScreenState();
}

class _DietPlansScreenState extends State<DietPlansScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DietViewModel>(context, listen: false).fetchDiets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dietVm = Provider.of<DietViewModel>(context);
    final settingsVm = Provider.of<GymSettingsViewModel>(context);
    final fitnessGoalsList = ['All', ...settingsVm.goals.map((e) => e.name)];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Diet Plans',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: dietVm.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  )
                : const Icon(Icons.refresh_rounded, color: AppTheme.textPrimary),
            tooltip: 'Refresh',
            onPressed: dietVm.isLoading
                ? null
                : () => Provider.of<DietViewModel>(context, listen: false).fetchDiets(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, AppRouter.slideRoute(const DietDetailScreen(dietPlan: null)));
        },
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
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
                  final isSelected = (goal == 'All' && (dietVm.selectedGoal.isEmpty || dietVm.selectedGoal.toLowerCase() == 'all')) ||
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
                          dietVm.setGoalFilter(goal == 'All' ? 'All' : goal);
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
              child: RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: () => Provider.of<DietViewModel>(context, listen: false).fetchDiets(),
                child: dietVm.isLoading && dietVm.diets.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : dietVm.filteredDiets.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.restaurant_outlined,
                                        size: 52,
                                        color: AppTheme.textMuted.withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No Diet Plans found',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Pull down or tap below to sync from cloud',
                                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                      ),
                                      const SizedBox(height: 16),
                                      OutlinedButton.icon(
                                        onPressed: () => Provider.of<DietViewModel>(context, listen: false).fetchDiets(),
                                        icon: const Icon(Icons.refresh, size: 16),
                                        label: const Text('Refresh from Cloud'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
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
                                          if (plan.meals.isNotEmpty)
                                            Text(
                                              '${plan.meals.length} meals included',
                                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                            ),
                                        ],
                                      ),
                                    ),
                                    StatusBadge.fromStatus(plan.status.isNotEmpty ? plan.status : 'Active'),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
                                      onSelected: (action) async {
                                        if (action == 'edit') {
                                          Navigator.push(context, AppRouter.slideRoute(DietDetailScreen(dietPlan: plan)));
                                        } else if (action == 'copy') {
                                          await dietVm.duplicateDiet(plan);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Diet plan duplicated')),
                                            );
                                          }
                                        } else if (action == 'delete') {
                                          _confirmDelete(context, dietVm, plan);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Edit')]),
                                        ),
                                        const PopupMenuItem(
                                          value: 'copy',
                                          child: Row(children: [Icon(Icons.copy, size: 16), SizedBox(width: 8), Text('Duplicate')]),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(children: [Icon(Icons.delete, size: 16, color: AppTheme.danger), SizedBox(width: 8), Text('Delete')]),
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
              ],
            ),
          ),
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
