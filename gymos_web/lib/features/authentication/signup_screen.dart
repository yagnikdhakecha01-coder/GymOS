import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/navigation/app_router.dart';
import '../../core/services/supabase_service.dart';
import 'first_time_setup_screen.dart';
import 'login_screen.dart';
import 'auth_viewmodel.dart';
import '../../core/widgets/app_branding_header.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _showPassword = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Sign up with Supabase Auth
      final response = await SupabaseService.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {'role': 'owner'},
      );

      if (mounted) {
        setState(() => _isLoading = false);

        if (response.user != null) {
          final authVm = Provider.of<AuthViewModel>(context, listen: false);
          await authVm.selectRole('owner');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              content: Text(
                'Account created! Let\'s complete your profile.',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              ),
            ),
          );

          // Route to FirstTimeSetupScreen
          Navigator.pushAndRemoveUntil(
            context,
            AppRouter.scaleRoute(const FirstTimeSetupScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text(e.toString().replaceAll('Exception:', '')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FD),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Account',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F6FD),
              Color(0xFFF5F6FA),
              Color(0xFFEEF0F7),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 460),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // App Branding Header (Custom logo & Name)
                      const Center(
                        child: AppBrandingHeader(
                          logoSize: 56,
                          fontSize: 20,
                          spacing: 12,
                          welcomeText: false,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        Provider.of<AuthViewModel>(context, listen: false).isCustomBrandingEnabled
                            ? 'Get Started'
                            : 'Get Started with GymOS',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Create an account to begin configuring your gym',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 28),

                      // Email
                      Text(
                        'Email Address',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'name@example.com',
                          prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Email is required';
                          if (!val.contains('@')) return 'Please enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Password
                      Text(
                        'Password',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Enter password (min 6 characters)',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_showPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Password is required';
                          if (val.length < 6) return 'Password must be at least 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // Confirm Password
                      Text(
                        'Confirm Password',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_showPassword,
                        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Confirm password is required';
                          if (val != _passwordController.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // Submit button
                      CustomButton(
                        text: 'Sign Up',
                        onPressed: _isLoading ? null : _handleSignup,
                      ),
                      const SizedBox(height: 24),

                      // Redirect to Login
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Already have an account? ", style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                          GestureDetector(
                            onTap: () => Navigator.pushReplacement(
                              context,
                              AppRouter.slideRoute(const LoginScreen(role: 'Gym Owner')),
                            ),
                            child: Text('Login', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
