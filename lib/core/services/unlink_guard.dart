import 'package:flutter/material.dart';
import '../../features/authentication/auth_viewmodel.dart';
import '../../features/authentication/role_selection_screen.dart';
import '../navigation/app_router.dart';

/// Forces immediate logout + redirect when a staff/member account was unlinked.
/// No dialog — user is sent to the login screen automatically.
class UnlinkGuard {
  static bool _isHandling = false;

  /// Returns true if the user was unlinked and redirect was triggered.
  static Future<bool> checkAndForceLogout(
    BuildContext context,
    AuthViewModel authVm,
  ) async {
    if (_isHandling) return true;

    final wasUnlinked = await authVm.forceLogoutIfUnlinked();
    if (!wasUnlinked) return false;

    _isHandling = true;
    try {
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          AppRouter.scaleRoute(const RoleSelectionScreen()),
          (route) => false,
        );
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _isHandling = false;
      });
    }
    return true;
  }
}
