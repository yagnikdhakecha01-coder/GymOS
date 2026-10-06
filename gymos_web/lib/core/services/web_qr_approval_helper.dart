import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme.dart';
import 'supabase_service.dart';
import 'local_storage.dart';

class WebQrApprovalHelper {
  /// Checks if the scanned string is a GymOS Web Login QR code
  static bool isWebLoginQr(String code) {
    return code.trim().startsWith('gymos_web_login:');
  }

  /// Handles the QR code, showing an approval bottom sheet
  static Future<bool> handleScan(BuildContext context, String code) async {
    final token = code.trim().replaceFirst('gymos_web_login:', '').trim();
    if (token.isEmpty) return false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WebLoginApprovalSheet(token: token),
    );

    return result ?? false;
  }
}

class _WebLoginApprovalSheet extends StatefulWidget {
  final String token;

  const _WebLoginApprovalSheet({required this.token});

  @override
  State<_WebLoginApprovalSheet> createState() => _WebLoginApprovalSheetState();
}

class _WebLoginApprovalSheetState extends State<_WebLoginApprovalSheet> {
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;

  String _getMobileDeviceName() {
    if (kIsWeb) return 'Web Client';
    try {
      if (Platform.isAndroid) return 'Android Phone';
      if (Platform.isIOS) return 'iPhone';
    } catch (_) {}
    return 'Mobile App';
  }

  Future<void> _approve() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await SupabaseService.client.rpc(
        'approve_web_qr_login',
        params: {
          'p_token': widget.token,
          'p_scanner_device_name': _getMobileDeviceName(),
        },
      );

      final data = res as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });

        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = data?['error'] as String? ?? 'Could not approve login request.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = LocalStorageService.instance;
    final role = storage?.getUserRole()?.toUpperCase() ?? 'USER';
    final gymInfo = storage?.getGymInfo();
    final gymName = gymInfo?['name'] as String? ?? 'GymOS';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            if (_isSuccess) ...[
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: AppTheme.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 44),
              ),
              const SizedBox(height: 16),
              Text(
                'Logged in Successfully!',
                style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Your computer web portal has been unlocked.',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
            ] else ...[
              // Device / Laptop Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2), width: 1.5),
                ),
                child: const Icon(Icons.laptop_mac_rounded, color: AppTheme.primary, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                'Log in to GymOS Web?',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A computer is requesting access to your gym account.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),

              // Account info box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        role,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        gymName,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _approve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Approve & Log In',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
