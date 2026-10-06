import 'env.dart';

class SupabaseConfig {
  static String? _dynamicUrl;
  static String? _dynamicAnonKey;

  static void setDynamicConfig(String url, String anonKey) {
    _dynamicUrl = url;
    _dynamicAnonKey = anonKey;
  }

  /// Exposes the Supabase URL read from environment or dynamic config.
  static String get url {
    final envUrl = Env.supabaseUrl;
    if (envUrl.isNotEmpty) {
      return envUrl.replaceAll('"', '').replaceAll("'", '').trim();
    }
    return (_dynamicUrl ?? '').replaceAll('"', '').replaceAll("'", '').trim();
  }

  /// Exposes the Supabase Anon Key read from environment or dynamic config.
  static String get anonKey {
    final envAnon = Env.supabaseAnonKey;
    if (envAnon.isNotEmpty) {
      return envAnon.replaceAll('"', '').replaceAll("'", '').trim();
    }
    return (_dynamicAnonKey ?? '').replaceAll('"', '').replaceAll("'", '').trim();
  }

  /// Checks if both URL and Anon Key are valid and non-empty.
  static bool get isValid => url.isNotEmpty && anonKey.isNotEmpty;
}
