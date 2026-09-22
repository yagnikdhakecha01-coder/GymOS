import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, String> _loadEnv() {
  final envFile = File('.env');
  if (!envFile.existsSync()) return {};
  final env = <String, String>{};
  for (var line in envFile.readAsLinesSync()) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final idx = line.indexOf('=');
    if (idx != -1) {
      final k = line.substring(0, idx).trim();
      var v = line.substring(idx + 1).trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      env[k] = v;
    }
  }
  return env;
}

void main() {
  final env = _loadEnv();
  final url = env['SUPABASE_URL'] ?? Platform.environment['SUPABASE_URL'] ?? '';
  final anonKey = env['SUPABASE_ANON_KEY'] ?? Platform.environment['SUPABASE_ANON_KEY'] ?? '';

  test('debug attendance', () async {
    if (url.isEmpty || anonKey.isEmpty) {
      print('Skipping debug test: SUPABASE_URL or SUPABASE_ANON_KEY not set.');
      return;
    }
    final client = SupabaseClient(url, anonKey);

    print('================== DEBUG STAFF ATTENDANCE ==================');

    print('1. Querying members table for role Staff or Keval...');
    final List members = await client.from('members').select().ilike('name', '%Keval%');
    print('Total Keval members found: ${members.length}');
    for (var m in members) {
      print('Member: ${m['name']}, Role: ${m['role']}, ID: ${m['id']}, GymID: ${m['gym_id']}, Shift: ${m['shift']}');
    }

    print('\n2. Querying user_gym_associations...');
    final List uga = await client.from('user_gym_associations').select();
    print('Total Associations: ${uga.length}');
    for (var u in uga) {
      print('  User: ${u['user_id']}, Gym: ${u['gym_id']}, Role: ${u['role']}');
    }

    print('\n3. Querying attendance_logs for all records today...');
    final List logs = await client
        .from('attendance_logs')
        .select()
        .order('check_in', ascending: false)
        .limit(20);
    print('Total recent logs: ${logs.length}');
    for (var l in logs) {
      print('  Log ID: ${l['id']}, Staff: ${l['staff_id']}, User: ${l['user_id']}, Date: ${l['date']}, Status: ${l['status']}, ShiftIdx: ${l['shift_index']}, CheckIn: ${l['check_in']}, CheckOut: ${l['check_out']}');
    }
  });
}
