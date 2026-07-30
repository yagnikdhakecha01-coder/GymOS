import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/models/membership_plan.dart';
import 'membership_viewmodel.dart';

class MembershipDetailScreen extends StatefulWidget {
  final MembershipPlan? plan;

  const MembershipDetailScreen({Key? key, this.plan}) : super(key: key);

  @override
  State<MembershipDetailScreen> createState() => _MembershipDetailScreenState();
}

class _MembershipDetailScreenState extends State<MembershipDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final _customDaysController = TextEditingController();

  String _selectedLogo = '🎟️';
  String _selectedDuration = '30'; // 30, 90, 180, 365, Custom
  String _status = 'Active';
  
  bool _ptIncluded = false;
  bool _dietIncluded = false;
  bool _workoutIncluded = true;

  final List<String> _logos = ['🎟️', '⭐', '💎', '👑', '🎖️', '🔥', '⚡', '🏋️', '🥊'];

  @override
  void initState() {
    super.initState();
    if (widget.plan != null) {
      final p = widget.plan!;
      _nameController.text = p.title;
      _priceController.text = p.price.toStringAsFixed(0);
      _descController.text = p.description;
      _selectedLogo = p.logo;
      _ptIncluded = p.ptIncluded;
      _dietIncluded = p.dietIncluded;
      _workoutIncluded = p.workoutIncluded;
      _status = p.status;

      final daysStr = p.durationDays.toString();
      if (['30', '90', '180', '365'].contains(daysStr)) {
        _selectedDuration = daysStr;
      } else {
        _selectedDuration = 'Custom';
        _customDaysController.text = daysStr;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter plan name'), backgroundColor: AppTheme.danger),
      );
      return;
    }
    if (_priceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter plan price'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    int durationDays = 30;
    if (_selectedDuration == 'Custom') {
      durationDays = int.tryParse(_customDaysController.text) ?? 30;
    } else {
      durationDays = int.parse(_selectedDuration);
    }

    final id = widget.plan?.id ?? 'm_plan_${DateTime.now().millisecondsSinceEpoch}';
    final newPlan = MembershipPlan(
      id: id,
      title: _nameController.text.trim(),
      price: double.tryParse(_priceController.text) ?? 0.0,
      durationMonths: durationDays ~/ 30,
      durationDays: durationDays,
      ptIncluded: _ptIncluded,
      dietIncluded: _dietIncluded,
      workoutIncluded: _workoutIncluded,
      freezeDays: _selectedDuration == '365' ? 30 : (_selectedDuration == '180' ? 15 : 5),
      reminderDays: 5,
      logo: _selectedLogo,
      description: _descController.text.trim(),
      status: _status,
    );

    final membershipVm = Provider.of<MembershipViewModel>(context, listen: false);
    await membershipVm.savePlan(newPlan);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Membership plan saved successfully!'), backgroundColor: AppTheme.success),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.plan != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Membership Plan' : 'New Membership Plan'),
        actions: [
          IconButton(icon: const Icon(Icons.check, size: 28, color: AppTheme.primary), onPressed: _save),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo selector
                Center(
                  child: Column(
                    children: [
                      Text('Plan Logo Icon', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: _logos.map((logo) {
                          final isSelected = _selectedLogo == logo;
                          return InkWell(
                            onTap: () => setState(() => _selectedLogo = logo),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primaryLight : Colors.white,
                                border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(logo, style: const TextStyle(fontSize: 22)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Form Details Card
                CustomCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Plan Name
                      Text('Plan Name *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(hintText: 'e.g. Platinum Annual VIP'),
                      ),
                      const SizedBox(height: 14),

                      // Description
                      Text('Description', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _descController,
                        maxLines: 2,
                        decoration: const InputDecoration(hintText: 'e.g. Unlimited gym access, custom diet & coaching'),
                      ),
                      const SizedBox(height: 14),

                      // Duration & Price
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Duration *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  value: _selectedDuration,
                                  items: const [
                                    DropdownMenuItem(value: '30', child: Text('30 Days')),
                                    DropdownMenuItem(value: '90', child: Text('90 Days')),
                                    DropdownMenuItem(value: '180', child: Text('180 Days')),
                                    DropdownMenuItem(value: '365', child: Text('365 Days')),
                                    DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedDuration = val);
                                    }
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
                                Text('Price (₹) *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _priceController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(hintText: 'e.g. 9999'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      // Custom Duration Input
                      if (_selectedDuration == 'Custom') ...[
                        const SizedBox(height: 14),
                        Text('Custom Duration (Days) *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _customDaysController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'e.g. 45'),
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Status Selector
                      Text('Status *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _status,
                        items: const [
                          DropdownMenuItem(value: 'Active', child: Text('Active')),
                          DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _status = val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Features Switched Card
                CustomCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Plan Features Included', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        title: const Text('Workout Plan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        value: _workoutIncluded,
                        activeColor: AppTheme.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setState(() => _workoutIncluded = val),
                      ),
                      SwitchListTile(
                        title: const Text('Diet Plan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        value: _dietIncluded,
                        activeColor: AppTheme.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setState(() => _dietIncluded = val),
                      ),
                      SwitchListTile(
                        title: const Text('Personal Training (PT)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        value: _ptIncluded,
                        activeColor: AppTheme.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setState(() => _ptIncluded = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                CustomButton(
                  text: 'Save Membership Plan',
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
