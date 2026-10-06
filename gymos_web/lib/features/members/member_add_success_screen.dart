import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/invitation_share_sheet.dart';

class MemberAddSuccessScreen extends StatelessWidget {
  final String memberName;
  final String invitationCode;
  final String? phone;

  const MemberAddSuccessScreen({
    super.key,
    required this.memberName,
    required this.invitationCode,
    this.phone,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Success Icon
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.green.shade100, width: 2),
                        ),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 50,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Member Added Successfully!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$memberName has been registered. Share the invitation code below to help them set up their account.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Invitation Code Box
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'INVITATION CODE',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            invitationCode,
                            style: GoogleFonts.firaCode(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: invitationCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Invitation code copied to clipboard!'),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppTheme.textPrimary,
                                  elevation: 0,
                                  side: const BorderSide(color: AppTheme.border),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                                icon: const Icon(Icons.copy_all_rounded, size: 16),
                                label: Text(
                                  'Copy',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  InvitationShareSheet.show(
                                    context: context,
                                    invitationCode: invitationCode,
                                    phone: phone ?? '',
                                    recipientName: memberName,
                                    isStaff: false,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                icon: const Icon(Icons.share_rounded, size: 16),
                                label: Text(
                                  'Share Invitation',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Done Button
                    ElevatedButton(
                      onPressed: () {
                        // Pop both the success screen and the wizard
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Go to Dashboard',
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
    );
  }
}
