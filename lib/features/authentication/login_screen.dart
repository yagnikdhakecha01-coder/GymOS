import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/navigation/app_router.dart';
import 'auth_viewmodel.dart';
import '../../core/models/user_profile.dart';
import 'signup_screen.dart';
import 'first_time_setup_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/main_navigation_holder.dart';
import '../staff/portal/staff_shell.dart';
import '../receptionist/portal/receptionist_shell.dart';
import '../member_app/screens/member_shell.dart';
import '../members/members_screen.dart';
import '../staff/staff_screen.dart';
import '../finance/finance_screen.dart';
import '../more/more_screen.dart';
import 'gym_role_selector_screen.dart';
import '../member_app/screens/member_code_screen.dart';
import '../member_app/member_app_viewmodel.dart';
import 'role_selection_screen.dart';
import '../../core/widgets/app_branding_header.dart';
import '../../core/services/supabase_service.dart';

import '../../core/services/rate_limiter_service.dart';

class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _emailEntered = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_passwordController.text.isEmpty) return;

    // Production Rate Limiter: Max 5 attempts per minute
    final lockoutDuration = RateLimiterService().checkLoginRateLimit();
    if (lockoutDuration != null) {
      final secs = lockoutDuration.inSeconds.clamp(1, 60);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text('Too many login attempts. Please wait $secs seconds before trying again.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      await _applySelectedRole(authVm);
      await authVm.login(_emailController.text, _passwordController.text);

      RateLimiterService().resetLoginAttempts();

      if (mounted) {
        setState(() => _isLoading = false);
        await _navigateToRoleDashboard(authVm);
      }
    } catch (e) {
      RateLimiterService().recordFailedLogin();
      if (mounted) {
        setState(() => _isLoading = false);
        String errorMsg = e.toString().replaceAll('AuthException:', '').replaceAll('Exception:', '').trim();
        if (errorMsg.contains('Invalid login credentials')) {
          if (!kIsWeb && Platform.isIOS) {
            errorMsg = 'Invalid credentials. If your account was registered on our Web Portal, please tap "Forgot Password?" below to set your mobile password.';
          } else {
            errorMsg = 'Invalid login credentials. If you registered using Google, please login with Google.';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text(errorMsg),
          ),
        );
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final lockout = RateLimiterService().checkPasswordResetRateLimit();
    if (lockout != null) {
      final mins = lockout.inMinutes.clamp(1, 60);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text('Password reset limit reached (3 per hour). Please try again in $mins minutes.'),
        ),
      );
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text('Please enter a valid email address first.'),
        ),
      );
      return;
    }

    try {
      RateLimiterService().recordPasswordResetAttempt();
      await SupabaseService.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text('Password reset link sent to $email'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text('Failed to send reset email: $e'),
          ),
        );
      }
    }
  }

  Future<void> _applySelectedRole(AuthViewModel authVm) async {
    if (widget.role == 'Gym Owner') {
      await authVm.selectRole('owner');
    } else if (widget.role == 'Gym Staff') {
      await authVm.selectRole('staff');
    } else if (widget.role == 'Gym Member') {
      await authVm.selectRole('member');
    }
  }

  Future<void> _navigateToRoleDashboard(AuthViewModel authVm) async {
    if (!mounted) return;

    if (!authVm.isLoggedIn &&
        SupabaseService.client.auth.currentSession == null) {
      return;
    }

    final selectedRole = authVm.selectedRole ?? (widget.role == 'Gym Owner' ? 'owner' : widget.role == 'Gym Staff' ? 'staff' : 'member');

    var matchingAssocs = authVm.userAssociations.where((a) {
      if (selectedRole == 'owner') return a.role == UserRole.owner;
      if (selectedRole == 'staff') return a.role == UserRole.staff;
      if (selectedRole == 'member') return a.role == UserRole.member;
      return true;
    }).toList();

    // If matchingAssocs is empty right after login/social sign-in, re-sync associations once
    // to give database auto-link triggers time to finish
    if (matchingAssocs.isEmpty && (selectedRole == 'member' || selectedRole == 'staff')) {
      await authVm.loadCurrentProfile();
      matchingAssocs = authVm.userAssociations.where((a) {
        if (selectedRole == 'owner') return a.role == UserRole.owner;
        if (selectedRole == 'staff') return a.role == UserRole.staff;
        if (selectedRole == 'member') return a.role == UserRole.member;
        return true;
      }).toList();
    }

    if (!mounted) return;

    if (matchingAssocs.length > 1) {
      Navigator.pushAndRemoveUntil(
        context,
        AppRouter.scaleRoute(const GymRoleSelectorScreen()),
        (route) => false,
      );
      return;
    }

    Widget targetScreen;

    if (matchingAssocs.isEmpty) {
      if (selectedRole == 'owner') {
        targetScreen = const FirstTimeSetupScreen();
      } else {
        targetScreen = const MemberCodeScreen();
      }
    } else {
      final assoc = matchingAssocs.first;
      if (authVm.activeAssociation?.gymId != assoc.gymId || authVm.activeAssociation?.role != assoc.role) {
        await authVm.selectAssociation(assoc);
      }
      final profile = authVm.currentProfile;

      if (profile == null) {
        if (selectedRole == 'owner') {
          targetScreen = const FirstTimeSetupScreen();
        } else {
          targetScreen = const MemberCodeScreen();
        }
      } else {
        if (profile.role == UserRole.staff || profile.role == UserRole.member) {
          final unlinked = await authVm.forceLogoutIfUnlinked();
          if (unlinked) {
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              AppRouter.scaleRoute(RoleSelectionScreen()),
              (route) => false,
            );
            return;
          }
        }

        switch (profile.role) {
          case UserRole.owner:
            if (profile.setupCompleted) {
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
            try {
              if (mounted) {
                final memberVm = Provider.of<MemberAppViewModel>(context, listen: false);
                await memberVm.loadMemberDataFromSupabase(forceRefresh: true);
              }
            } catch (_) {}
            targetScreen = const MemberShell();
            break;
        }
      }
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      AppRouter.scaleRoute(targetScreen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Login'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
          child: Column(
            children: [
              const SizedBox(height: 32),
              // App Branding Header (Custom logo & Name)
              const AppBrandingHeader(
                logoSize: 64,
                fontSize: 20,
                spacing: 12,
                welcomeText: false,
              ),
              const SizedBox(height: 16),

              if (!_emailEntered) ...[
                // Step 1: Email entry
                Text(
                  'Welcome back!',
                  style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Login to continue to your account',
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 28),

                // Social Login (Google & Apple)
                OutlinedButton(
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    try {
                      final authVm = Provider.of<AuthViewModel>(context, listen: false);
                      await _applySelectedRole(authVm);
                      final signedIn = await authVm.signInWithGoogle();
                      if (!signedIn || !mounted) return;

                      if (!kIsWeb) {
                        await _navigateToRoleDashboard(authVm);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                            content: Text('Google Sign-in failed: $e'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isLoading = false);
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusInput)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('G', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(width: 10),
                      Text('Continue with Google', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                    ],
                  ),
                ),
                if (kIsWeb || Platform.isIOS || Platform.isMacOS) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        final authVm = Provider.of<AuthViewModel>(context, listen: false);
                        await _applySelectedRole(authVm);
                        final signedIn = await authVm.signInWithApple();
                        if (!signedIn || !mounted) return;

                        if (!kIsWeb) {
                          await _navigateToRoleDashboard(authVm);
                        }
                      } catch (e) {
                        if (mounted) {
                          final cleanMsg = e.toString().replaceFirst('Exception: ', '').trim();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                cleanMsg.startsWith('Apple Sign-in failed')
                                    ? cleanMsg
                                    : 'Apple Sign-in failed: $cleanMsg',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isLoading = false);
                        }
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusInput)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.apple, size: 22, color: Colors.black),
                        const SizedBox(width: 8),
                        Text('Continue with Apple', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppTheme.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted)),
                    ),
                    const Expanded(child: Divider(color: AppTheme.border)),
                  ],
                ),
                const SizedBox(height: 20),

                // Email field
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Email', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Enter your email address',
                    prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 24),

                CustomButton(
                  text: 'Next',
                  onPressed: () {
                    if (_emailController.text.isNotEmpty) {
                      setState(() => _emailEntered = true);
                    }
                  },
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account? ", style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                    GestureDetector(
                      onTap: () => Navigator.push(context, AppRouter.slideRoute(const SignupScreen())),
                      child: Text('Sign up', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    ),
                  ],
                ),

              ] else ...[
                // Step 2: Password entry
                Text(
                  'Welcome back!',
                  style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  _emailController.text,
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary),
                ),
                GestureDetector(
                  onTap: () => setState(() => _emailEntered = false),
                  child: Text('Change', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                ),
                const SizedBox(height: 28),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Password', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _handleForgotPassword,
                    child: Text('Forgot Password?', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                  ),
                ),
                if (!kIsWeb && Platform.isIOS)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Tip: If your account was registered on the Web Portal, tap "Forgot Password?" to set your mobile password.',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                const SizedBox(height: 8),

                CustomButton(
                  text: 'Login',
                  isLoading: _isLoading,
                  onPressed: _handleLogin,
                ),
                const SizedBox(height: 24),

                if (widget.role == 'Gym Owner')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Don't have an account? ", style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                      GestureDetector(
                        onTap: () => Navigator.push(context, AppRouter.slideRoute(const SignupScreen())),
                        child: Text('Sign up', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      ),
                    ],
                  ),
              ],

              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.headset_mic_outlined, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Text('Help & Support', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.primary)),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Main App Shell with Bottom Navigation ──
class MainShell extends StatefulWidget {
  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    MembersScreen(),
    StaffScreen(),
    FinanceScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline_rounded), activeIcon: Icon(Icons.people_rounded), label: 'Members'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), activeIcon: Icon(Icons.person_rounded), label: 'Staff'),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Finance'),
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), activeIcon: Icon(Icons.grid_view_rounded), label: 'More'),
          ],
        ),
      ),
    );
  }
}
