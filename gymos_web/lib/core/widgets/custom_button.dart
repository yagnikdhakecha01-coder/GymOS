import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isLoading;
  final bool isSmall;
  final IconData? icon;
  final Color? color;
  final Color? textColor;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isPrimary = true,
    this.isLoading = false,
    this.isSmall = false,
    this.icon,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (isSmall) return _buildSmallButton(context);
    return _buildFullButton(context);
  }

  Widget _buildSmallButton(BuildContext context) {
    final bg = color ?? AppTheme.primary;
    final fg = textColor ?? Colors.white;

    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(text),
          ],
        ),
      ),
    );
  }

  Widget _buildFullButton(BuildContext context) {
    final isDisabled = onPressed == null;
    final bg = color ?? (isPrimary ? AppTheme.primary : Colors.transparent);
    final borderCol = isPrimary ? Colors.transparent : AppTheme.border;
    final fg = textColor ?? (isPrimary ? Colors.white : AppTheme.textPrimary);

    return SizedBox(
      width: double.infinity,
      height: AppTheme.buttonHeight,
      child: isLoading
          ? Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                  strokeWidth: 2.5,
                ),
              ),
            )
          : isPrimary
              ? ElevatedButton(
                  onPressed: isDisabled ? null : onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: bg,
                    foregroundColor: fg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    ),
                    textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: fg),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              : OutlinedButton(
                  onPressed: isDisabled ? null : onPressed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: fg,
                    side: BorderSide(color: borderCol, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    ),
                    textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: fg),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
