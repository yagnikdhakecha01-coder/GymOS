import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme.dart';

class AvatarCacheService {
  static final Map<String, Uint8List> _memoryCache = {};
  static final Set<String> _pendingDownloads = {};

  static Uint8List? getFromMemory(String key) {
    return _memoryCache[key];
  }

  static void putInMemory(String key, Uint8List bytes) {
    _memoryCache[key] = bytes;
  }

  static Future<void> preloadAvatar(String url) async {
    if (url.isEmpty || !url.startsWith('http') || _pendingDownloads.contains(url) || _memoryCache.containsKey(url)) {
      return;
    }
    _pendingDownloads.add(url);
    try {
      if (!kIsWeb) {
        final request = await HttpClient().getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          if (bytes.isNotEmpty) {
            _memoryCache[url] = bytes;
          }
        }
      }
    } catch (_) {
    } finally {
      _pendingDownloads.remove(url);
    }
  }
}

class AppCachedAvatar extends StatefulWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final double? fontSize;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? textColor;
  final BoxBorder? border;

  const AppCachedAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 50,
    this.fontSize,
    this.borderRadius,
    this.backgroundColor,
    this.textColor,
    this.border,
  });

  @override
  State<AppCachedAvatar> createState() => _AppCachedAvatarState();
}

class _AppCachedAvatarState extends State<AppCachedAvatar> {
  Uint8List? _cachedBytes;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  @override
  void didUpdateWidget(covariant AppCachedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _checkCache();
    }
  }

  void _checkCache() {
    final url = widget.imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      _cachedBytes = null;
      return;
    }

    if (url.startsWith('data:image') || url.length > 200 && !url.startsWith('http')) {
      try {
        final cleanBase64 = url.contains(',') ? url.split(',').last : url;
        final bytes = base64Decode(cleanBase64);
        _cachedBytes = bytes;
        AvatarCacheService.putInMemory(url, bytes);
        return;
      } catch (_) {}
    }

    final mem = AvatarCacheService.getFromMemory(url);
    if (mem != null) {
      _cachedBytes = mem;
    } else if (url.startsWith('http')) {
      AvatarCacheService.preloadAvatar(url).then((_) {
        if (mounted) {
          final loaded = AvatarCacheService.getFromMemory(url);
          if (loaded != null) {
            setState(() => _cachedBytes = loaded);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl?.trim() ?? '';
    final radius = widget.borderRadius ?? BorderRadius.circular(widget.size / 2);
    final bgColor = widget.backgroundColor ?? const Color(0xFFE2E8F0);
    final txtColor = widget.textColor ?? AppTheme.textPrimary;
    final fSize = widget.fontSize ?? (widget.size * 0.38);

    Widget fallbackInitials() {
      final initial = widget.name.trim().isNotEmpty ? widget.name.trim()[0].toUpperCase() : 'S';
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: radius,
          border: widget.border,
        ),
        child: Center(
          child: Text(
            initial,
            style: GoogleFonts.inter(
              fontSize: fSize,
              fontWeight: FontWeight.bold,
              color: txtColor,
            ),
          ),
        ),
      );
    }

    if (_cachedBytes != null) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: widget.border,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Image.memory(
            _cachedBytes!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => fallbackInitials(),
          ),
        ),
      );
    }

    if (url.isNotEmpty && url.startsWith('http')) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: widget.border,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Image.network(
            url,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => fallbackInitials(),
          ),
        ),
      );
    }

    return fallbackInitials();
  }
}
