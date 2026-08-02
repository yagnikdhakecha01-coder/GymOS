import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/navigation/app_router.dart';
import 'login_screen.dart';
import 'first_time_setup_screen.dart';
import '../member_app/screens/member_code_screen.dart';
import '../staff/portal/staff_dashboard_screen.dart';
import '../member_app/screens/member_shell.dart';

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
              // Logo
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.fitness_center_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome to GymOS',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
              Text(
                'By continuing you agree to our Terms & Privacy Policy',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                textAlign: TextAlign.center,
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
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.primaryLight),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15), width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      child: Icon(icon, color: AppTheme.primary, size: 24),
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
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    Text(
                      title,
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
