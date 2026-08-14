import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final client = SupabaseClient(
    'https://gilxxyvwqucwwwqaxosx.supabase.co',
    'sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP',
  );

  test('debug attendance', () async {
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
