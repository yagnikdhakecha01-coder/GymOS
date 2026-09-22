import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import 'gym_info_screen.dart';
import 'fitness_goals_screen.dart';
import 'custom_fields_screen.dart';
import 'staff_management_menu_screen.dart';
import '../workout/workout_plans_screen.dart';
import '../diet/diet_plans_screen.dart';
import '../membership/membership_plans_screen.dart';
import '../attendance/owner_settings_screen.dart';
import 'online_database_screen.dart';
import 'custom_branding_screen.dart';
import 'gym_rules_settings_screen.dart';

class GymSettingsMenuScreen extends StatelessWidget {
  const GymSettingsMenuScreen({super.key});

  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget targetScreen,
  }) {
    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => targetScreen),
        );
      },
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gym Settings'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header description card
              CustomCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.settings_suggest_rounded, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Configure your gym settings here. Set up gym timings, custom fitness goals, and add custom fields to the member registration forms before adding members.',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Settings Group Card
              CustomCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // 1. Gym Information
                    _buildMenuTile(
                      context,
                      icon: Icons.business_rounded,
                      color: AppTheme.primary,
                      title: 'Gym Information',
                      subtitle: 'Edit gym name, logo, timing, and address',
                      targetScreen: const GymInfoScreen(),
                    ),
                    const Divider(height: 1),

                    // 2. Membership Plans
                    _buildMenuTile(
                      context,
                      icon: Icons.card_membership_rounded,
                      color: AppTheme.warning,
                      title: 'Membership Plans',
                      subtitle: 'Set up pricing & billing terms',
                      targetScreen: const MembershipPlansScreen(),
                    ),
                    const Divider(height: 1),

                    // 3. Staff Management
                    _buildMenuTile(
                      context,
                      icon: Icons.people_outline_rounded,
                      color: AppTheme.primary,
                      title: 'Staff Management',
                      subtitle: 'Manage staff, roles and permissions',
                      targetScreen: const StaffManagementMenuScreen(),
                    ),
                    const Divider(height: 1),

                    // 4. Fitness Goals
                    _buildMenuTile(
                      context,
                      icon: Icons.emoji_events_outlined,
                      color: AppTheme.success,
                      title: 'Fitness Goals',
                      subtitle: 'Create & manage dynamic workout goals',
                      targetScreen: const FitnessGoalsScreen(),
                    ),
                    const Divider(height: 1),

                    // 5. Workout Plans
                    _buildMenuTile(
                      context,
                      icon: Icons.fitness_center_rounded,
                      color: Colors.orange,
                      title: 'Workout Plans',
                      subtitle: 'Manage client workout schedules',
                      targetScreen: const WorkoutPlansScreen(),
                    ),
                    const Divider(height: 1),

                    // 6. Diet Plans
                    _buildMenuTile(
                      context,
                      icon: Icons.restaurant_rounded,
                      color: AppTheme.success,
                      title: 'Diet Plans',
                      subtitle: 'Manage client meal plans',
                      targetScreen: const DietPlansScreen(),
                    ),
                    const Divider(height: 1),

                    // 7. Custom Member Form
                    _buildMenuTile(
                      context,
                      icon: Icons.assignment_ind_outlined,
                      color: AppTheme.warning,
                      title: 'Custom Member Form',
                      subtitle: 'Add custom fields to member registration form',
                      targetScreen: const CustomFieldsScreen(),
                    ),
                    const Divider(height: 1),

                    // 8. Attendance Configuration
                    _buildMenuTile(
                      context,
                      icon: Icons.co_present_rounded,
                      color: Colors.purple,
                      title: 'Attendance Settings',
                      subtitle: 'SSID rules, static QR and display links',
                      targetScreen: const OwnerQrSettingsScreen(),
                    ),
                    const Divider(height: 1),

                    // 9. Custom App Branding
                    _buildMenuTile(
                      context,
                      icon: Icons.branding_watermark_rounded,
                      color: Colors.teal,
                      title: 'Custom App Branding',
                      subtitle: 'Custom name & logo whitelabel settings',
                      targetScreen: const CustomBrandingScreen(),
                    ),
                    const Divider(height: 1),

                    // 10. Gym Rules & Member Agreements
                    _buildMenuTile(
                      context,
                      icon: Icons.gavel_rounded,
                      color: const Color(0xFF6366F1),
                      title: 'Gym Rules & Member Agreements',
                      subtitle: 'Official gym rules & audit history of agreed members',
                      targetScreen: const GymRulesSettingsScreen(),
                    ),
                    const Divider(height: 1),

                    // 11. Online Database Status
                    _buildMenuTile(
                      context,
                      icon: Icons.cloud_sync_rounded,
                      color: Colors.blue,
                      title: 'Online Database',
                      subtitle: 'View sync status, queue size, and retry operations',
                      targetScreen: const OnlineDatabaseScreen(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
