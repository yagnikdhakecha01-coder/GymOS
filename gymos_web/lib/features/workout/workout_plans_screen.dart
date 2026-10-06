import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import 'workout_viewmodel.dart';
import 'workout_detail_screen.dart';
import '../../core/navigation/app_router.dart';
import '../../core/models/workout_plan.dart';
import '../gym_settings/gym_settings_viewmodel.dart';

class WorkoutPlansScreen extends StatefulWidget {
  const WorkoutPlansScreen({super.key});

  @override
  State<WorkoutPlansScreen> createState() => _WorkoutPlansScreenState();
}

class _WorkoutPlansScreenState extends State<WorkoutPlansScreen> {
  String _difficultyFilter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WorkoutViewModel>(context, listen: false).fetchWorkouts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final workoutVm = Provider.of<WorkoutViewModel>(context);
    final settingsVm = Provider.of<GymSettingsViewModel>(context);
    final fitnessGoalsList = ['All', ...settingsVm.goals.map((e) => e.name)];

    // Apply UI filtering for difficulty on top of viewmodel's goal/search filter
    final filteredWorkouts = workoutVm.filteredWorkouts.where((plan) {
      if (_difficultyFilter != 'All' && plan.difficulty != _difficultyFilter) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Workout Plans',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textPrimary),
            onPressed: () => workoutVm.refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, AppRouter.slideRoute(const WorkoutDetailScreen(workoutPlan: null)));
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
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: TextField(
                        onChanged: (val) => workoutVm.setSearchQuery(val),
                        decoration: InputDecoration(
                          hintText: 'Search workout plans...',
                          border: InputBorder.none,
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

            // Goal Chips & Difficulty Dropdown Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Goal Scroll list
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: fitnessGoalsList.map((goal) {
                          final isSelected = workoutVm.selectedGoal == goal;
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
                                  workoutVm.setGoalFilter(goal);
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Difficulty Filter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _difficultyFilter,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                        items: ['All', 'Beginner', 'Intermediate', 'Advanced'].map((diff) {
                          return DropdownMenuItem(value: diff, child: Text(diff));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _difficultyFilter = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Workout List
            Expanded(
              child: workoutVm.isLoading && workoutVm.workouts.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => workoutVm.fetchWorkouts(),
                      child: filteredWorkouts.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fitness_center_outlined, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                                      const SizedBox(height: 8),
                                      Text('No Workout Plans found', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        onPressed: () => workoutVm.fetchWorkouts(),
                                        icon: const Icon(Icons.refresh, size: 16),
                                        label: const Text('Refresh'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 8),
                              itemCount: filteredWorkouts.length,
                              itemBuilder: (context, index) {
                                final plan = filteredWorkouts[index];
                                return _buildWorkoutCard(context, workoutVm, plan);
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

  Widget _buildWorkoutCard(BuildContext context, WorkoutViewModel workoutVm, WorkoutPlan plan) {
    // Days list for weekly preview
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return CustomCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () {
        Navigator.push(context, AppRouter.slideRoute(WorkoutDetailScreen(workoutPlan: plan)));
      },
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusThumbnail),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: AppTheme.primaryLight,
                    child: const Icon(Icons.fitness_center_rounded, color: AppTheme.primary, size: 24),
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              plan.difficulty,
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            plan.goal,
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
                  onSelected: (action) async {
                    if (action == 'edit') {
                      Navigator.push(context, AppRouter.slideRoute(WorkoutDetailScreen(workoutPlan: plan)));
                    } else if (action == 'duplicate') {
                      await workoutVm.duplicateWorkout(plan);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Workout plan duplicated'), backgroundColor: AppTheme.success),
                        );
                      }
                    } else if (action == 'delete') {
                      _confirmDelete(context, workoutVm, plan);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'duplicate', child: Row(children: [Icon(Icons.copy, size: 16), SizedBox(width: 8), Text('Duplicate')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: AppTheme.danger), SizedBox(width: 8), Text('Delete')])),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Weekly schedule preview
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Weekly Schedule:',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted),
                ),
                Row(
                  children: List.generate(days.length, (idx) {
                    final dayName = days[idx];
                    final letter = dayLetters[idx];
                    final hasWorkout = plan.schedule[dayName]?.isNotEmpty == true;

                    return Container(
                      margin: const EdgeInsets.only(left: 4),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasWorkout ? AppTheme.primary : AppTheme.surfaceGray,
                        border: Border.all(color: hasWorkout ? AppTheme.primary : AppTheme.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        letter,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: hasWorkout ? Colors.white : AppTheme.textSecondary,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WorkoutViewModel vm, WorkoutPlan plan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Workout Plan'),
        content: Text('Are you sure you want to delete "${plan.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              await vm.deleteWorkout(plan.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Workout plan deleted'), backgroundColor: AppTheme.danger),
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
