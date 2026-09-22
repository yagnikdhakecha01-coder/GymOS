import 'dart:convert';
import 'dart:io';

void main() async {
  print('================================================================');
  print('🔍 READ-ONLY SECURITY AUDIT & VULNERABILITY RECON SCAN');
  print('   (Strictly Non-Destructive - Zero Data Modification)');
  print('================================================================');

  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('❌ .env not found');
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

  Future<Map<String, dynamic>> checkTable(String table, String select) async {
    try {
      final uri = Uri.parse('$url/rest/v1/$table?select=$select&limit=3');
      final req = await client.getUrl(uri);
      req.headers.add('apikey', anonKey);
      req.headers.add('Authorization', 'Bearer $anonKey');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return {
        'statusCode': res.statusCode,
        'body': body,
      };
    } catch (e) {
      return {'statusCode': 500, 'body': e.toString()};
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
      return {
        'statusCode': res.statusCode,
        'body': body,
      };
    } catch (e) {
      return {'statusCode': 500, 'body': e.toString()};
    }
  }

  final tablesToTest = [
    {'name': 'subscriptions', 'cols': 'id,gym_id,plan_id,status'},
    {'name': 'payments', 'cols': 'id,gym_id,amount,status,payment_method'},
    {'name': 'invoices', 'cols': 'id,gym_id,amount,invoice_number'},
    {'name': 'subscription_history', 'cols': 'id,gym_id,old_plan_id,new_plan_id'},
    {'name': 'leave_requests', 'cols': 'id,gym_id,staff_id,status'},
    {'name': 'salary_advance_ledger', 'cols': 'id,gym_id,staff_id,amount'},
    {'name': 'attendance_audit_log', 'cols': 'id,gym_id,action,created_at'},
    {'name': 'support_messages', 'cols': 'id,ticket_id,message'},
    {'name': 'members', 'cols': 'id,gym_id,name,phone'},
    {'name': 'staff', 'cols': 'id,gym_id,name,phone,salary'},
    {'name': 'finance_transactions', 'cols': 'id,gym_id,amount,category'},
  ];

  print('\n[PHASE 1] Testing Anonymous Read Access on Critical Tables:\n');
  for (var t in tablesToTest) {
    final result = await checkTable(t['name']!, t['cols']!);
    final status = result['statusCode'];
    final body = result['body'] as String;

    if (status == 200) {
      try {
        final list = jsonDecode(body) as List;
        if (list.isNotEmpty) {
          print('🔴 VULNERABLE: Table "${t['name']}" is LEAKING data anonymously! (${list.length} rows exposed)');
        } else {
          print('🟢 PROTECTED: Table "${t['name']}" returned empty array (0 rows leaked).');
        }
      } catch (_) {
        print('🟡 INFO: Table "${t['name']}" status 200: $body');
      }
    } else if (status == 401 || status == 403) {
      print('🟢 PROTECTED: Table "${t['name']}" rejected with HTTP $status (Access Denied).');
    } else {
      print('⚪ Table "${t['name']}" returned status: $status');
    }
  }

  print('\n[PHASE 2] Testing Anonymous Call on High-Privilege RPCs:\n');
  final rpcsToTest = [
    {
      'name': 'get_trainer_clients',
      'params': {'p_staff_id': '00000000-0000-0000-0000-000000000000'}
    },
    {
      'name': 'get_member_payment_transactions',
      'params': {'p_member_id': '00000000-0000-0000-0000-000000000000'}
    },
    {
      'name': 'fn_user_accessible_gym_ids',
      'params': {'p_user_id': '00000000-0000-0000-0000-000000000000'}
    },
  ];

  for (var r in rpcsToTest) {
    final result = await checkRpc(r['name'] as String, r['params'] as Map<String, dynamic>);
    final status = result['statusCode'];
    final body = result['body'] as String;

    if (status == 200) {
      print('🔴 VULNERABLE: RPC "${r['name']}" is callable by ANONYMOUS users! Status: 200');
    } else if (status == 401 || status == 403) {
      print('🟢 PROTECTED: RPC "${r['name']}" blocked with HTTP $status');
    } else {
      print('⚪ RPC "${r['name']}" responded with HTTP $status: $body');
    }
  }

  print('\n================================================================');
  print('🏁 AUDIT SCAN FINISHED');
  print('================================================================');
  exit(0);
}
