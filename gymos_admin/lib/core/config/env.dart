class AdminEnv {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gilxxyvwqucwwwqaxosx.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP',
  );
}
