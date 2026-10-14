class Env {
  /// Reads SUPABASE_URL from Dart environment variables.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Reads SUPABASE_ANON_KEY from Dart environment variables.
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Reads RAZORPAY_KEY_ID from Dart environment variables or uses default live key.
  static const String razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID', defaultValue: 'rzp_live_TkaAcBNqI1IitC');

  /// Configurable Attendance Display base URL
  static const String displayBaseUrl = String.fromEnvironment('DISPLAY_BASE_URL');
}
