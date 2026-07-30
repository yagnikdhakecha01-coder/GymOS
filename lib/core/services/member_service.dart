import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class MemberService {
  SupabaseClient get _client => SupabaseService.client;

  /// Regenerates a member's unique access code.
  /// Calls the secure PostgreSQL RPC function which validates owner permission,
  /// generates the new code, invalidates the old one, and registers an audit log.
  Future<String> regenerateAccessCode(String memberId) async {
    try {
      final newCode = await _client.rpc(
        'regenerate_member_access_code',
        params: {'member_uuid': memberId},
      ) as String;
      
      return newCode;
    } catch (e) {
      print('Regenerate access code error: $e');
      throw Exception('Failed to regenerate member access code: $e');
    }
  }
}
