import 'dart:io';
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

void main() async {
  final env = _loadEnv();
  final url = env['SUPABASE_URL'] ?? Platform.environment['SUPABASE_URL'] ?? '';
  final anonKey = env['SUPABASE_ANON_KEY'] ?? Platform.environment['SUPABASE_ANON_KEY'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    print('Error: SUPABASE_URL or SUPABASE_ANON_KEY not set in .env or environment.');
    exit(1);
  }

  print('Initializing Supabase client from environment...');
  final client = SupabaseClient(url, anonKey);
  
  try {
    print('Checking total member count...');
    final List allMembers = await client.from('members').select('id, name, phone');
    print('Total members in DB: ${allMembers.length}');
    for (var m in allMembers.take(20)) {
      print('  - Name: ${m['name']}, Phone: ${m['phone']}, ID: ${m['id']}');
    }
    
    print('\nSearching for name containing "Jigar" (case-insensitive)...');
    final List matchName = await client
        .from('members')
        .select()
        .ilike('name', '%Jigar%');
        
    print('Matching members count: ${matchName.length}');
    for (var member in matchName) {
      final memberId = member['id'];
      print('\n================== MEMBER RECORD ==================');
      print('ID: $memberId');
      print('Name: ${member['name']}');
      print('Phone: ${member['phone']}');
      print('Pending Amount: ${member['pending_amount']}');
      print('Total Received Amount: ${member['total_received_amount']}');
      print('Payment Status: ${member['payment_status']}');
      print('Raw Member JSON: $member');
      
      print('\n================== MEMBER MEMBERSHIPS ==================');
      final List memberships = await client
          .from('member_memberships')
          .select()
          .eq('member_id', memberId);
      for (var m in memberships) {
        print('Membership ID: ${m['id']}');
        print('  Plan ID: ${m['plan_id']}');
        print('  Start Date: ${m['start_date']}');
        print('  End Date: ${m['end_date']}');
        print('  Total Amount: ${m['total_amount']}');
        print('  Paid Amount: ${m['paid_amount']}');
        print('  Status: ${m['status']}');
        print('  Payment Status: ${m['payment_status']}');
        print('  Raw: $m');
        
        print('  ------------------ PAYMENTS FOR THIS MEMBERSHIP ------------------');
        final List payments = await client
            .from('membership_payments')
            .select()
            .eq('member_membership_id', m['id']);
        for (var p in payments) {
          print('  Payment ID: ${p['id']}');
          print('    Amount: ${p['amount']}');
          print('    Date: ${p['payment_date']}');
          print('    Mode: ${p['payment_mode']}');
          print('    Transaction ID: ${p['transaction_id']}');
          print('    Raw: $p');
        }
      }
      
      print('\n================== FINANCE TRANSACTIONS ==================');
      final List txs = await client
          .from('finance_transactions')
          .select()
          .eq('reference_id', memberId);
      for (var tx in txs) {
        print('TX ID: ${tx['id']}');
        print('  Amount: ${tx['amount']}');
        print('  Type: ${tx['type']}');
        print('  Category: ${tx['category']}');
        print('  Date: ${tx['transaction_date']}');
        print('  Raw: $tx');
      }
    }
  } catch (e) {
    print('Query failed with error: $e');
  }
}
