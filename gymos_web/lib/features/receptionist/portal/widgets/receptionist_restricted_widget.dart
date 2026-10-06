import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/theme.dart';

class RestrictedAccessWidget extends StatelessWidget {
  final String moduleName;
  const RestrictedAccessWidget({super.key, required this.moduleName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_person_outlined,
                size: 64,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Access Restricted',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The gym owner has disabled your permission to access the $moduleName module.\n\nChanges sync in real-time. Once the owner enables it, this page will unlock automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
