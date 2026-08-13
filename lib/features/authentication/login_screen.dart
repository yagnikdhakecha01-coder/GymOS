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
import '../member_app/member_app_viewmodel.dart';
import '../member_app/screens/member_code_screen.dart';
import 'data_sync_screen.dart';
import '../../core/widgets/app_branding_header.dart';

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
    setState(() => _isLoading = true);

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      if (widget.role == 'Gym Owner') {
        await authVm.selectRole('owner');
      } else if (widget.role == 'Gym Staff') {
        await authVm.selectRole('staff');
      } else if (widget.role == 'Gym Member') {
        await authVm.selectRole('member');
      }
      
      await authVm.login(_emailController.text, _passwordController.text);

      if (mounted) {
        setState(() => _isLoading = false);
        await _navigateToRoleDashboard(authVm);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String errorMsg = e.toString().replaceAll('AuthException:', '').replaceAll('Exception:', '').trim();
        if (errorMsg.contains('Invalid login credentials')) {
          errorMsg = 'Invalid login credentials. If you registered using Google, please login with Google.';
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

  Future<void> _navigateToRoleDashboard(AuthViewModel authVm) async {
    if (!mounted) return;

    if (authVm.userAssociations.length > 1) {
      Navigator.pushAndRemoveUntil(
        context,
        AppRouter.scaleRoute(const GymRoleSelectorScreen()),
        (route) => false,
      );
      return;
    }

    Widget targetScreen;
    bool shouldSync = false;

    if (authVm.userAssociations.isEmpty) {
      if (authVm.selectedRole == 'owner') {
        targetScreen = const FirstTimeSetupScreen();
      } else {
        await authVm.logout();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          AppRouter.scaleRoute(RoleSelectionScreen()),
          (route) => false,
        );
        return;
      }
    } else {
      final profile = authVm.currentProfile!;

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
    }

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

                // Google sign in
                OutlinedButton(
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    try {
                      final authVm = Provider.of<AuthViewModel>(context, listen: false);
                      if (widget.role == 'Gym Owner') {
                        await authVm.selectRole('owner');
                      } else if (widget.role == 'Gym Staff') {
                        await authVm.selectRole('staff');
                      } else if (widget.role == 'Gym Member') {
                        await authVm.selectRole('member');
                      }
                      await authVm.signInWithGoogle();
                      if (mounted && !kIsWeb) {
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
                    onPressed: () {},
                    child: Text('Forgot Password?', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                  ),
                ),
                const SizedBox(height: 8),

                CustomButton(
                  text: 'Login',
                  isLoading: _isLoading,
                  onPressed: _handleLogin,
                ),
                const SizedBox(height: 16),

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
                const SizedBox(height: 16),

                // Apple Sign In
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppTheme.textPrimary,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusInput)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.apple_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text('Sign in with Apple', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
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
