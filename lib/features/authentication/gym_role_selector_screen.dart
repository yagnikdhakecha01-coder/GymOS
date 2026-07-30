import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/navigation/app_router.dart';
import '../../core/models/association_model.dart';
import '../../core/models/user_profile.dart';
import '../dashboard/main_navigation_holder.dart';
import '../staff/portal/staff_shell.dart';
import '../receptionist/portal/receptionist_shell.dart';
import '../member_app/screens/member_shell.dart';
import 'first_time_setup_screen.dart';
import 'role_selection_screen.dart';
import 'auth_viewmodel.dart';

class GymRoleSelectorScreen extends StatelessWidget {
  const GymRoleSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final associations = authVm.userAssociations;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              // Header
              Text(
                'Select Profile',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the gym account you want to enter',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Associations List
              Expanded(
                child: ListView.builder(
                  itemCount: associations.length,
                  itemBuilder: (context, index) {
                    final assoc = associations[index];
                    IconData icon;
                    Color accentColor;

                    switch (assoc.role) {
                      case UserRole.owner:
                        icon = Icons.business_center_rounded;
                        accentColor = AppTheme.primary;
                        break;
                      case UserRole.staff:
                        icon = Icons.badge_rounded;
                        accentColor = AppTheme.warning;
                        break;
                      case UserRole.member:
                        icon = Icons.person_rounded;
                        accentColor = const Color(0xFF10B981);
                        break;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        onTap: () async {
                          await authVm.selectAssociation(assoc);
                          if (context.mounted) {
                            Widget targetScreen;
                            switch (assoc.role) {
                              case UserRole.owner:
                                if (assoc.setupCompleted) {
                                  targetScreen = const MainNavigationHolder();
                                } else {
                                  targetScreen = const FirstTimeSetupScreen();
                                }
                                break;
                              case UserRole.staff:
                                final staffRole = authVm.staffRecord?.role.toLowerCase() ?? '';
                                if (staffRole.contains('reception')) {
                                  targetScreen = const ReceptionistShell();
                                } else {
                                  targetScreen = const StaffShell();
                                }
                                break;
                              case UserRole.member:
                                targetScreen = const MemberShell();
                                break;
                            }
                            Navigator.pushAndRemoveUntil(
                              context,
                              AppRouter.scaleRoute(targetScreen),
                              (route) => false,
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                            border: Border.all(color: AppTheme.border, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(icon, color: accentColor, size: 26),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      assoc.gymName ?? 'GymOS Partner',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: accentColor.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        assoc.role.name.toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: accentColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: AppTheme.textMuted,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Logout Action
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await authVm.logout();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        AppRouter.scaleRoute(const RoleSelectionScreen()),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  label: Text(
                    'Logout / Switch Account',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
