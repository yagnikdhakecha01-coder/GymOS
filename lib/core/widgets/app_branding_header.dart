import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../features/authentication/auth_viewmodel.dart';
import '../services/gym_logo_cache_service.dart';
import '../theme/theme.dart';

class AppBrandingHeader extends StatelessWidget {
  final double logoSize;
  final double fontSize;
  final double spacing;
  final bool welcomeText;

  const AppBrandingHeader({
    Key? key,
    this.logoSize = 72,
    this.fontSize = 24,
    this.spacing = 16,
    this.welcomeText = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final isBrandingEnabled = authVm.isCustomBrandingEnabled;
    final brandingName = authVm.customBrandingName;
    final logoBase64 = authVm.customBrandingLogoBase64;
    final logoUrl = authVm.customBrandingLogoUrl;

    // Use whitelabel custom logo if enabled, otherwise fall back to the standard gym logo
    final displayLogoUrl = (logoUrl != null && logoUrl.isNotEmpty)
        ? logoUrl
        : (authVm.gymInfo?['logo'] ?? authVm.gymInfo?['logo_url'] ?? '');

    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id']?.toString();
    final cachedBase64 = GymLogoCacheService.getCachedLogoBase64(authVm.storage, gymId, displayLogoUrl);

    Widget logoWidget;
    if (cachedBase64 != null && cachedBase64.isNotEmpty) {
      try {
        logoWidget = Container(
          decoration: BoxDecoration(
            boxShadow: AppTheme.cardShadow,
            borderRadius: BorderRadius.circular(logoSize * 0.25),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(logoSize * 0.25),
            child: Image.memory(
              base64Decode(cachedBase64),
              width: logoSize,
              height: logoSize,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        );
      } catch (_) {
        logoWidget = _buildDefaultLogo();
      }
    } else if (displayLogoUrl.isNotEmpty) {
      logoWidget = Container(
        decoration: BoxDecoration(
          boxShadow: AppTheme.cardShadow,
          borderRadius: BorderRadius.circular(logoSize * 0.25),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(logoSize * 0.25),
          child: Image.network(
            displayLogoUrl,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildDefaultLogo(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(logoSize * 0.25),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      logoWidget = _buildDefaultLogo();
    }

    final displayText = welcomeText 
        ? (isBrandingEnabled ? 'Welcome to $brandingName' : 'Welcome to GymOS')
        : brandingName;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logoWidget,
        SizedBox(height: spacing),
        Text(
          displayText,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: AppTheme.primary,
            letterSpacing: welcomeText ? 0.5 : 2,
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: logoSize,
      height: logoSize,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(logoSize * 0.25),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Icon(
        Icons.fitness_center_rounded,
        color: Colors.white,
        size: logoSize * 0.5,
      ),
    );
  }
}
