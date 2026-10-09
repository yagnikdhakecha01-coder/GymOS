import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import 'role_selection_screen.dart';
import '../../core/navigation/app_router.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/user_profile.dart';
import '../dashboard/main_navigation_holder.dart';
import '../staff/portal/staff_shell.dart';
import '../receptionist/portal/receptionist_shell.dart';
import '../member_app/screens/member_shell.dart';
import '../member_app/screens/member_code_screen.dart';
import '../error/configuration_error_screen.dart';
import 'auth_viewmodel.dart';
import 'first_time_setup_screen.dart';
import 'gym_role_selector_screen.dart';
import 'biometric_lock_screen.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/version_check_service.dart';

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Note: Version update dialog is handled gracefully by VersionCheckEngine without blocking app startup.

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
              VersionCheckEngine.scheduleCheckAfterAppLoad();
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

      final currentRoleStr = (authVm.selectedRole ?? authVm.storage.getUserRole() ?? '').toLowerCase();

      // Only check unlinked for staff/member, NEVER owner
      if (currentRoleStr == 'staff' || currentRoleStr == 'member') {
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

      // Filter associations by the user's selected role
      final matchingAssocs = authVm.userAssociations.where((a) {
        if (currentRoleStr == 'owner') return a.role == UserRole.owner;
        if (currentRoleStr == 'staff') return a.role == UserRole.staff;
        if (currentRoleStr == 'member') return a.role == UserRole.member;
        return false;
      }).toList();

      if (matchingAssocs.length > 1 && authVm.activeAssociation == null) {
        nextScreen = const GymRoleSelectorScreen();
      } else if (matchingAssocs.isEmpty) {
        if (currentRoleStr == 'owner') {
          final savedGym = authVm.storage.getGymInfo();
          if (savedGym != null) {
            nextScreen = const MainNavigationHolder();
          } else {
            nextScreen = const FirstTimeSetupScreen();
          }
        } else if (currentRoleStr == 'staff' || currentRoleStr == 'member') {
          // If member or staff has not completed invitation code verification,
          // ALWAYS route to MemberCodeScreen so they enter their invitation code.
          nextScreen = const MemberCodeScreen();
        } else {
          nextScreen = const RoleSelectionScreen();
        }
      } else {
        // User has at least 1 valid association for the selected role
        final assoc = matchingAssocs.first;
        if (authVm.activeAssociation?.gymId != assoc.gymId || authVm.activeAssociation?.role != assoc.role) {
          await authVm.selectAssociation(assoc);
        }

        final profile = authVm.currentProfile;
        Widget targetScreen;
        if (currentRoleStr == 'owner') {
          if (profile?.setupCompleted == true || authVm.storage.getGymInfo() != null) {
            targetScreen = const MainNavigationHolder();
          } else {
            targetScreen = const FirstTimeSetupScreen();
          }
        } else if (currentRoleStr == 'staff') {
          final staffRole = authVm.staffRecord?.role.toLowerCase() ?? '';
          if (staffRole.contains('reception')) {
            targetScreen = const ReceptionistShell();
          } else {
            targetScreen = const StaffShell();
          }
        } else if (currentRoleStr == 'member') {
          targetScreen = const MemberShell();
        } else {
          targetScreen = const RoleSelectionScreen();
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
      VersionCheckEngine.scheduleCheckAfterAppLoad();
    } catch (e) {
      debugPrint('SplashScreen _verifyAndRoute error fallback: $e');
      if (mounted) {
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        if (authVm.isLoggedIn || authVm.storage.isLoggedIn()) {
          final roleStr = (authVm.selectedRole ?? authVm.storage.getUserRole() ?? '').toLowerCase();
          final hasSavedGym = authVm.storage.getGymInfo() != null;
          final hasCachedMember = authVm.storage.hasKey('member_cached_id') || authVm.storage.getString('member_id') != null;
          final hasCachedStaff = authVm.storage.hasKey('gymos_offline_staff_cache');

          if (roleStr == 'owner') {
            Navigator.pushReplacement(
              context,
              AppRouter.scaleRoute(hasSavedGym ? const MainNavigationHolder() : const FirstTimeSetupScreen()),
            );
            VersionCheckEngine.scheduleCheckAfterAppLoad();
            return;
          } else if (roleStr == 'staff') {
            Navigator.pushReplacement(
              context,
              AppRouter.scaleRoute((hasSavedGym || hasCachedStaff) ? const StaffShell() : const MemberCodeScreen()),
            );
            VersionCheckEngine.scheduleCheckAfterAppLoad();
            return;
          } else if (roleStr == 'member') {
            Navigator.pushReplacement(
              context,
              AppRouter.scaleRoute((hasSavedGym || hasCachedMember) ? const MemberShell() : const MemberCodeScreen()),
            );
            VersionCheckEngine.scheduleCheckAfterAppLoad();
            return;
          }
        }
        Navigator.pushReplacement(context, AppRouter.scaleRoute(const RoleSelectionScreen()));
        VersionCheckEngine.scheduleCheckAfterAppLoad();
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
