import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/admin_theme.dart';

Future<bool?> showAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
  Color? confirmColor,
  IconData? icon,
  bool isDangerous = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ConfirmDialog(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      confirmColor: confirmColor ?? (isDangerous ? AdminTheme.danger : AdminTheme.primary),
      icon: icon ?? (isDangerous ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
      isDangerous: isDangerous,
    ),
  );
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final Color confirmColor;
  final IconData icon;
  final bool isDangerous;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmText,
    required this.cancelText,
    required this.confirmColor,
    required this.icon,
    required this.isDangerous,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusLg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDangerous
                      ? AdminTheme.dangerLight
                      : AdminTheme.primaryLight.withValues(alpha: AdminTheme.isDark(context) ? 0.2 : 1.0),
                  borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
                ),
                child: Icon(icon, color: confirmColor, size: 28),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.textColor(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AdminTheme.secondaryTextColor(context),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        side: BorderSide(color: AdminTheme.borderColor(context)),
                      ),
                      child: Text(cancelText),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        minimumSize: const Size(0, 44),
                      ),
                      child: Text(confirmText),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
