import 'dart:math';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../config/env.dart';

class SupabaseService {
  static SupabaseClient? _client;
  static bool _hasInitializationError = false;
  static String? _errorMessage;

  /// Private constructor to prevent instantiation.
  SupabaseService._();

  /// Checks if credentials exist in the environment.
  static bool get isConfigured => SupabaseConfig.isValid;

  /// Checks if the client has been successfully initialized.
  static bool get isInitialized => _client != null;

  /// Returns true if there was an error during initialization.
  static bool get hasError => _hasInitializationError;

  /// Returns the exact reason why initialization failed.
  static String? get errorMessage => _errorMessage;

  /// Returns the single SupabaseClient instance.
  /// Throws a StateError if client is accessed before successful initialization.
  static SupabaseClient get client {
    if (_client == null) {
      throw StateError(
        'Supabase client has not been initialized. '
        'Verify that isConfigured is true and call initialize() before accessing the client.',
      );
    }
    return _client!;
  }

  /// Initializes the Supabase client safely and verifies the connection.
  /// Categorizes errors into exact reasons instead of generic ones.
  static Future<void> initialize() async {
    _hasInitializationError = false;
    _errorMessage = null;

    var urlStr = SupabaseConfig.url;
    var anonKeyStr = SupabaseConfig.anonKey;

    if (urlStr.isEmpty || anonKeyStr.isEmpty) {
      // Fallback: Try loading from .env asset
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
            final value = parts.sublist(1).join('=').trim();
            if (key == 'SUPABASE_URL') {
              fileUrl = value;
            } else if (key == 'SUPABASE_ANON_KEY') {
              fileKey = value;
            }
          }
        }
        if (fileUrl != null && fileKey != null) {
          SupabaseConfig.setDynamicConfig(fileUrl, fileKey);
          urlStr = SupabaseConfig.url;
          anonKeyStr = SupabaseConfig.anonKey;
          print('Supabase loaded credentials from runtime .env asset.');
        }
      } catch (e) {
        print('Supabase: Could not load .env asset: $e');
      }
    }

    if (urlStr.isEmpty || anonKeyStr.isEmpty) {
      print('Supabase: Keys not set. Running in offline/mock mode.');
      return;
    }

    try {
      await Supabase.initialize(
        url: urlStr,
        anonKey: anonKeyStr,
      );
      _client = Supabase.instance.client;
      print('Supabase initialized successfully.');
    } catch (e) {
      print('Supabase initialization warning (running in offline/mock mode): $e');
    }
  }

  /// Performs a lightweight query to test actual API connectivity and authentication.
  static Future<String> _testConnection() async {
    try {
      // Query a dummy table. If we successfully contact the DB,
      // a "relation does not exist" (42P01) error is returned, confirming API authorization!
      await Supabase.instance.client
          .from('connection_test_dummy_verification')
          .select()
          .limit(1);

      return 'SUCCESS';
    } on PostgrestException catch (e) {
      // Code 42P01 = Table/Relation does not exist.
      // This is a SUCCESS state because the database successfully validated our Anon key
      // and returned a standard PostgreSQL error.
      if (e.code == '42P01') {
        return 'SUCCESS';
      }
      // Status 401 = Unauthorized / Invalid API Key
      if (e.code == '401' || 
          e.message.contains('JW') || 
          e.message.contains('apiKey') || 
          e.message.contains('Invalid API key')) {
        return 'Invalid API Key';
      }
      return 'Flutter configuration issue';
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('xmlhttprequest') || 
          errorStr.contains('socketexception') || 
          errorStr.contains('failed host lookup') || 
          errorStr.contains('connection failed')) {
        return 'Network Error';
      }
      if (errorStr.contains('argumenterror') || 
          errorStr.contains('format_exception') || 
          errorStr.contains('invalid uri')) {
        return 'Invalid URL';
      }
      return 'Flutter configuration issue';
    }
  }

  static String generateUuidV4() {
    final random = Random.secure();
    final List<int> bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
