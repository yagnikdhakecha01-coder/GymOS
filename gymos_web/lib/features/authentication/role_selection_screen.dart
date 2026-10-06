import 'package:flutter/material.dart';
import '../auth/web_qr_login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  final bool isAddProfile;

  const RoleSelectionScreen({super.key, this.isAddProfile = false});

  @override
  Widget build(BuildContext context) {
    return const WebQrLoginScreen();
  }
}
