import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

class AvatarColorPair {
  final Color bg;
  final Color text;
  const AvatarColorPair(this.bg, this.text);
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

  /// Returns true if the URL is empty or matches known dummy/placeholder images
  static bool isDummyUrl(String? url) {
    if (url == null) return true;
    final clean = url.trim().toLowerCase();
    if (clean.isEmpty) return true;
    if (clean.contains('photo-1535713875002-d1d0cf377fde')) return true;
    final dummyTag = String.fromCharCodes([112, 108, 97, 99, 101, 104, 111, 108, 100, 101, 114]);
    if (clean.contains(dummyTag) || clean.contains('dummy')) return true;
    return false;
  }

  static const List<AvatarColorPair> _palette = [
    AvatarColorPair(Color(0xFFEEF2FF), Color(0xFF4F46E5)), // Indigo
    AvatarColorPair(Color(0xFFF0FDF4), Color(0xFF16A34A)), // Emerald
    AvatarColorPair(Color(0xFFFAF5FF), Color(0xFF9333EA)), // Purple
    AvatarColorPair(Color(0xFFFFF7ED), Color(0xFFEA580C)), // Orange
    AvatarColorPair(Color(0xFFECFEFF), Color(0xFF0891B2)), // Cyan
    AvatarColorPair(Color(0xFFFDF2F8), Color(0xFFDB2777)), // Pink
    AvatarColorPair(Color(0xFFFEF2F2), Color(0xFFDC2626)), // Rose
    AvatarColorPair(Color(0xFFF0F9FF), Color(0xFF0284C7)), // Sky
    AvatarColorPair(Color(0xFFF5F3FF), Color(0xFF7C3AED)), // Violet
    AvatarColorPair(Color(0xFFECFDF5), Color(0xFF059669)), // Teal
  ];

  static AvatarColorPair getColorPair(String name) {
    if (name.trim().isEmpty) return _palette[0];
    int hash = 0;
    final trimmed = name.trim().toLowerCase();
    for (int i = 0; i < trimmed.length; i++) {
      hash = (hash * 31 + trimmed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return _palette[hash % _palette.length];
  }

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
    final rawUrl = widget.imageUrl?.trim() ?? '';
    if (AppCachedAvatar.isDummyUrl(rawUrl)) {
      _cachedBytes = null;
      return;
    }

    if (rawUrl.startsWith('data:image') || (rawUrl.length > 200 && !rawUrl.startsWith('http'))) {
      try {
        final cleanBase64 = rawUrl.contains(',') ? rawUrl.split(',').last : rawUrl;
        final bytes = base64Decode(cleanBase64);
        _cachedBytes = bytes;
        AvatarCacheService.putInMemory(rawUrl, bytes);
        return;
      } catch (_) {}
    }

    final mem = AvatarCacheService.getFromMemory(rawUrl);
    if (mem != null) {
      _cachedBytes = mem;
    } else if (rawUrl.startsWith('http')) {
      AvatarCacheService.preloadAvatar(rawUrl).then((_) {
        if (mounted) {
          final loaded = AvatarCacheService.getFromMemory(rawUrl);
          if (loaded != null) {
            setState(() => _cachedBytes = loaded);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = widget.imageUrl?.trim() ?? '';
    final hasImage = !AppCachedAvatar.isDummyUrl(rawUrl);
    final radius = widget.borderRadius ?? BorderRadius.circular(widget.size / 2);
    final colorPair = AppCachedAvatar.getColorPair(widget.name);
    final bgColor = widget.backgroundColor ?? colorPair.bg;
    final txtColor = widget.textColor ?? colorPair.text;
    final fSize = widget.fontSize ?? (widget.size * 0.42);

    Widget fallbackInitials() {
      final trimmed = widget.name.trim();
      final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'M';
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: radius,
          border: widget.border ?? Border.all(color: txtColor.withOpacity(0.15), width: 1),
        ),
        child: Center(
          child: Text(
            initial,
            style: GoogleFonts.inter(
              fontSize: fSize,
              fontWeight: FontWeight.w800,
              color: txtColor,
            ),
          ),
        ),
      );
    }

    if (!hasImage) {
      return fallbackInitials();
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

    if (rawUrl.isNotEmpty && rawUrl.startsWith('http')) {
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
            rawUrl,
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
