import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/navigation/app_router.dart';
import '../../core/services/supabase_service.dart';
import 'auth_viewmodel.dart';
import 'role_selection_screen.dart';

class AuthSuccessScreen extends StatefulWidget {
  const AuthSuccessScreen({super.key});

  @override
  State<AuthSuccessScreen> createState() => _AuthSuccessScreenState();
}

class _AuthSuccessScreenState extends State<AuthSuccessScreen> {
  bool _isLoggingOut = false;

  Future<void> _handleLogout() async {
    setState(() => _isLoggingOut = true);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);

    try {
      await authVm.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          AppRouter.scaleRoute(const RoleSelectionScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoggingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            content: Text('Logout failed: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    final email = user?.email ?? 'Unknown Email';
    final userId = user?.id ?? 'Unknown ID';
    
    // Determine Auth Provider
    String providerName = 'Email Login';
    final identities = user?.identities;
    if (identities != null && identities.isNotEmpty) {
      final provider = identities.first.provider;
      if (provider.toLowerCase() == 'google') {
        providerName = 'Login with Google';
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark Slate
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Success Icon Animation / Pill
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Color(0xFF10B981),
                      size: 64,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                Text(
                  '✅ Logged In Successfully',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your session is active and secured via Supabase Auth',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 32),

                // Info Panel Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('User ID', userId, isCode: true),
                      const Divider(color: Color(0xFF334155), height: 32),
                      _buildInfoRow('Email Address', email),
                      const Divider(color: Color(0xFF334155), height: 32),
                      _buildInfoRow('Auth Provider', providerName, isBadge: true),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Logout Button
                SizedBox(
                  height: 50,
                  child: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444), // Crimson Red
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFEF4444).withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ).build(
                    context,
                    onPressed: _isLoggingOut ? null : _handleLogout,
                    child: _isLoggingOut
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Logout',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isCode = false, bool isBadge = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF64748B),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        if (isCode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                value,
                style: GoogleFonts.firaCode(
                  fontSize: 12,
                  color: const Color(0xFF38BDF8),
                ),
              ),
            ),
          )
        else if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
            ),
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF818CF8),
              ),
            ),
          )
        else
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
      ],
    );
  }
}

// Extension to help build ElevatedButton easily
extension on ButtonStyle {
  Widget build(BuildContext context, {required VoidCallback? onPressed, required Widget child}) {
    return ElevatedButton(
      style: this,
      onPressed: onPressed,
      child: child,
    );
  }
}
