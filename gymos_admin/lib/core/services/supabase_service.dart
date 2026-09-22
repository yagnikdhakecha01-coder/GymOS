import 'dart:math';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class AdminSupabaseService {
  static SupabaseClient? _client;

  AdminSupabaseService._();

  static bool get isConfigured => AdminSupabaseConfig.isValid;
  static bool get isInitialized => _client != null;

  static SupabaseClient get client {
    if (_client == null) {
      throw StateError('Supabase client has not been initialized.');
    }
    return _client!;
  }

  static Future<void> initialize() async {
    var urlStr = AdminSupabaseConfig.url;
    var anonKeyStr = AdminSupabaseConfig.anonKey;

    if (urlStr.isEmpty || anonKeyStr.isEmpty) {
      try {
        final content = await rootBundle.loadString('.env');
        final lines = content.split('\n');
        String? fileUrl;
        String? fileKey;
        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final parts = line.split('=');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts.sublist(1).join('=').trim().replaceAll('"', '').replaceAll("'", '');
            if (key == 'SUPABASE_URL') fileUrl = value;
            if (key == 'SUPABASE_ANON_KEY') fileKey = value;
          }
        }
        if (fileUrl != null && fileKey != null && fileUrl.isNotEmpty && fileKey.isNotEmpty) {
          AdminSupabaseConfig.setDynamicConfig(fileUrl, fileKey);
          urlStr = AdminSupabaseConfig.url;
          anonKeyStr = AdminSupabaseConfig.anonKey;
        }
      } catch (_) {}
    }

    if (urlStr.isEmpty || anonKeyStr.isEmpty) return;

    try {
      await Supabase.initialize(
        url: urlStr,
        anonKey: anonKeyStr,
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: true,
        ),
      );
      _client = Supabase.instance.client;
    } catch (_) {}
  }

  /// Ensures the active session is refreshed if expired or close to expiry (< 5 minutes)
  static Future<Session?> ensureValidSession() async {
    if (_client == null) return null;
    try {
      final session = _client!.auth.currentSession;
      if (session == null) return null;

      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiresAt = session.expiresAt ?? 0;

      // If token is expired or expires in under 300 seconds (5 minutes)
      if (session.isExpired || (expiresAt > 0 && expiresAt - nowSec < 300)) {
        final res = await _client!.auth.refreshSession();
        return res.session ?? _client!.auth.currentSession;
      }
      return session;
    } catch (e) {
      return _client?.auth.currentSession;
    }
  }

  static String generateUuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
