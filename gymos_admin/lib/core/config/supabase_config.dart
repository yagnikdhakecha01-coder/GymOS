import 'env.dart';

class AdminSupabaseConfig {
  static String? _dynamicUrl;
  static String? _dynamicAnonKey;

  static void setDynamicConfig(String url, String anonKey) {
    _dynamicUrl = url;
    _dynamicAnonKey = anonKey;
  }

  static String get url {
    final envUrl = AdminEnv.supabaseUrl;
    if (envUrl.isNotEmpty) {
      return envUrl.replaceAll('"', '').replaceAll("'", '').trim();
    }
    return (_dynamicUrl ?? '').replaceAll('"', '').replaceAll("'", '').trim();
  }

  static String get anonKey {
    final envAnon = AdminEnv.supabaseAnonKey;
    if (envAnon.isNotEmpty) {
      return envAnon.replaceAll('"', '').replaceAll("'", '').trim();
    }
    return (_dynamicAnonKey ?? '').replaceAll('"', '').replaceAll("'", '').trim();
  }

  static bool get isValid => url.isNotEmpty && anonKey.isNotEmpty;
}
