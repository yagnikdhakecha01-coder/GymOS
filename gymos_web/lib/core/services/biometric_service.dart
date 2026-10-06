import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const String _keyBiometricEnabled = 'settings_biometric_lock';

  /// Check if the device has biometric hardware and if it's enrolled
  static Future<bool> isBiometricsSupported() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (_) {
      return false;
    }
  }

  /// Get the list of enrolled biometrics (e.g. fingerprint, face)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Get local configuration value
  static Future<bool> isLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometricEnabled) ?? false;
  }

  /// Check if Face ID or Fingerprint is available
  static Future<String> getBiometricTypeLabel() async {
    final List<BiometricType> available = await getAvailableBiometrics();
    if (available.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (available.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    }
    return 'Biometrics';
  }

  /// Authenticate the user
  static Future<bool> authenticate({String message = 'Authenticate to access Gym OS'}) async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: message,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      return didAuthenticate;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Persist biometric lock settings locally and in Supabase
  static Future<void> setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometricEnabled, enabled);

    if (SupabaseService.isInitialized) {
      try {
        final userId = SupabaseService.client.auth.currentUser?.id;
        if (userId != null) {
          await SupabaseService.client.from('user_settings').upsert({
            'user_id': userId,
            'biometric_lock': enabled,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
        // Non-fatal
      }
    }
  }
}
