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
    'Leg Day',
    'Shoulder Day',
    'Rest Day',
    'Back Day',
    'Tricep Day',
    'Cardio & Steam',
    'Aerobics Day',
    'Yoga Day',
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
      p.schedule.forEach((key, list) {
        _schedule[key] = List.from(list);
      });
    } else {
      _schedule = {
        'Monday': [],
        'Tuesday': [],
        'Wednesday': [],
        'Thursday': [],
        'Friday': [],
        'Saturday': [],
        'Sunday': [],
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
    final newPlan = WorkoutPlan(
      id: id,
      title: _titleController.text.trim(),
      goal: _selectedGoal,
      difficulty: _selectedDiff,
      description: _descController.text.trim(),
      schedule: _schedule,
    );

    final error = await workoutVm.saveWorkout(newPlan);
    if (mounted) {
      if (error != null) {
        // Show the exact error so user can report it
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

  @override
  Widget build(BuildContext context) {
    // Retrieve dynamic goals from Setup ViewModel
    final settingsVm = Provider.of<GymSettingsViewModel>(context);
    final goalsList = settingsVm.goals.map((e) => e.name).toList();
    if (!goalsList.contains(_selectedGoal)) {
      if (goalsList.isNotEmpty) {
        _selectedGoal = goalsList.first;
      } else {
        goalsList.add('Fitness');
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
                            'Swipe to change days',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Vertical List of Days
                      CustomCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          children: _days.map((day) {
                            final list = _schedule[day] ?? [];
                            final currentDayVal = list.isNotEmpty ? list.first.title : null;
                            final validatedVal = _dayTypes.contains(currentDayVal) ? currentDayVal : null;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      day,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: validatedVal,
                                      hint: Text('Select Routine', style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textMuted)),
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
                                      items: _dayTypes.map((type) {
                                        return DropdownMenuItem<String>(
                                          value: type,
                                          child: Text(type, style: GoogleFonts.inter(fontSize: 13.5)),
                                        );
                                      }).toList(),
                                      onChanged: (newVal) {
                                        if (newVal != null) {
                                          setState(() {
                                            _schedule[day] = [
                                              ScheduledWorkout(title: newVal, description: '')
                                            ];
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
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
