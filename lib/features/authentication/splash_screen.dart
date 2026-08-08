import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import 'role_selection_screen.dart';
import '../../core/navigation/app_router.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/models/user_profile.dart';
import '../dashboard/main_navigation_holder.dart';
import '../staff/portal/staff_shell.dart';
import '../receptionist/portal/receptionist_shell.dart';
import '../member_app/screens/member_shell.dart';
import '../error/configuration_error_screen.dart';
import 'auth_viewmodel.dart';
import 'first_time_setup_screen.dart';
import 'gym_role_selector_screen.dart';
import '../member_app/screens/member_code_screen.dart';
import 'data_sync_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();

    if (SupabaseService.isInitialized && !SupabaseService.hasError && SupabaseService.client.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _verifyAndRoute(context);
        }
      });
    } else {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          if (!SupabaseService.isInitialized || SupabaseService.hasError) {
            Navigator.pushReplacement(
              context,
              AppRouter.scaleRoute(const ConfigurationErrorScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              AppRouter.scaleRoute(const RoleSelectionScreen()),
            );
          }
        }
      });
    }
  }

  Future<void> _verifyAndRoute(BuildContext context) async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      await authVm.loadCurrentProfile(); // Sync profile state
      
      if (authVm.userAssociations.length > 1 && authVm.activeAssociation == null) {
        if (mounted) {
          Navigator.pushReplacement(context, AppRouter.scaleRoute(const GymRoleSelectorScreen()));
        }
        return;
      }

      if (authVm.userAssociations.isEmpty) {
        if (mounted) {
          final role = authVm.selectedRole ?? '';
          if (role == 'owner') {
            Navigator.pushReplacement(context, AppRouter.scaleRoute(const FirstTimeSetupScreen()));
          } else {
            Navigator.pushReplacement(context, AppRouter.scaleRoute(const MemberCodeScreen()));
          }
        }
      } else {
        if (mounted) {
          final profile = authVm.currentProfile!;
          Widget targetScreen;
          bool shouldSync = false;
          switch (profile.role) {
            case UserRole.owner:
              if (profile.setupCompleted) {
                targetScreen = const MainNavigationHolder();
                shouldSync = true;
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
              shouldSync = true;
              break;
            case UserRole.member:
              targetScreen = const MemberShell();
              shouldSync = true;
              break;
          }
          Navigator.pushReplacement(
            context,
            AppRouter.scaleRoute(shouldSync ? DataSyncScreen(targetScreen: targetScreen) : targetScreen),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pushReplacement(context, AppRouter.scaleRoute(const RoleSelectionScreen()));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.fitness_center_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  'GYMOS',
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Stronger Every Day',
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
