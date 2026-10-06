import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/gym_logo_cache_service.dart';
import '../services/local_storage.dart';
import '../theme/theme.dart';

class AppCachedGymLogo extends StatelessWidget {
  final String? gymId;
  final String? logoUrl;
  final String gymName;
  final double size;
  final BorderRadius? borderRadius;

  const AppCachedGymLogo({
    super.key,
    this.gymId,
    this.logoUrl,
    required this.gymName,
    this.size = 52,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(14);
    final storage = LocalStorageService.instance;
    final cleanLogo = logoUrl?.trim() ?? '';
    
    return ValueListenableBuilder<int>(
      valueListenable: GymLogoCacheService.cacheNotifier,
      builder: (context, _, _) {
        // 1. Check instant in-memory or local base64 cache
        final cachedBase64 = GymLogoCacheService.getCachedLogoBase64(storage, gymId, cleanLogo);
        Uint8List? imageBytes;
        if (cachedBase64 != null && cachedBase64.isNotEmpty) {
          try {
            imageBytes = base64Decode(cachedBase64);
          } catch (_) {}
        }

        Widget content;
        if (imageBytes != null && imageBytes.isNotEmpty) {
          content = ClipRRect(
            borderRadius: radius,
            child: Image.memory(
              imageBytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildStaticFallback(radius),
            ),
          );
        } else if (cleanLogo.startsWith('http')) {
          content = ClipRRect(
            borderRadius: radius,
            child: Image.network(
              cleanLogo,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildStaticFallback(radius),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return _buildStaticFallback(radius);
              },
            ),
          );
        } else {
          content = _buildStaticFallback(radius);
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: AppTheme.cardBackground,
          ),
          child: content,
        );
      },
    );
  }

  Widget _buildStaticFallback(BorderRadius radius) {
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: AppTheme.primary,
        alignment: Alignment.center,
        child: Text(
          gymName.trim().isNotEmpty ? gymName.trim()[0].toUpperCase() : 'G',
          style: GoogleFonts.inter(
            fontSize: size * 0.44,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
