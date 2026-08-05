import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isSignUpMode = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Row(
        children: [
          // Left branding panel (desktop only)
          if (isWide)
            Expanded(
              flex: 5,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6C3AED), Color(0xFF4C1D95)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      top: -80,
                      left: -80,
                      child: Container(
                        width: 300,
                        height: 300,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -120,
                      right: -60,
                      child: Container(
                        width: 400,
                        height: 400,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Center(
                                    child: Text('G',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26)),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'Gym OS',
                                  style: GoogleFonts.inter(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Super Admin\nControl Panel',
                              style: GoogleFonts.inter(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.1,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Manage every gym, subscription, payment,\nand platform operation from one console.',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: Colors.white.withValues(alpha: 0.7),
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 40),
                            // Stats preview
                            Row(
                              children: [
                                _BrandingStat(value: '150+', label: 'Active Gyms'),
                                const SizedBox(width: 32),
                                _BrandingStat(value: '12K+', label: 'Members'),
                                const SizedBox(width: 32),
                                _BrandingStat(value: '99.9%', label: 'Uptime'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Right login form
          Expanded(
            flex: isWide ? 4 : 1,
            child: Container(
              color: const Color(0xFF0F172A),
              child: Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.all(40),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isWide) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: AdminTheme.primaryGradient,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Center(
                                      child: Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Gym OS Admin',
                                    style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 40),
                            ],
                            Text(
                              _isSignUpMode ? 'Register Super Admin' : 'Welcome back',
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isSignUpMode ? 'Register a new Super Admin account' : 'Sign in to your Super Admin account',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(height: 36),
                            // Email
                            Text('Email', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF94A3B8))),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                              decoration: _inputDecoration(
                                hint: 'admin@gymos.com',
                                prefixIcon: Icons.mail_outline_rounded,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Email is required';
                                if (!v.contains('@')) return 'Enter a valid email';
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            // Password
                            Text('Password', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF94A3B8))),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                              decoration: _inputDecoration(
                                hint: '••••••••',
                                prefixIcon: Icons.lock_outline_rounded,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    size: 20,
                                    color: const Color(0xFF64748B),
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Password is required';
                                if (v.length < 6) return 'Minimum 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            // Error message
                            if (authProvider.error != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: AdminTheme.danger.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                                  border: Border.all(color: AdminTheme.danger.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded, size: 18, color: AdminTheme.danger),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        authProvider.error!,
                                        style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.danger),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 8),
                            // Login button
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: authProvider.isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AdminTheme.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                child: authProvider.isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        _isSignUpMode ? 'Register Admin' : 'Sign In',
                                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isSignUpMode ? 'Already have an admin account? ' : 'First time here? ',
                                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() => _isSignUpMode = !_isSignUpMode),
                                  child: Text(
                                    _isSignUpMode ? 'Sign In' : 'Register Admin',
                                    style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.primary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Text(
                                'Super Admin access only',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: const Color(0xFF475569), fontSize: 14),
      prefixIcon: Icon(prefixIcon, size: 20, color: const Color(0xFF64748B)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminTheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminTheme.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminTheme.danger, width: 1.5),
      ),
      errorStyle: GoogleFonts.inter(fontSize: 12, color: AdminTheme.danger),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSignUpMode) {
      final success = await context.read<AuthProvider>().signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (success && mounted) {
        setState(() => _isSignUpMode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin registration successful! You can now log in.'),
            backgroundColor: AdminTheme.success,
          ),
        );
      }
    } else {
      await context.read<AuthProvider>().login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
    }
  }
}

class _BrandingStat extends StatelessWidget {
  final String value;
  final String label;

  const _BrandingStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
