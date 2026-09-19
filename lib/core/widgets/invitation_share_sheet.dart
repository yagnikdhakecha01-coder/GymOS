import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/authentication/auth_viewmodel.dart';
import '../theme/theme.dart';

class InvitationShareSheet extends StatelessWidget {
  final String invitationCode;
  final String phone;
  final String? recipientName;
  final String? gymName;
  final String? ownerName;
  final bool isStaff;
  final String? role;

  const InvitationShareSheet({
    super.key,
    required this.invitationCode,
    required this.phone,
    this.recipientName,
    this.gymName,
    this.ownerName,
    this.isStaff = false,
    this.role,
  });

  /// Displays the invitation share bottom sheet
  static Future<void> show({
    required BuildContext context,
    required String invitationCode,
    required String phone,
    String? recipientName,
    String? gymName,
    String? ownerName,
    bool isStaff = false,
    String? role,
  }) {
    // Resolve gymName and ownerName from AuthViewModel if not explicitly provided
    String resolvedGymName = gymName ?? '';
    String resolvedOwnerName = ownerName ?? '';

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      if (resolvedGymName.isEmpty) {
        resolvedGymName = authVm.gymInfo?['name']?.toString() ?? 'GymOS Partner Gym';
      }
      if (resolvedOwnerName.isEmpty) {
        resolvedOwnerName = authVm.currentProfile?.fullName ??
            authVm.gymInfo?['owner_name']?.toString() ??
            'Gym Owner';
      }
    } catch (_) {
      if (resolvedGymName.isEmpty) resolvedGymName = 'GymOS Gym';
      if (resolvedOwnerName.isEmpty) resolvedOwnerName = 'Gym Owner';
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InvitationShareSheet(
        invitationCode: invitationCode,
        phone: phone,
        recipientName: recipientName,
        gymName: resolvedGymName,
        ownerName: resolvedOwnerName,
        isStaff: isStaff,
        role: role,
      ),
    );
  }

  /// Cleans phone number and formats for WhatsApp (adds 91 for Indian 10-digit numbers)
  static String formatPhoneNumber(String rawPhone) {
    var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      digits = '91$digits';
    }
    return digits;
  }

  /// Builds the formatted invitation message
  String buildMessage() {
    final effectiveGymName = (gymName != null && gymName!.isNotEmpty) ? gymName! : 'Our Gym';
    final effectiveOwnerName = (ownerName != null && ownerName!.isNotEmpty) ? ownerName! : 'Gym Owner';
    final greeting = (recipientName != null && recipientName!.trim().isNotEmpty)
        ? 'Hello ${recipientName!.trim()},'
        : 'Hello,';

    final roleLine = isStaff
        ? (role != null ? 'as a *$role*' : 'as *Staff*')
        : 'to join us as a *Member*';

    return '''🏋️ *$effectiveGymName*
━━━━━━━━━━━━━━━━━━━━
$greeting
You have been invited by Gym Owner - *$effectiveOwnerName* $roleLine.

*Your Invitation Code:*
`$invitationCode`

*Registered Mobile Number:*
$phone

📲 *How to Join:*
1. Download the GymOS app
2. Open app & choose "Have an Invitation Code?"
3. Enter code: `$invitationCode`
━━━━━━━━━━━━━━━━━━━━
Welcome to $effectiveGymName! 💪''';
  }

  /// Launches WhatsApp directly with the chat open and prefilled message
  Future<void> _launchWhatsApp(BuildContext context, {bool isBusiness = false}) async {
    final cleanPhone = formatPhoneNumber(phone);
    final message = buildMessage();
    final encodedText = Uri.encodeComponent(message);

    // Direct WhatsApp app URI scheme
    final appUri = Uri.parse("whatsapp://send?phone=$cleanPhone&text=$encodedText");
    final webFallbackUri = Uri.parse("https://api.whatsapp.com/send?phone=$cleanPhone&text=$encodedText");

    bool opened = false;
    try {
      if (await canLaunchUrl(appUri)) {
        opened = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      }
      if (!opened && await canLaunchUrl(webFallbackUri)) {
        opened = await launchUrl(webFallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('WhatsApp launch error: $e');
    }

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBusiness
                ? 'Could not open WhatsApp Business. Please check if installed.'
                : 'Could not open WhatsApp. Please check if installed.',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Launches default SMS app
  Future<void> _launchSms(BuildContext context) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final message = buildMessage();
    final smsUri = Uri(
      scheme: 'sms',
      path: cleanPhone,
      queryParameters: <String, String>{
        'body': message,
      },
    );

    bool opened = false;
    try {
      if (await canLaunchUrl(smsUri)) {
        opened = await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('SMS launch error: $e');
    }

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open SMS application.', style: GoogleFonts.inter()),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Uses Native System Share
  Future<void> _shareViaSystem(BuildContext context) async {
    final message = buildMessage();
    try {
      await SharePlus.instance.share(
        message,
        subject: 'GymOS Invitation - ${gymName ?? "Gym"}',
      );
    } catch (e) {
      debugPrint('System share error: $e');
    }
  }

  /// Copies full invitation text
  void _copyFullText(BuildContext context) {
    Clipboard.setData(ClipboardData(text: buildMessage()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('Full invitation copied to clipboard!', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Copies invitation code only
  void _copyCodeOnly(BuildContext context) {
    Clipboard.setData(ClipboardData(text: invitationCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.copy_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text('Invitation Code: $invitationCode copied!', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          ],
        ),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveGym = (gymName != null && gymName!.isNotEmpty) ? gymName! : 'Gym';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.share_rounded, color: Color(0xFF25D366), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Invitation Code',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      effectiveGym,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Code Display Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceGray,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INVITATION CODE',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        invitationCode,
                        style: GoogleFonts.firaCode(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Mobile: $phone',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _copyCodeOnly(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.textPrimary,
                    elevation: 0,
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: Text(
                    'Copy',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section Title
          Text(
            'CHOOSE SHARING APP',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),

          // Action 1: WhatsApp
          _buildShareTile(
            context: context,
            title: 'Share via WhatsApp',
            subtitle: 'Opens direct chat with $phone',
            icon: Icons.chat_bubble_rounded,
            iconColor: const Color(0xFF25D366),
            backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.08),
            onTap: () {
              Navigator.pop(context);
              _launchWhatsApp(context, isBusiness: false);
            },
          ),
          const SizedBox(height: 10),

          // Action 2: WhatsApp Business
          _buildShareTile(
            context: context,
            title: 'Share via WhatsApp Business',
            subtitle: 'Send using your Business account',
            icon: Icons.business_center_rounded,
            iconColor: const Color(0xFF075E54),
            backgroundColor: const Color(0xFF075E54).withValues(alpha: 0.08),
            onTap: () {
              Navigator.pop(context);
              _launchWhatsApp(context, isBusiness: true);
            },
          ),
          const SizedBox(height: 10),

          // Action 3: SMS / Messages
          _buildShareTile(
            context: context,
            title: 'Share via SMS / Messenger',
            subtitle: 'Send regular text message',
            icon: Icons.sms_rounded,
            iconColor: const Color(0xFF0288D1),
            backgroundColor: const Color(0xFF0288D1).withValues(alpha: 0.08),
            onTap: () {
              Navigator.pop(context);
              _launchSms(context);
            },
          ),
          const SizedBox(height: 10),

          // Action 4: More Apps / Native Share
          _buildShareTile(
            context: context,
            title: 'Share via Other Apps',
            subtitle: 'Telegram, Instagram, Gmail, etc.',
            icon: Icons.share_rounded,
            iconColor: AppTheme.primary,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.08),
            onTap: () {
              Navigator.pop(context);
              _shareViaSystem(context);
            },
          ),
          const SizedBox(height: 10),

          // Action 5: Copy Full Message
          _buildShareTile(
            context: context,
            title: 'Copy Full Invitation Text',
            subtitle: 'Includes instructions, gym name & code',
            icon: Icons.content_copy_rounded,
            iconColor: AppTheme.textPrimary,
            backgroundColor: AppTheme.surfaceGray,
            onTap: () {
              Navigator.pop(context);
              _copyFullText(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildShareTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
