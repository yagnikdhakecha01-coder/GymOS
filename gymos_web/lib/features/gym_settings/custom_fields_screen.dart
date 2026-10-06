import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/models/gym_setup.dart';
import 'gym_settings_viewmodel.dart';

class CustomFieldsScreen extends StatefulWidget {
  const CustomFieldsScreen({super.key});

  @override
  State<CustomFieldsScreen> createState() => _CustomFieldsScreenState();
}

class _CustomFieldsScreenState extends State<CustomFieldsScreen> {
  bool _isLoading = false;

  void _showAddEditDialog(BuildContext context, GymSettingsViewModel vm, [CustomField? field]) {
    final labelController = TextEditingController(text: field?.label ?? '');
    final optionController = TextEditingController();
    
    String selectedType = field?.fieldType ?? 'Text';
    bool isRequired = field?.required ?? false;
    bool isVisible = field?.visible ?? true;
    List<String> options = List.from(field?.options ?? []);

    final fieldTypes = ['Text', 'Number', 'Date', 'Dropdown', 'Checkbox', 'Switch', 'Paragraph', 'Photo'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(field == null ? 'Add Custom Field' : 'Edit Custom Field', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Field Label *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(controller: labelController, decoration: const InputDecoration(hintText: 'e.g. Height (feet)')),
                const SizedBox(height: 14),

                Text('Field Type *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: fieldTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedType = val);
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Options builder for Dropdown and Checkbox
                if (selectedType == 'Dropdown' || selectedType == 'Checkbox') ...[
                  Row(
                    children: [
                      Text('Options *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: TextField(
                            controller: optionController,
                            decoration: const InputDecoration(hintText: 'Add option...'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: AppTheme.primary, size: 28),
                        onPressed: () {
                          final opt = optionController.text.trim();
                          if (opt.isNotEmpty) {
                            setDialogState(() {
                              options.add(opt);
                              optionController.clear();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: options.map((opt) {
                      return Chip(
                        label: Text(opt),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () {
                          setDialogState(() => options.remove(opt));
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                ],

                // Settings Switches
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Required Field', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    Switch(
                      value: isRequired,
                      activeColor: AppTheme.primary,
                      onChanged: (val) => setDialogState(() => isRequired = val),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Visible in Form', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    Switch(
                      value: isVisible,
                      activeColor: AppTheme.primary,
                      onChanged: (val) => setDialogState(() => isVisible = val),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (labelController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Label is required'), backgroundColor: AppTheme.danger),
                  );
                  return;
                }
                if ((selectedType == 'Dropdown' || selectedType == 'Checkbox') && options.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('At least one option is required'), backgroundColor: AppTheme.danger),
                  );
                  return;
                }

                final id = field?.id ?? 'cf_${DateTime.now().millisecondsSinceEpoch}';
                final newField = CustomField(
                  id: id,
                  label: labelController.text.trim(),
                  fieldType: selectedType,
                  options: options,
                  required: isRequired,
                  visible: isVisible,
                );

                setState(() => _isLoading = true);
                Navigator.pop(context);
                await vm.saveCustomField(newField);
                setState(() => _isLoading = false);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(field == null ? 'Custom field added!' : 'Custom field updated!'),
                      backgroundColor: AppTheme.success,
                    ),
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

  void _deleteConfirm(BuildContext context, GymSettingsViewModel vm, CustomField field) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Custom Field?'),
        content: Text('Are you sure you want to delete "${field.label}"? This field will no longer appear on new registration forms.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              setState(() => _isLoading = true);
              Navigator.pop(context);
              await vm.deleteCustomField(field.id);
              setState(() => _isLoading = false);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Custom field deleted'), backgroundColor: AppTheme.success),
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
    final list = vm.customFields;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Custom Member Form'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primary, size: 28),
            onPressed: () => _showAddEditDialog(context, vm),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_ind_outlined, size: 64, color: AppTheme.textMuted.withOpacity(0.4)),
                              const SizedBox(height: 16),
                              Text('No Custom Fields Yet', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                              const SizedBox(height: 6),
                              Text('Add custom questions (like "Emergency Contact" or "Blood Group") to the registration form.', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textMuted)),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final item = list[index];

                          return CustomCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.short_text_rounded, color: AppTheme.primary, size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(item.label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                          if (item.required) ...[
                                            const SizedBox(width: 4),
                                            const Text('*', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Type: ${item.fieldType} • Status: ${item.visible ? "Visible" : "Hidden"}',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
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
        ),
      ),
    );
  }
}
