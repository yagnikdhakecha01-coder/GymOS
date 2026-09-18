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
import 'biometric_lock_screen.dart';
import '../../core/services/biometric_service.dart';

import '../../core/widgets/app_branding_header.dart';

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final hasActiveSession = SupabaseService.isInitialized &&
          !SupabaseService.hasError &&
          SupabaseService.client.auth.currentSession != null;
      final hasStoredLogin = authVm.storage.isLoggedIn();

      if (hasActiveSession || hasStoredLogin) {
        _verifyAndRoute(context);
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
    });
  }

  Future<void> _verifyAndRoute(BuildContext context) async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      
      // Silently ensure valid session (refreshes in background if expired)
      await SupabaseService.ensureValidSession();

      try {
        await authVm.loadCurrentProfile();
      } catch (e) {
        debugPrint('loadCurrentProfile network warning: $e');
      }

      // Only check unlinked for staff/member, NEVER owner
      final currentRole = authVm.currentProfile?.role;
      if (currentRole == UserRole.staff || currentRole == UserRole.member) {
        try {
          final unlinked = await authVm.forceLogoutIfUnlinked();
          if (unlinked && mounted) {
            Navigator.pushReplacement(
              context,
              AppRouter.scaleRoute(const RoleSelectionScreen()),
            );
            return;
          }
        } catch (_) {}
      }

      Widget nextScreen;

      if (authVm.userAssociations.length > 1 && authVm.activeAssociation == null) {
        nextScreen = const GymRoleSelectorScreen();
      } else if (authVm.userAssociations.isEmpty) {
        final role = authVm.selectedRole ?? authVm.storage.getUserRole() ?? '';
        if (role == 'owner') {
          final savedGym = authVm.storage.getGymInfo();
          if (savedGym != null) {
            nextScreen = const MainNavigationHolder();
          } else {
            nextScreen = const FirstTimeSetupScreen();
          }
        } else if (role == 'staff') {
          nextScreen = const StaffShell();
        } else if (role == 'member') {
          nextScreen = const MemberShell();
        } else {
          nextScreen = const RoleSelectionScreen();
        }
      } else {
        final profile = authVm.currentProfile;
        Widget targetScreen;
        if (profile == null) {
          final role = authVm.selectedRole ?? authVm.storage.getUserRole() ?? '';
          if (role == 'owner') {
            final savedGym = authVm.storage.getGymInfo();
            targetScreen = savedGym != null ? const MainNavigationHolder() : const FirstTimeSetupScreen();
          } else if (role == 'staff') {
            targetScreen = const StaffShell();
          } else {
            targetScreen = const MemberShell();
          }
        } else {
          switch (profile.role) {
            case UserRole.owner:
              if (profile.setupCompleted || authVm.storage.getGymInfo() != null) {
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
        }
        nextScreen = targetScreen;
      }

      final lockEnabled = await BiometricService.isLockEnabled();
      if (lockEnabled) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            AppRouter.scaleRoute(BiometricLockScreen(targetScreen: nextScreen)),
          );
        }
      } else {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            AppRouter.scaleRoute(nextScreen),
          );
        }
      }
    } catch (e) {
      debugPrint('SplashScreen _verifyAndRoute error fallback: $e');
      if (mounted) {
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        if (authVm.isLoggedIn || authVm.storage.isLoggedIn()) {
          final roleStr = (authVm.selectedRole ?? authVm.storage.getUserRole() ?? '').toLowerCase();
          if (roleStr == 'owner') {
            Navigator.pushReplacement(context, AppRouter.scaleRoute(const MainNavigationHolder()));
            return;
          } else if (roleStr == 'staff') {
            Navigator.pushReplacement(context, AppRouter.scaleRoute(const StaffShell()));
            return;
          } else if (roleStr == 'member') {
            Navigator.pushReplacement(context, AppRouter.scaleRoute(const MemberShell()));
            return;
          }
        }
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
                const AppBrandingHeader(
                  logoSize: 80,
                  fontSize: 32,
                  spacing: 20,
                  welcomeText: false,
                ),
                const SizedBox(height: 10),
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
