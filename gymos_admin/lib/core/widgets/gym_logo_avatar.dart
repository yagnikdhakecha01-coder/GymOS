import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/admin_theme.dart';
import 'full_screen_image_viewer.dart';

/// A robust gym logo avatar widget that displays the gym's official logo image
/// with rounded corners, subtle border, error fallback to stylized initials,
/// and optional full-screen zoom on tap.
class GymLogoAvatar extends StatelessWidget {
  final String? logoUrl;
  final String gymName;
  final double size;
  final double borderRadius;
  final bool enableFullScreenViewer;
  final Color? backgroundColor;

  const GymLogoAvatar({
    super.key,
    required this.logoUrl,
    required this.gymName,
    this.size = 36,
    this.borderRadius = 8,
    this.enableFullScreenViewer = false,
    this.backgroundColor,
  });

  bool get _hasValidLogo =>
      logoUrl != null &&
      logoUrl!.trim().isNotEmpty &&
      logoUrl!.trim().startsWith('http');

  @override
  Widget build(BuildContext context) {
    final cleanName = gymName.trim().isNotEmpty ? gymName.trim() : 'Gym';
    final initial = cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'G';

    final Widget initialBadge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AdminTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AdminTheme.primary.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: AdminTheme.primary,
            fontSize: (size * 0.42).clamp(11.0, 26.0),
          ),
        ),
      ),
    );

    if (!_hasValidLogo) {
      return initialBadge;
    }

    final cleanUrl = logoUrl!.trim();

    final Widget imageContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: AdminTheme.borderColor(context).withValues(alpha: 0.8),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius > 1 ? borderRadius - 1 : 0),
        child: Image.network(
          cleanUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => initialBadge,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return initialBadge;
          },
        ),
      ),
    );

    if (enableFullScreenViewer) {
      return Tooltip(
        message: 'Click to view $cleanName logo',
        waitDuration: const Duration(milliseconds: 300),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              showFullScreenImageViewer(
                context,
                imageUrl: cleanUrl,
                title: '$cleanName Logo',
                subtitle: 'Gym Official Branding',
              );
            },
            child: imageContent,
          ),
        ),
      );
    }

    return imageContent;
  }
}
