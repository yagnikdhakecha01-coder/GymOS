import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';

class AboutGymOSScreen extends StatelessWidget {
  const AboutGymOSScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('About GymOS'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              // App Logo
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.fitness_center_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'GymOS',
                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 1.2.0 (Build 26)',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const Spacer(flex: 1),

              // Version Details List
              CustomCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      title: Text('Terms of Service', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textMuted),
                      onTap: () {},
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text('Privacy Policy', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textMuted),
                      onTap: () {},
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text('Licensing Agreement', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textMuted),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              
              Text(
                '© 2026 GymOS Inc. All rights reserved.',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
