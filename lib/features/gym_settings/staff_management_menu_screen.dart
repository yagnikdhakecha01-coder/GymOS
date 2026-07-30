import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../staff/staff_screen.dart';
import '../staff/add_staff_screen.dart';
import 'staff_roles_screen.dart';

class StaffManagementMenuScreen extends StatelessWidget {
  const StaffManagementMenuScreen({super.key});

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

  Widget _buildLockTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
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
      trailing: const Icon(Icons.lock_outline_rounded, color: AppTheme.textMuted, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Staff Management'),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          children: [
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildMenuTile(
                    context,
                    icon: Icons.people_outline_rounded,
                    color: AppTheme.primary,
                    title: 'Staff List',
                    subtitle: 'View and manage all staff members',
                    targetScreen: const StaffScreen(),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.person_add_alt_1_outlined,
                    color: AppTheme.success,
                    title: 'Add Staff',
                    subtitle: 'Add new staff member',
                    targetScreen: const AddStaffScreen(),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.shield_outlined,
                    color: AppTheme.warning,
                    title: 'Staff Roles',
                    subtitle: 'Manage staff roles for your gym',
                    targetScreen: const StaffRolesScreen(),
                  ),
                  const Divider(height: 1),
                  _buildLockTile(
                    icon: Icons.security_outlined,
                    color: AppTheme.textMuted,
                    title: 'Permissions (Coming Soon)',
                    subtitle: 'Manage role based permissions',
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
