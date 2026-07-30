import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/models/gym_setup.dart';
import 'gym_settings_viewmodel.dart';
import '../../core/widgets/save_success_screen.dart';

class FitnessGoalsScreen extends StatefulWidget {
  const FitnessGoalsScreen({super.key});

  @override
  State<FitnessGoalsScreen> createState() => _FitnessGoalsScreenState();
}

class _FitnessGoalsScreenState extends State<FitnessGoalsScreen> {
  bool _isLoading = false;

  void _showAddEditDialog(BuildContext context, GymSettingsViewModel vm, [FitnessGoal? goal]) {
    final nameController = TextEditingController(text: goal?.name ?? '');
    final descController = TextEditingController(text: goal?.description ?? '');
    
    String selectedIcon = goal?.icon ?? '💪';
    String selectedColor = goal?.color ?? '0xFF7C3AED';

    final colors = [
      '0xFF7C3AED', // Purple
      '0xFFEF4444', // Red
      '0xFF10B981', // Green
      '0xFF3B82F6', // Blue
      '0xFFF59E0B', // Orange
      '0xFFEC4899', // Pink
      '0xFF06B6D4', // Cyan
    ];

    final emojis = ['💪', '📉', '📈', '🧘', '🏃', '🏋️', '🚴', '🥗', '⚡', '🏆'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(goal == null ? 'Add Fitness Goal' : 'Edit Fitness Goal', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Goal Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(controller: nameController, decoration: const InputDecoration(hintText: 'e.g. Fat Loss')),
                const SizedBox(height: 14),

                Text('Description', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(controller: descController, decoration: const InputDecoration(hintText: 'e.g. Lose fat and build stamina')),
                const SizedBox(height: 14),

                // Icon Picker
                Text('Select Icon', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: emojis.map((emoji) {
                    final isSelected = selectedIcon == emoji;
                    return InkWell(
                      onTap: () => setDialogState(() => selectedIcon = emoji),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryLight : Colors.transparent,
                          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 18)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Color Picker
                Text('Select Color', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors.map((colStr) {
                    final isSelected = selectedColor == colStr;
                    final colorVal = Color(int.parse(colStr));
                    return InkWell(
                      onTap: () => setDialogState(() => selectedColor = colStr),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorVal,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)] : null,
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name is required'), backgroundColor: AppTheme.danger),
                  );
                  return;
                }
                
                final id = goal?.id ?? 'goal_${DateTime.now().millisecondsSinceEpoch}';
                final updatedGoal = FitnessGoal(
                  id: id,
                  name: nameController.text.trim(),
                  icon: selectedIcon,
                  color: selectedColor,
                  description: descController.text.trim(),
                );

                setState(() => _isLoading = true);
                Navigator.pop(context);
                await vm.saveGoal(updatedGoal);
                setState(() => _isLoading = false);
                
                if (mounted) {
                  SaveSuccessScreen.show(
                    context,
                    title: 'Save Successful',
                    message: goal == null
                        ? 'Fitness Goal has been added successfully.'
                        : 'Fitness Goal has been updated successfully.',
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteConfirm(BuildContext context, GymSettingsViewModel vm, FitnessGoal goal) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Goal?'),
        content: Text('Are you sure you want to delete the goal "${goal.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              setState(() => _isLoading = true);
              Navigator.pop(context);
              await vm.deleteGoal(goal.id);
              setState(() => _isLoading = false);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fitness Goal deleted'), backgroundColor: AppTheme.success),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<GymSettingsViewModel>(context);
    final list = vm.goals;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Fitness Goals'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primary, size: 28),
            onPressed: () => _showAddEditDialog(context, vm),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.emoji_events_outlined, size: 64, color: AppTheme.textMuted.withOpacity(0.4)),
                          const SizedBox(height: 16),
                          Text('No Fitness Goals Yet', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                          const SizedBox(height: 6),
                          Text('Tap the "+" button to add your first custom gym workout goal.', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final item = list[index];
                      Color colorVal;
                      try {
                        colorVal = Color(int.parse(item.color));
                      } catch (_) {
                        colorVal = AppTheme.primary;
                      }

                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: colorVal.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(item.icon, style: const TextStyle(fontSize: 20)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                  if (item.description.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(item.description, style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary)),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: AppTheme.textSecondary, size: 20),
                              onPressed: () => _showAddEditDialog(context, vm, item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                              onPressed: () => _deleteConfirm(context, vm, item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
