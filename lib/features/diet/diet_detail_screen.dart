import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_card.dart';
import 'diet_viewmodel.dart';
import '../../core/models/diet_plan.dart';
import '../gym_settings/gym_settings_viewmodel.dart';
import '../../core/widgets/save_success_screen.dart';
import '../../core/services/supabase_service.dart';

class DietDetailScreen extends StatefulWidget {
  final DietPlan? dietPlan;

  const DietDetailScreen({Key? key, this.dietPlan}) : super(key: key);

  @override
  State<DietDetailScreen> createState() => _DietDetailScreenState();
}

class _DietDetailScreenState extends State<DietDetailScreen> {
  final _titleController = TextEditingController();
  final _caloriesController = TextEditingController(text: '2000');
  final _notesController = TextEditingController();

   String _selectedGoal = 'Fitness';
  String _status = 'Active';
  List<Meal> _meals = [];

  final _mealNameController = TextEditingController();
  final _mealItemsController = TextEditingController();
  final _mealTimeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.dietPlan != null) {
      final p = widget.dietPlan!;
      _titleController.text = p.title;
      _caloriesController.text = p.calories.toString();
      _notesController.text = p.notes;
      _selectedGoal = p.goal;
      _meals = List.from(p.meals);
      _status = p.status;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _caloriesController.dispose();
    _notesController.dispose();
    _mealNameController.dispose();
    _mealItemsController.dispose();
    _mealTimeController.dispose();
    super.dispose();
  }

  void _addMeal() {
    if (_mealNameController.text.isNotEmpty && _mealItemsController.text.isNotEmpty) {
      setState(() {
        _meals.add(Meal(
          name: _mealNameController.text,
          items: _mealItemsController.text,
          time: _mealTimeController.text,
        ));
        _mealNameController.clear();
        _mealItemsController.clear();
        _mealTimeController.clear();
      });
    }
  }

  Future<void> _saveDietPlan() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a plan title'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final id = widget.dietPlan?.id ?? SupabaseService.generateUuidV4();
    final newPlan = DietPlan(
      id: id,
      title: _titleController.text,
      goal: _selectedGoal,
      calories: int.tryParse(_caloriesController.text) ?? 2000,
      meals: _meals,
      notes: _notesController.text,
      status: _status,
    );

    final dietVm = Provider.of<DietViewModel>(context, listen: false);
    await dietVm.saveDiet(newPlan);

    if (mounted) {
      Navigator.pop(context);
      SaveSuccessScreen.show(
        context,
        title: 'Save Successful',
        message: 'Diet plan has been saved successfully.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.dietPlan != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Diet Plan' : 'Create Diet Plan'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  CustomCard(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Basic Information', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text('Plan Title', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(hintText: 'e.g. High Protein Fat Loss Diet'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Goal', style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    value: _selectedGoal,
                                    items: Provider.of<GymSettingsViewModel>(context, listen: false)
                                        .goals
                                        .map((g) => DropdownMenuItem(value: g.name, child: Text(g.name)))
                                        .toList()
                                      ..insert(0, const DropdownMenuItem(value: 'Fitness', child: Text('Fitness'))),
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
                                  Text('Calories / Day', style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _caloriesController,
                                    keyboardType: TextInputType.number,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Plan Status', style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    value: _status,
                                    items: const [
                                      DropdownMenuItem(value: 'Active', child: Text('Active')),
                                      DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _status = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Notes / Instructions', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(hintText: 'e.g. Drink 4 liters of water daily'),
                        ),
                      ],
                    ),
                  ),

                  // Meals list
                  CustomCard(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Meals Schedule (${_meals.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (_meals.isEmpty)
                          const Center(child: Text('No meals added yet.', style: TextStyle(color: AppTheme.textMuted)))
                        else
                          ..._meals.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final meal = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppTheme.success.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.restaurant, color: AppTheme.success, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(meal.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            Text(meal.time, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                          ],
                                        ),
                                        Text(meal.items, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                                    onPressed: () {
                                      setState(() => _meals.removeAt(idx));
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),

                  // Add Meal
                  CustomCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Add New Meal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: null,
                          hint: const Text('Select meal type'),
                          items: const [
                            DropdownMenuItem(value: 'Breakfast', child: Text('Breakfast')),
                            DropdownMenuItem(value: 'Mid-Morning Snack', child: Text('Mid-Morning Snack')),
                            DropdownMenuItem(value: 'Lunch', child: Text('Lunch')),
                            DropdownMenuItem(value: 'Evening Snack', child: Text('Evening Snack')),
                            DropdownMenuItem(value: 'Dinner', child: Text('Dinner')),
                            DropdownMenuItem(value: 'Pre-Workout', child: Text('Pre-Workout')),
                            DropdownMenuItem(value: 'Post-Workout', child: Text('Post-Workout')),
                          ],
                          onChanged: (val) {
                            if (val != null) _mealNameController.text = val;
                          },
                        ),
                        const SizedBox(height: 12),
                        Text('Food Items', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _mealItemsController,
                          maxLines: 2,
                          decoration: const InputDecoration(hintText: 'e.g. 3 egg whites, oats with berries'),
                        ),
                        const SizedBox(height: 12),
                        Text('Timing', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _mealTimeController,
                          decoration: const InputDecoration(hintText: 'e.g. 08:00 AM'),
                        ),
                        const SizedBox(height: 16),
                        CustomButton(
                          text: 'Add Meal',
                          icon: Icons.add,
                          isPrimary: false,
                          onPressed: _addMeal,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CustomButton(
                text: 'Save Diet Plan',
                onPressed: _saveDietPlan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
