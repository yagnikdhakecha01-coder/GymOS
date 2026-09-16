import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_card.dart';
import '../gym_settings/gym_settings_viewmodel.dart';
import 'workout_viewmodel.dart';
import '../../core/models/workout_plan.dart';
import '../../core/services/supabase_service.dart';
import '../../core/widgets/save_success_screen.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final WorkoutPlan? workoutPlan;

  const WorkoutDetailScreen({Key? key, this.workoutPlan}) : super(key: key);

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  String _selectedGoal = 'Fitness';
  String _selectedDiff = 'Beginner';
  
  // Weekly schedule map
  late Map<String, List<ScheduledWorkout>> _schedule;
  
  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final List<String> _dayTypes = [
    'Chest Day',
    'Back Day',
    'Leg Day',
    'Shoulder Day',
    'Bicep Day',
    'Tricep Day',
    'Arms Day',
    'Abs & Core',
    'Cardio & Steam',
    'Aerobics Day',
    'HIIT Cardio',
    'CrossFit',
    'Yoga Day',
    'Stretching & Mobility',
    'Full Body Workout',
    'Upper Body',
    'Lower Body',
    'Push Day',
    'Pull Day',
    'Rest Day',
  ];

  @override
  void initState() {
    super.initState();
    
    if (widget.workoutPlan != null) {
      final p = widget.workoutPlan!;
      _titleController.text = p.title;
      _descController.text = p.description;
      _selectedGoal = p.goal;
      _selectedDiff = p.difficulty;
      
      // Deep copy schedule
      _schedule = {};
      for (final day in _days) {
        final existing = p.schedule[day] ?? [];
        if (existing.isNotEmpty) {
          _schedule[day] = List.from(existing);
        } else {
          _schedule[day] = [ScheduledWorkout(title: '', description: '')];
        }
      }
    } else {
      _schedule = {
        for (final day in _days) day: [ScheduledWorkout(title: '', description: '')],
      };
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a plan title'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final workoutVm = Provider.of<WorkoutViewModel>(context, listen: false);
    final id = widget.workoutPlan?.id ?? SupabaseService.generateUuidV4();

    // Clean up empty routines per day
    final Map<String, List<ScheduledWorkout>> cleanedSchedule = {};
    for (final day in _days) {
      final list = _schedule[day] ?? [];
      final validWorkouts = list.where((w) => w.title.trim().isNotEmpty).toList();
      cleanedSchedule[day] = validWorkouts;
    }

    final newPlan = WorkoutPlan(
      id: id,
      title: _titleController.text.trim(),
      goal: _selectedGoal,
      difficulty: _selectedDiff,
      description: _descController.text.trim(),
      schedule: cleanedSchedule,
    );

    final error = await workoutVm.saveWorkout(newPlan);
    if (mounted) {
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ $error'),
            backgroundColor: AppTheme.danger,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        Navigator.pop(context);
        SaveSuccessScreen.show(
          context,
          title: 'Save Successful',
          message: 'Workout plan has been saved to the database.',
        );
      }
    }
  }

  List<String> _getDropdownOptions(String? currentVal) {
    final options = List<String>.from(_dayTypes);
    if (currentVal != null && currentVal.isNotEmpty && !options.contains(currentVal)) {
      options.insert(0, currentVal);
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    // Retrieve dynamic goals from Setup ViewModel
    final settingsVm = Provider.of<GymSettingsViewModel>(context);
    final goalsList = settingsVm.goals.map((e) => e.name).toList();
    if (!goalsList.contains(_selectedGoal)) {
      if (_selectedGoal.isNotEmpty) {
        goalsList.insert(0, _selectedGoal);
      } else if (goalsList.isNotEmpty) {
        _selectedGoal = goalsList.first;
      } else {
        goalsList.add('Fitness');
        _selectedGoal = 'Fitness';
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.workoutPlan == null ? 'New Workout Plan' : 'Edit Workout Plan'),
        actions: [
          IconButton(icon: const Icon(Icons.check, size: 28, color: AppTheme.primary), onPressed: _save),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Basic Info Card
                      CustomCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Plan Title *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _titleController,
                              decoration: const InputDecoration(hintText: 'e.g. Intermediate Fat Loss'),
                            ),
                            const SizedBox(height: 14),

                            Text('Description', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _descController,
                              maxLines: 2,
                              decoration: const InputDecoration(hintText: 'e.g. High intensity interval training & cardio combination'),
                            ),
                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Goal *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<String>(
                                        value: _selectedGoal,
                                        isExpanded: true,
                                        items: goalsList.map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
                                        onChanged: (val) {
                                          if (val != null) setState(() => _selectedGoal = val);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Difficulty *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<String>(
                                        value: _selectedDiff,
                                        isExpanded: true,
                                        items: ['Beginner', 'Intermediate', 'Advanced'].map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
                                        onChanged: (val) {
                                          if (val != null) setState(() => _selectedDiff = val);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Weekly Schedule Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Weekly Schedule',
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          Text(
                            'Tap + to add multiple routines',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // List of Days with Multi-Routine support
                      CustomCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          children: List.generate(_days.length, (dayIdx) {
                            final day = _days[dayIdx];
                            final list = _schedule[day] ?? [ScheduledWorkout(title: '', description: '')];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (dayIdx > 0) const Divider(height: 24, color: AppTheme.border),
                                // Day Header Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryLight.withOpacity(0.35),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            day.substring(0, 3).toUpperCase(),
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          day,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // + Add Routine Button
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (_schedule[day] == null) {
                                            _schedule[day] = [];
                                          }
                                          _schedule[day]!.add(ScheduledWorkout(title: '', description: ''));
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.add_rounded, size: 14, color: AppTheme.primary),
                                            const SizedBox(width: 3),
                                            Text(
                                              'Add Routine',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                // List of Routines for this Day
                                ...List.generate(list.length, (routineIdx) {
                                  final routine = list[routineIdx];
                                  final currentVal = routine.title.isNotEmpty ? routine.title : null;
                                  final options = _getDropdownOptions(currentVal);
                                  final validatedVal = options.contains(currentVal) ? currentVal : null;

                                  return Padding(
                                    padding: EdgeInsets.only(bottom: routineIdx < list.length - 1 ? 8.0 : 0.0),
                                    child: Row(
                                      children: [
                                        if (list.length > 1)
                                          Container(
                                            margin: const EdgeInsets.only(right: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.surfaceGray,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '#${routineIdx + 1}',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ),
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: validatedVal,
                                            hint: Text(
                                              list.length > 1
                                                  ? 'Select Routine ${routineIdx + 1}'
                                                  : 'Select Routine',
                                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                                            ),
                                            isExpanded: true,
                                            decoration: InputDecoration(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: const BorderSide(color: AppTheme.border),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: const BorderSide(color: AppTheme.border),
                                              ),
                                            ),
                                            items: options.map((type) {
                                              return DropdownMenuItem<String>(
                                                value: type,
                                                child: Text(type, style: GoogleFonts.inter(fontSize: 13)),
                                              );
                                            }).toList(),
                                            onChanged: (newVal) {
                                              if (newVal != null) {
                                                setState(() {
                                                  _schedule[day]![routineIdx] = ScheduledWorkout(
                                                    title: newVal,
                                                    description: routine.description,
                                                  );
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                        if (list.length > 1 || (list.length == 1 && routine.title.isNotEmpty)) ...[
                                          const SizedBox(width: 6),
                                          IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                                            splashRadius: 16,
                                            tooltip: 'Remove',
                                            onPressed: () {
                                              setState(() {
                                                if (_schedule[day]!.length > 1) {
                                                  _schedule[day]!.removeAt(routineIdx);
                                                } else {
                                                  _schedule[day]![0] = ScheduledWorkout(title: '', description: '');
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
