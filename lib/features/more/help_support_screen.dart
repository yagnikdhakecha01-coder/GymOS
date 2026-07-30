import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Widget _buildFAQTile(String question, String answer) {
    return ExpansionTile(
      title: Text(
        question,
        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedAlignment: Alignment.topLeft,
      children: [
        Text(
          answer,
          style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Help & Support'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          children: [
            // Support Card
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need Instant Help?',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Our support team is available Monday to Saturday (09:00 AM - 06:00 PM)',
                    style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.email_outlined, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Text('support@gymos.com', style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Text('+91 99887 76655', style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textPrimary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // FAQs Group
            Text('FREQUENTLY ASKED QUESTIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildFAQTile(
                    'How do I add custom fields to member forms?',
                    'Go to More -> Gym Settings -> Custom Member Form. Here, you can configure text, number, dropdown, switch, or photo fields that will automatically appear when adding a member.',
                  ),
                  const Divider(height: 1),
                  _buildFAQTile(
                    'Can I schedule multiple workouts in a single day?',
                    'Yes, inside More -> Workout Plans -> Add/Edit Plan. Each day of the weekly schedule has an "+ Add Workout" button allowing you to add unlimited routines.',
                  ),
                  const Divider(height: 1),
                  _buildFAQTile(
                    'How does trainer assignment work?',
                    'When adding a member, toggle the "Personal Trainer" switch to ON. You will then see options to select an assigned trainer, PT package, and custom coaching notes.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
