import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/theme.dart';
import '../../core/navigation/app_router.dart';
import 'login_screen.dart';
import 'first_time_setup_screen.dart';
import '../member_app/screens/member_code_screen.dart';
import '../staff/portal/staff_dashboard_screen.dart';
import '../member_app/screens/member_shell.dart';
import '../../core/widgets/app_branding_header.dart';

class RoleSelectionScreen extends StatelessWidget {
  final bool isAddProfile;

  const RoleSelectionScreen({super.key, this.isAddProfile = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // App Branding Header (Custom logo & Welcome name)
              const AppBrandingHeader(
                logoSize: 72,
                fontSize: 24,
                spacing: 20,
                welcomeText: true,
              ),
              const SizedBox(height: 6),
              Text(
                'Choose who you are so we can\ngive you the right experience',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Role Cards (matching assets/images/role/ folder structure)
              _RoleCard(
                title: 'Gym Owner',
                subtitle: 'Manage your gym',
                icon: Icons.business_rounded,
                imagePath: 'assets/images/role/owner.png',
                onTap: () {
                  if (isAddProfile) {
                    Navigator.pushReplacement(
                      context,
                      AppRouter.slideRoute(const FirstTimeSetupScreen(isAddingAdditionalGym: true)),
                    );
                  } else {
                    Navigator.push(
                      context,
                      AppRouter.slideRoute(const LoginScreen(role: 'Gym Owner')),
                    );
                  }
                },
              ),
              const SizedBox(height: 14),
              _RoleCard(
                title: 'Gym Staff',
                subtitle: 'Trainer / Reception',
                icon: Icons.badge_outlined,
                imagePath: 'assets/images/role/staff.png',
                onTap: () {
                  if (isAddProfile) {
                    Navigator.pushReplacement(
                      context,
                      AppRouter.slideRoute(const MemberCodeScreen()),
                    );
                  } else {
                    Navigator.push(
                      context,
                      AppRouter.slideRoute(const LoginScreen(role: 'Gym Staff')),
                    );
                  }
                },
              ),
              const SizedBox(height: 14),
              _RoleCard(
                title: 'Gym Member',
                subtitle: 'Access your account',
                icon: Icons.person_outline_rounded,
                imagePath: 'assets/images/role/member.png',
                onTap: () {
                  if (isAddProfile) {
                    Navigator.pushReplacement(
                      context,
                      AppRouter.slideRoute(const MemberCodeScreen()),
                    );
                  } else {
                    Navigator.push(
                      context,
                      AppRouter.slideRoute(const LoginScreen(role: 'Gym Member')),
                    );
                  }
                },
              ),

              const Spacer(flex: 3),

              // Language + Help
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.language, size: 18, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text('English', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                  const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.headset_mic_outlined, size: 16, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Text('Help & Support', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'By continuing you agree to our ',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://gymos.tech/terms-of-service.html'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      'Terms',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Text(
                    ' & ',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://gymos.tech/privacy-policy.html'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      'Privacy Policy',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
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

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String imagePath;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F7FD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.8), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.3),
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.primaryLight.withValues(alpha: 0.4),
                      child: Icon(icon, color: AppTheme.primary, size: 28),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'I am',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
