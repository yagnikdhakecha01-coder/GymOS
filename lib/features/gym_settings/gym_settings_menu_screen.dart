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
      leading: Container(
        width: AppTheme.iconContainerSize,
        height: AppTheme.iconContainerSize,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusIconContainer),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => targetScreen),
        );
      },
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
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          children: [
            // Quick Info Banner
            CustomCard(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Configure your gym settings here. Set up gym timings, custom fitness goals, and add custom fields to the member registration forms before adding members.',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
