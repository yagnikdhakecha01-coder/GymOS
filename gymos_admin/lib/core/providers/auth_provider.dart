import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/google_drive_service.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final AdminAuthService _authService = AdminAuthService();
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _heartbeatTimer;

  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _error;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get error => _error;
  String? get userEmail => _authService.currentUser?.email;
  String? get userId => _authService.currentUser?.id;

  AuthProvider() {
    _initAuthListener();
    checkSession();
    _startHeartbeat();
  }

  void _initAuthListener() {
    try {
      if (AdminSupabaseService.isInitialized) {
        _authSubscription = AdminSupabaseService.client.auth.onAuthStateChange.listen((data) async {
          final AuthChangeEvent event = data.event;
          final Session? session = data.session;
          if (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.tokenRefreshed) {
            if (session != null && !_isAuthenticated) {
              await checkSession();
            }
          } else if (event == AuthChangeEvent.signedOut) {
            _isAuthenticated = false;
            notifyListeners();
          }
        });
      }
    } catch (e) {
      debugPrint('Error setting up auth state listener: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Check and refresh token every 15 minutes to prevent session expiration (Supabase JWT expires in 60m)
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 15), (_) async {
      if (_isAuthenticated) {
        try {
          final session = await AdminSupabaseService.ensureValidSession();
          if (session == null && _authService.currentSession == null) {
            await checkSession();
          }
        } catch (e) {
          debugPrint('Heartbeat session refresh error: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncGoogleTokensIfAvailable() async {
    try {
      final session = _authService.currentSession;
      if (session != null && session.providerToken != null && session.providerToken!.isNotEmpty) {
        await GoogleDriveService.saveCredentials(
          accessToken: session.providerToken!,
          refreshToken: (session.providerRefreshToken != null && session.providerRefreshToken!.isNotEmpty)
              ? session.providerRefreshToken
              : null,
          clientId: GoogleDriveService.defaultClientId,
        );
      }
    } catch (e) {
      debugPrint('Error syncing Google Drive tokens: $e');
    }
  }

  Future<void> checkSession() async {
    try {
      if (_authService.isLoggedIn) {
        _isLoading = true;
        notifyListeners();
        try {
          final isAdmin = await _authService.verifySuperAdmin();
          _isAuthenticated = isAdmin;
          if (isAdmin) {
            await _syncGoogleTokensIfAvailable();
          }
        } catch (_) {
          _isAuthenticated = false;
        } finally {
          _isLoading = false;
          notifyListeners();
        }
      } else {
        _isAuthenticated = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in AuthProvider.checkSession: $e');
      _isAuthenticated = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> loginWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final success = await _authService.signInWithGoogle();
      if (!success) {
        _error = 'Google Sign-In failed or was cancelled';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      _startHeartbeat();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('AuthException: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = await _authService.signIn(email: email, password: password);
      if (user == null) {
        _error = 'Invalid credentials';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final isAdmin = await _authService.verifySuperAdmin();
      if (!isAdmin) {
        await _authService.signOut();
        _error = 'Access denied. Super Admin only.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await _authService.logLoginEvent();
      _isAuthenticated = true;
      _isLoading = false;
      _startHeartbeat();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('AuthException: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _heartbeatTimer?.cancel();
    await _authService.signOut();
    _isAuthenticated = false;
    notifyListeners();
  }
}
