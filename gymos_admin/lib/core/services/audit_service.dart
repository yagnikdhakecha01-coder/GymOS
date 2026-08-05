import 'supabase_service.dart';

class AuditService {
  static Future<void> log({
    required String action,
    required String category,
    String? gymId,
    String? gymName,
    String? details,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (!AdminSupabaseService.isInitialized) return;
      final user = AdminSupabaseService.client.auth.currentUser;
      await AdminSupabaseService.client.from('audit_logs').insert({
        'admin_id': user?.id,
        'admin_email': user?.email,
        'action': action,
        'category': category,
        'gym_id': gymId,
        'gym_name': gymName,
        'details': details,
        'metadata': metadata,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }
}
