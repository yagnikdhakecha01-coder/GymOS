import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print('Initializing Supabase client...');
  final supabase = await Supabase.initialize(
    url: 'https://gilxxyvwqucwwwqaxosx.supabase.co',
    anonKey: 'sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP',
  );
  
  final client = supabase.client;
  
  try {
    print('Testing query to attendance_displays...');
    final response = await client.from('attendance_displays').select();
    print('Query succeeded! Registered displays count: ${response.length}');
    print('Data: $response');
  } catch (e) {
    print('Query failed with error: $e');
  }
}
