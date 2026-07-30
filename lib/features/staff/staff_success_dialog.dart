import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';

class StaffSuccessDialog extends StatelessWidget {
  final String staffName;
  final String role;
  final String invitationCode;
  final VoidCallback onDone;

  const StaffSuccessDialog({
    super.key,
    required this.staffName,
    required this.role,
    required this.invitationCode,
    required this.onDone,
  });

  static void show({
    required BuildContext context,
    required String staffName,
    required String role,
    required String invitationCode,
    required VoidCallback onDone,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: StaffSuccessDialog(
            staffName: staffName,
            role: role,
            invitationCode: invitationCode,
            onDone: onDone,
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: invitationCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'Invitation code copied!',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _shareCode(BuildContext context) {
    final message = 'Welcome to GymOS, $staffName!\n'
        'You have been added as a $role.\n'
        'Please download the GymOS app and use this Invitation Code to register:\n\n'
        'Invitation Code: $invitationCode\n\n'
        'Download now and get started!';
    
    // Fallback: Copy message to clipboard and instruct user
    Clipboard.setData(ClipboardData(text: message));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Share text copied to clipboard! Paste it in WhatsApp or SMS.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scale transition like tick icon
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppTheme.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 48,
                color: AppTheme.success,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Staff Added Successfully',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The staff record has been created. Share the invitation code below to complete setup.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          // Info summary card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Staff Name', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                    Text(
                      staffName,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Role', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                    Text(
                      role,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Text(
                        'INVITATION CODE',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: SelectableText(
                        invitationCode,
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          letterSpacing: 4.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _copyToClipboard(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.copy_rounded, size: 16, color: AppTheme.textPrimary),
                      const SizedBox(width: 6),
                      Text(
                        'Copy Code',
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _shareCode(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryLight,
                    foregroundColor: AppTheme.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.share_rounded, size: 16, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Share Code',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onDone,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              'Done',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
