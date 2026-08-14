import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'local_storage.dart';

class GymLogoCacheService {
  static final Map<String, String> _memoryCache = {};
  static final Set<String> _pendingDownloads = {};

  /// Get cached base64 logo string instantly from memory or local storage
  static String? getCachedLogoBase64(LocalStorageService storage, String? gymId, String? logoUrl) {
    if (gymId != null && gymId.isNotEmpty) {
      if (_memoryCache.containsKey(gymId) && _memoryCache[gymId]!.isNotEmpty) {
        return _memoryCache[gymId];
      }
      final cached = storage.getCachedImage('gym_logo_$gymId');
      if (cached != null && cached.isNotEmpty) {
        _memoryCache[gymId] = cached;
        return cached;
      }
    }
    
    // Check general custom gym logo cache
    final generalCached = storage.getCachedImage('custom_gym_logo');
    if (generalCached != null && generalCached.isNotEmpty) {
      if (gymId != null && gymId.isNotEmpty) {
        _memoryCache[gymId] = generalCached;
      }
      return generalCached;
    }
    
    // Safe background pre-download (only once per URL, no build loop trigger)
    if (logoUrl != null && logoUrl.startsWith('http') && !_pendingDownloads.contains(logoUrl)) {
      _pendingDownloads.add(logoUrl);
      Future.microtask(() => preloadAndCacheLogo(storage, gymId, logoUrl));
    }
    return null;
  }

  /// Download network image URL and save to local storage as base64
  static Future<void> preloadAndCacheLogo(LocalStorageService storage, String? gymId, String logoUrl) async {
    if (logoUrl.isEmpty || !logoUrl.startsWith('http')) return;
    try {
      final key = (gymId != null && gymId.isNotEmpty) ? 'gym_logo_$gymId' : 'custom_gym_logo';
      final existing = storage.getCachedImage(key);
      if (existing != null && existing.isNotEmpty) {
        if (gymId != null) _memoryCache[gymId] = existing;
        return;
      }

      Uint8List? bytes;
      if (kIsWeb) {
        return;
      } else {
        final request = await HttpClient().getUrl(Uri.parse(logoUrl));
        final response = await request.close();
        if (response.statusCode == 200) {
          bytes = await consolidateHttpClientResponseBytes(response);
        }
      }

      if (bytes != null && bytes.isNotEmpty) {
        final base64Str = base64Encode(bytes);
        if (gymId != null && gymId.isNotEmpty) {
          _memoryCache[gymId] = base64Str;
          await storage.setCachedImage('gym_logo_$gymId', base64Str);
        }
        await storage.setCachedImage('custom_gym_logo', base64Str);
      }
    } catch (e) {
      // Ignore background network errors gracefully
    } finally {
      _pendingDownloads.remove(logoUrl);
    }
  }

  /// Cache base64 logo string directly when uploaded or updated
  static Future<void> cacheLogoBase64(LocalStorageService storage, String? gymId, String base64Data) async {
    if (base64Data.isEmpty) return;
    if (gymId != null && gymId.isNotEmpty) {
      _memoryCache[gymId] = base64Data;
      await storage.setCachedImage('gym_logo_$gymId', base64Data);
    }
    await storage.setCachedImage('custom_gym_logo', base64Data);
  }
}
