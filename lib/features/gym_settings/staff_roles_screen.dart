import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../staff/staff_viewmodel.dart';
import '../authentication/auth_viewmodel.dart';

class StaffRolesScreen extends StatefulWidget {
  const StaffRolesScreen({super.key});

  @override
  State<StaffRolesScreen> createState() => _StaffRolesScreenState();
}

class _StaffRolesScreenState extends State<StaffRolesScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _localRoles = [];

  // Icon Mapping Helper
  IconData _getIconData(String name) {
    switch (name) {
      case 'fitness_center_rounded':
        return Icons.fitness_center_rounded;
      case 'business_center_rounded':
        return Icons.business_center_rounded;
      case 'account_box_rounded':
        return Icons.account_box_rounded;
      case 'calculate_rounded':
        return Icons.calculate_rounded;
      case 'restaurant_menu_rounded':
        return Icons.restaurant_menu_rounded;
      case 'people_rounded':
        return Icons.people_rounded;
      case 'shield_rounded':
        return Icons.shield_rounded;
      case 'home_rounded':
        return Icons.home_rounded;
      case 'music_note_rounded':
        return Icons.music_note_rounded;
      case 'pool_rounded':
        return Icons.pool_rounded;
      case 'spa_rounded':
        return Icons.spa_rounded;
      default:
        return Icons.badge_outlined;
    }
  }

  Color _getIconBgColor(String name) {
    switch (name.toLowerCase()) {
      case 'trainer':
      case 'crossfit coach':
        return const Color(0xFFFEE2E2); // Light Red
      case 'personal trainer':
      case 'cleaner':
        return const Color(0xFFFEF3C7); // Light Orange
      case 'manager':
        return const Color(0xFFFEF3C7); // Light Yellow
      case 'receptionist':
      case 'housekeeping':
      case 'massage therapist':
        return const Color(0xFFF3E8FF); // Light Purple
      case 'yoga trainer':
      case 'nutritionist':
        return const Color(0xFFDCFCE7); // Light Green
      case 'sales executive':
        return const Color(0xFFFCE7F3); // Light Pink
      case 'accountant':
      case 'security':
      case 'swimming coach':
        return const Color(0xFFE0F2FE); // Light Blue
      default:
        return const Color(0xFFF3F4F6); // Light Gray
    }
  }

  Color _getIconColor(String name) {
    switch (name.toLowerCase()) {
      case 'trainer':
      case 'crossfit coach':
        return const Color(0xFFEF4444); // Red
      case 'personal trainer':
      case 'cleaner':
        return const Color(0xFFF59E0B); // Orange
      case 'manager':
        return const Color(0xFFD97706); // Amber
      case 'receptionist':
      case 'housekeeping':
      case 'massage therapist':
        return const Color(0xFFA855F7); // Purple
      case 'yoga trainer':
      case 'nutritionist':
        return const Color(0xFF22C55E); // Green
      case 'sales executive':
        return const Color(0xFFEC4899); // Pink
      case 'accountant':
      case 'security':
      case 'swimming coach':
        return const Color(0xFF0EA5E9); // Blue
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  String _getIconKey(String name) {
    switch (name.toLowerCase()) {
      case 'trainer':
      case 'crossfit coach':
      case 'yoga trainer':
      case 'zumba trainer':
      case 'swimming coach':
      case 'massage therapist':
        return 'fitness_center_rounded';
      case 'manager':
        return 'business_center_rounded';
      case 'receptionist':
      case 'personal trainer':
        return 'account_box_rounded';
      case 'accountant':
        return 'calculate_rounded';
      case 'nutritionist':
        return 'restaurant_menu_rounded';
      default:
        return 'badge_outlined';
    }
  }

  Future<void> _loadRoles() async {
    setState(() => _isLoading = true);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];

    if (gymId != null) {
      await staffVm.fetchRoles(gymId);
      setState(() {
        if (staffVm.staffRoles.isEmpty) {
          final List<String> defaultActiveNames = ['Trainer', 'Personal Trainer', 'Manager', 'Receptionist'];
          final List<String> defaultOptionalNames = [
            'Yoga Trainer', 'CrossFit Coach', 'Nutritionist', 'Sales Executive',
            'Accountant', 'Cleaner', 'Housekeeping', 'Security',
            'Zumba Trainer', 'Swimming Coach', 'Massage Therapist', 'Other'
          ];
          
          _localRoles = [];
          for (var name in defaultActiveNames) {
            _localRoles.add({
              'gym_id': gymId,
              'role_name': name,
              'is_default': true,
              'is_enabled': true,
              'is_custom': false,
              'icon': _getIconKey(name),
            });
          }
          for (var name in defaultOptionalNames) {
            _localRoles.add({
              'gym_id': gymId,
              'role_name': name,
              'is_default': true,
              'is_enabled': false,
              'is_custom': false,
              'icon': _getIconKey(name),
            });
          }
        } else {
          _localRoles = staffVm.staffRoles.map((r) => Map<String, dynamic>.from(r)).toList();
        }
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    try {
      await staffVm.saveRoles(_localRoles);
      setState(() => _isLoading = false);
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save roles: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: AppTheme.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Roles Updated!',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Staff roles have been updated successfully.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to settings menu
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Done', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Add Custom Role Bottom Sheet ---
  void _showAddCustomRoleSheet() {
    final nameController = TextEditingController();
    String selectedIconKey = 'badge_outlined';

    final List<Map<String, dynamic>> icons = [
      {'key': 'fitness_center_rounded', 'icon': Icons.fitness_center_rounded},
      {'key': 'people_rounded', 'icon': Icons.people_rounded},
      {'key': 'business_center_rounded', 'icon': Icons.business_center_rounded},
      {'key': 'calculate_rounded', 'icon': Icons.calculate_rounded},
      {'key': 'home_rounded', 'icon': Icons.home_rounded},
      {'key': 'shield_rounded', 'icon': Icons.shield_rounded},
      {'key': 'restaurant_menu_rounded', 'icon': Icons.restaurant_menu_rounded},
      {'key': 'music_note_rounded', 'icon': Icons.music_note_rounded},
      {'key': 'pool_rounded', 'icon': Icons.pool_rounded},
      {'key': 'spa_rounded', 'icon': Icons.spa_rounded},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Add Custom Role',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Role Name *',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(hintText: 'Enter role name'),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Role Icon',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      // Grid of icons
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1,
                        ),
                        itemCount: icons.length,
                        itemBuilder: (context, idx) {
                          final item = icons[idx];
                          final isSel = selectedIconKey == item['key'];
                          return GestureDetector(
                            onTap: () {
                              setSheetState(() {
                                selectedIconKey = item['key'];
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSel ? AppTheme.primaryLight : AppTheme.surfaceGray,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isSel ? AppTheme.primary : AppTheme.border),
                              ),
                              child: Icon(item['icon'], color: isSel ? AppTheme.primary : AppTheme.textSecondary),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton(
                        onPressed: () async {
                          if (nameController.text.trim().isEmpty) return;
                          Navigator.pop(sheetContext); // Close sheet
                          
                          setState(() => _isLoading = true);
                          final authVm = Provider.of<AuthViewModel>(context, listen: false);
                          final staffVm = Provider.of<StaffViewModel>(context, listen: false);
                          final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    
                          if (gymId != null) {
                            await staffVm.addCustomRole(gymId, nameController.text.trim(), selectedIconKey);
                            await _loadRoles();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text('Add Role', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.border),
                          foregroundColor: AppTheme.textPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filter into groups
    final defaultActive = _localRoles.where((r) => r['is_default'] == true && ['Trainer', 'Personal Trainer', 'Manager', 'Receptionist'].contains(r['role_name'])).toList();
    final defaultOptional = _localRoles.where((r) => r['is_default'] == true && !['Trainer', 'Personal Trainer', 'Manager', 'Receptionist'].contains(r['role_name'])).toList();
    final customRoles = _localRoles.where((r) => r['is_custom'] == true).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Staff Roles'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, size: 20),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Text('Staff Roles', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  content: Text(
                    'Staff roles define the permissions and responsibilities of your gym staff. Default roles (Trainer, Receptionist, Manager) cannot be deleted, but you can create custom roles tailored to your gym operations.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Got It', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20.0),
                    children: [
                      // --- Default Roles ---
                      if (defaultActive.isNotEmpty) ...[
                        _buildSectionHeader('Default Roles', 'These roles are created by default'),
                        const SizedBox(height: 10),
                        CustomCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: List.generate(defaultActive.length, (idx) {
                              final role = defaultActive[idx];
                              return Column(
                                children: [
                                  _buildRoleRow(role),
                                  if (idx < defaultActive.length - 1) const Divider(height: 1),
                                ],
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // --- Optional Predefined Roles ---
                      if (defaultOptional.isNotEmpty) ...[
                        _buildSectionHeader('Additional Roles (Optional)', 'Enable roles you need for your gym'),
                        const SizedBox(height: 10),
                        CustomCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: List.generate(defaultOptional.length, (idx) {
                              final role = defaultOptional[idx];
                              return Column(
                                children: [
                                  _buildRoleRow(role),
                                  if (idx < defaultOptional.length - 1) const Divider(height: 1),
                                ],
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // --- Custom Roles ---
                      if (customRoles.isNotEmpty) ...[
                        _buildSectionHeader('Custom Roles', 'These roles are created by you'),
                        const SizedBox(height: 10),
                        CustomCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: List.generate(customRoles.length, (idx) {
                              final role = customRoles[idx];
                              return Column(
                                children: [
                                  _buildRoleRow(role),
                                  if (idx < customRoles.length - 1) const Divider(height: 1),
                                ],
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // --- Add Custom Role Button ---
                      OutlinedButton(
                        onPressed: _showAddCustomRoleSheet,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primary),
                          foregroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Add Custom Role',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                // --- Bottom Save Actions ---
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  child: ElevatedButton(
                    onPressed: _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      'Save Changes',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildRoleRow(Map<String, dynamic> role) {
    final isEnabled = role['is_enabled'] == true;
    final isDefault = role['is_default'] == true;
    final name = role['role_name'] as String;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          Transform.scale(
            scale: 0.9,
            child: Checkbox(
              value: isEnabled,
              activeColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: (val) {
                setState(() {
                  role['is_enabled'] = val;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getIconBgColor(name),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getIconData(role['icon'] ?? 'badge_outlined'),
              size: 16,
              color: _getIconColor(name),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: isEnabled ? FontWeight.w600 : FontWeight.w500,
                color: isEnabled ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
            ),
          ),
          if (isDefault && ['Trainer', 'Personal Trainer', 'Manager', 'Receptionist'].contains(name)) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Default',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8A56F6),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          const Icon(
            Icons.menu_rounded,
            size: 16,
            color: Color(0xFFD1D5DB),
          ),
        ],
      ),
    );
  }
}
