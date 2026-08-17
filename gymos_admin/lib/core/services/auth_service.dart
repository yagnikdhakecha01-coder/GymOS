import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AdminAuthService {
  SupabaseClient? get _client {
    try {
      return AdminSupabaseService.isInitialized ? AdminSupabaseService.client : null;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser {
    try {
      return _client?.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Session? get currentSession {
    try {
      return _client?.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  bool get isLoggedIn {
    try {
      return currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<User?> signUp({required String email, required String password}) async {
    if (_client == null) return null;
    final response = await _client!.auth.signUp(
      email: email,
      password: password,
    );
    return response.user;
  }

  Future<User?> signIn({required String email, required String password}) async {
    if (_client == null) return null;
    final response = await _client!.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user;
  }

  Future<bool> signInWithGoogle() async {
    if (_client == null) return false;
    final String? webRedirect = kIsWeb ? '${Uri.base.origin}/' : null;
    return await _client!.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: webRedirect,
      queryParams: {'prompt': 'select_account'},
    );
  }

  Future<void> signOut() async {
    if (_client != null) {
      try {
        await _client!.auth.signOut();
      } catch (_) {}
    }
  }

  /// Verify the logged-in user is a super admin
  Future<bool> verifySuperAdmin() async {
    if (_client == null || currentUser == null) return false;
    try {
      final result = await _client!
          .from('admin_users')
          .select('role')
          .eq('user_id', currentUser!.id)
          .eq('role', 'super_admin')
          .maybeSingle();
      return result != null;
    } catch (_) {
      // If admin_users table doesn't exist yet, allow login for setup
      return true;
    }
  }

  /// Log login event
  Future<void> logLoginEvent({String? deviceInfo, String? ipAddress}) async {
    if (_client == null || currentUser == null) return;
    try {
      await _client!.from('admin_sessions').insert({
        'user_id': currentUser!.id,
        'device_info': deviceInfo ?? 'Web Browser',
        'ip_address': ipAddress,
        'logged_in_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }
}
