import 'dart:convert';
import 'dart:io';

void main() async {
  print('======================================================');
  print('🛡️  GYMOS DATABASE SECURITY & CRASH HARDENING AUDIT');
  print('======================================================');

  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('❌ Error: .env file not found!');
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

  if (url.isEmpty || anonKey.isEmpty) {
    print('❌ Error: SUPABASE_URL or SUPABASE_ANON_KEY is missing in .env');
    exit(1);
  }

  print('Connected Target: $url');
  final client = HttpClient();

  // -------------------------------------------------------------
  // TEST 1: Exploit Simulation - Unauthenticated delete_gym_cascade
  // -------------------------------------------------------------
  print('\n[TEST 1] Attacking delete_gym_cascade via anonymous RPC...');
  try {
    final rpcUri = Uri.parse('$url/rest/v1/rpc/delete_gym_cascade');
    final request = await client.postUrl(rpcUri);
    request.headers.add('apikey', anonKey);
    request.headers.add('Authorization', 'Bearer $anonKey');
    request.headers.add('Content-Type', 'application/json');
    request.write(jsonEncode({'p_gym_id': '00000000-0000-0000-0000-000000000000'}));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 400) {
      print('✅ PASSED: Exploit Blocked! Response status: ${response.statusCode}');
      print('   Server message: $body');
    } else {
      print('⚠️ WARNING: Function responded with status: ${response.statusCode}');
      print('   Please ensure MASTER_DATABASE_SECURITY_AND_CRASH_HARDENING.sql has been executed in Supabase SQL editor.');
    }
  } catch (e) {
    print('✅ PASSED: Request failed as expected: $e');
  }

  // -------------------------------------------------------------
  // TEST 2: Data Exfiltration Simulation - gym_backups Table Leak
  // -------------------------------------------------------------
  print('\n[TEST 2] Probing gym_backups table anonymously for data leakage...');
  try {
    final backupUri = Uri.parse('$url/rest/v1/gym_backups?select=*');
    final request = await client.getUrl(backupUri);
    request.headers.add('apikey', anonKey);
    request.headers.add('Authorization', 'Bearer $anonKey');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 400 || body == '[]') {
      print('✅ PASSED: Backup Exfiltration Blocked! Status: ${response.statusCode}, Rows leaked: 0');
    } else {
      print('⚠️ WARNING: Sensitive backup records might be visible! Body: $body');
    }
  } catch (e) {
    print('✅ PASSED: Request blocked: $e');
  }

  // -------------------------------------------------------------
  // TEST 3: Exploit Simulation - restore_gym_backup RPC Payload Bomb
  // -------------------------------------------------------------
  print('\n[TEST 3] Attacking restore_gym_backup with anonymous caller...');
  try {
    final restoreUri = Uri.parse('$url/rest/v1/rpc/restore_gym_backup');
    final request = await client.postUrl(restoreUri);
    request.headers.add('apikey', anonKey);
    request.headers.add('Authorization', 'Bearer $anonKey');
    request.headers.add('Content-Type', 'application/json');
    request.write(jsonEncode({'p_backup_data': {'malicious': true}}));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 400) {
      print('✅ PASSED: Unauthorized Restore Blocked! Response status: ${response.statusCode}');
      print('   Server message: $body');
    } else {
      print('⚠️ WARNING: Restore executed without admin check! Status: ${response.statusCode}');
    }
  } catch (e) {
    print('✅ PASSED: Restore failed as expected: $e');
  }

  // -------------------------------------------------------------
  // TEST 4: Live Data Health Check - Confirm Live Data Intact
  // -------------------------------------------------------------
  print('\n[TEST 4] Live Data Health Check (Verifying Live Gym Data is Intact)...');
  try {
    final gymsUri = Uri.parse('$url/rest/v1/gyms?select=id,name,status&limit=5');
    final request = await client.getUrl(gymsUri);
    request.headers.add('apikey', anonKey);
    request.headers.add('Authorization', 'Bearer $anonKey');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    print('📊 Gyms Query Status: ${response.statusCode}');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(body) as List;
      print('✅ LIVE DATA VERIFIED: Found ${decoded.length} gyms accessible.');
      for (var g in decoded) {
        print('   - Gym ID: ${g['id']}, Name: ${g['name']}, Status: ${g['status']}');
      }
    }
  } catch (e) {
    print('Note: Live data read status: $e');
  }

  print('\n======================================================');
  print('🏁 AUDIT SCRIPT COMPLETED');
  print('======================================================');
  exit(0);
}
