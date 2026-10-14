class Env {
  /// Reads SUPABASE_URL from Dart environment variables.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Reads SUPABASE_ANON_KEY from Dart environment variables.
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Configurable Attendance Display base URL
  static const String displayBaseUrl = String.fromEnvironment('DISPLAY_BASE_URL');
}
