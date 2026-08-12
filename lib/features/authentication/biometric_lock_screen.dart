import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/services/biometric_service.dart';
import '../../core/widgets/app_branding_header.dart';

class BiometricLockScreen extends StatefulWidget {
  final Widget targetScreen;

  const BiometricLockScreen({super.key, required this.targetScreen});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _authenticating = false;
  String _biometricLabel = 'Biometrics';

  @override
  void initState() {
    super.initState();
    _getLabelAndAuthenticate();
  }

  Future<void> _getLabelAndAuthenticate() async {
    final label = await BiometricService.getBiometricTypeLabel();
    if (mounted) {
      setState(() {
        _biometricLabel = label;
      });
    }
    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
    });

    final success = await BiometricService.authenticate(
      message: 'Scan your $_biometricLabel to unlock Gym OS',
    );

    if (mounted) {
      setState(() {
        _authenticating = false;
      });

      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => widget.targetScreen),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authentication failed. Please tap to retry.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final lockIcon = isIOS ? Icons.face_retouching_natural_rounded : Icons.fingerprint_rounded;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppBrandingHeader(
                  logoSize: 80,
                  fontSize: 32,
                  spacing: 20,
                  welcomeText: false,
                ),
                const SizedBox(height: 60),
                GestureDetector(
                  onTap: _authenticate,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primary.withOpacity(0.12), width: 2),
                    ),
                    child: Icon(
                      lockIcon,
                      size: 72,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Gym OS is Locked',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please authenticate using $_biometricLabel to unlock the application.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 48),
                if (!_authenticating)
                  SizedBox(
                    width: 200,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _authenticate,
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: Text(
                        'Unlock with $_biometricLabel',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
