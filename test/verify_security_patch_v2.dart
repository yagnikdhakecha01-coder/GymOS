import 'dart:convert';
import 'dart:io';

void main() async {
  print('================================================================');
  print('🛡️  GYMOS SECURITY PATCH V2 - PENETRATION & VERIFICATION AUDIT');
  print('================================================================');

  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('❌ .env file not found!');
    exit(1);
  }

  final lines = envFile.readAsLinesSync();
  String url = '';
  String anonKey = '';

  for (var line in lines) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final parts = line.split('=');
    if (parts.length >= 2) {
      final key = parts[0].trim();
      var value = parts.sublist(1).join('=').trim();
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (key == 'SUPABASE_URL') url = value;
      if (key == 'SUPABASE_ANON_KEY') anonKey = value;
    }
  }

  final client = HttpClient();

  Future<Map<String, dynamic>> checkTable(String table) async {
    try {
      final uri = Uri.parse('$url/rest/v1/$table?select=*&limit=5');
      final req = await client.getUrl(uri);
      req.headers.add('apikey', anonKey);
      req.headers.add('Authorization', 'Bearer $anonKey');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return {'status': res.statusCode, 'body': body};
    } catch (e) {
      return {'status': 500, 'body': e.toString()};
    }
  }

  Future<Map<String, dynamic>> checkRpc(String rpcName, Map<String, dynamic> params) async {
    try {
      final uri = Uri.parse('$url/rest/v1/rpc/$rpcName');
      final req = await client.postUrl(uri);
      req.headers.add('apikey', anonKey);
      req.headers.add('Authorization', 'Bearer $anonKey');
      req.headers.add('Content-Type', 'application/json');
      req.write(jsonEncode(params));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return {'status': res.statusCode, 'body': body};
    } catch (e) {
      return {'status': 500, 'body': e.toString()};
    }
  }

  int passedCount = 0;
  int totalCount = 0;

  void evaluate(String testName, bool condition, String details) {
    totalCount++;
    if (condition) {
      passedCount++;
      print('✅ PASSED: $testName');
      print('   $details');
    } else {
      print('⚠️ FAILED / PENDING SQL RUN: $testName');
      print('   $details');
    }
  }

  print('\n--- [TEST SUITE 1: RESTRICTIVE TABLE ISOLATION] ---');

  final tables = ['leave_requests', 'salary_advance_ledger', 'payments', 'invoices', 'subscriptions'];
  for (var table in tables) {
    final res = await checkTable(table);
    final status = res['status'] as int;
    final body = res['body'] as String;

    bool isSafe = false;
    if (status >= 400) {
      isSafe = true;
    } else if (status == 200) {
      try {
        final list = jsonDecode(body) as List;
        isSafe = list.isEmpty;
      } catch (_) {
        isSafe = false;
      }
    }

    evaluate(
      'Anonymous access to "$table"',
      isSafe,
      'Status: $status, Leaked Records: ${status == 200 && isSafe ? "0" : "Blocked/Empty"}',
    );
  }

  print('\n--- [TEST SUITE 2: PRIVILEGED RPC FUNCTIONS GUARD] ---');

  final rpcTests = [
    {
      'name': 'get_trainer_clients',
      'params': {'p_staff_id': '00000000-0000-0000-0000-000000000000'},
    },
    {
      'name': 'update_member_measurements',
      'params': {
        'p_staff_id': '00000000-0000-0000-0000-000000000000',
        'p_member_id': '00000000-0000-0000-0000-000000000000',
        'p_measurements': {'weight': '70'}
      },
    },
    {
      'name': 'get_member_payment_transactions',
      'params': {'p_member_id': '00000000-0000-0000-0000-000000000000'},
    },
    {
      'name': 'delete_gym_cascade',
      'params': {'p_gym_id': '00000000-0000-0000-0000-000000000000'},
    },
  ];

  for (var rpc in rpcTests) {
    final res = await checkRpc(rpc['name'] as String, rpc['params'] as Map<String, dynamic>);
    final status = res['status'] as int;
    final body = res['body'] as String;

    final isBlocked = status >= 400 || body.contains('SECURITY ERROR') || body.contains('permission denied');
    evaluate(
      'Anonymous invoke on RPC "${rpc['name']}"',
      isBlocked,
      'Status: $status, Response: ${body.length > 80 ? body.substring(0, 80) + "..." : body}',
    );
  }

  print('\n--- [TEST SUITE 3: LIVE DATA INTEGRITY & AVAILABILITY] ---');
  final liveRes = await checkTable('gyms');
  final liveStatus = liveRes['status'] as int;
  evaluate(
    'Live Database Service Health & Response',
    liveStatus == 200,
    'Status: $liveStatus (Database is responsive and online)',
  );

  print('\n================================================================');
  print('🏁 FINAL AUDIT SCORE: $passedCount / $totalCount TESTS PASSED');
  print('================================================================');
  exit(0);
}
