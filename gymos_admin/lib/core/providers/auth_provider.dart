import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AdminAuthService _authService = AdminAuthService();

  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _error;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get error => _error;
  String? get userEmail => _authService.currentUser?.email;
  String? get userId => _authService.currentUser?.id;

  AuthProvider() {
    checkSession();
  }

  Future<void> checkSession() async {
    if (_authService.isLoggedIn) {
      _isLoading = true;
      notifyListeners();
      try {
        final isAdmin = await _authService.verifySuperAdmin();
        _isAuthenticated = isAdmin;
      } catch (_) {
        _isAuthenticated = false;
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> signUp(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final user = await _authService.signUp(email: email, password: password);
      if (user == null) {
        _error = 'Registration failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      _isLoading = false;
      notifyListeners();
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
    await _authService.signOut();
    _isAuthenticated = false;
    notifyListeners();
  }
}
