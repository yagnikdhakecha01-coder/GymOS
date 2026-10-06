import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
      isScrollControlled: true,
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
  bool _isFetchingDetails = true;
  String? _errorMessage;
  String _webDeviceName = 'Computer Web Browser';
  String? _ipAddress;
  DateTime _requestTime = DateTime.now();
  String? _approvedRole;

  @override
  void initState() {
    super.initState();
    _fetchSessionDetails();
  }

  Future<void> _fetchSessionDetails() async {
    try {
      final res = await SupabaseService.client
          .from('web_login_sessions')
          .select('*')
          .or('token.eq.${widget.token},session_token.eq.${widget.token}')
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _webDeviceName = res['device_name']?.toString() ??
              res['user_agent']?.toString() ??
              'Computer Web Browser';
          _ipAddress = res['ip_address']?.toString();
          if (res['created_at'] != null) {
            _requestTime = DateTime.tryParse(res['created_at'].toString())?.toLocal() ?? DateTime.now();
          }
          _isFetchingDetails = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _isFetchingDetails = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isFetchingDetails = false;
        });
      }
    }
  }

  String _getMobileDeviceName() {
    if (kIsWeb) return 'Web Client';
    try {
      if (Platform.isAndroid) return 'Android Phone';
      if (Platform.isIOS) return 'iPhone';
    } catch (_) {}
    return 'Mobile Device';
  }

  Future<void> _approve() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final storage = LocalStorageService.instance;
      final role = (storage?.getUserRole() ?? 'owner').toLowerCase();
      final gymId = storage?.getGymInfo()?['id']?.toString();
      final currentSession = SupabaseService.client.auth.currentSession;
      final accessToken = currentSession?.accessToken;
      final refreshToken = currentSession?.refreshToken;

      final res = await SupabaseService.client.rpc(
        'approve_web_qr_login',
        params: {
          'p_token': widget.token,
          'p_scanner_device_name': _getMobileDeviceName(),
          'p_role': role,
          'p_gym_id': gymId,
          'p_access_token': accessToken,
          'p_refresh_token': refreshToken,
        },
      );

      final data = res as Map<String, dynamic>?;
      if (data != null && data['success'] == true) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
          _approvedRole = data['role']?.toString();
        });

        await Future.delayed(const Duration(milliseconds: 1400));
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

  String _formatTime(DateTime dt) {
    return DateFormat('dd MMM yyyy • hh:mm a').format(dt);
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
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 24),

            if (_isSuccess) ...[
              // Success Animation State
              Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: AppTheme.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 48),
              ),
              const SizedBox(height: 16),
              Text(
                'Web Portal Unlocked!',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Successfully logged in to $_webDeviceName',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'Time: ${_formatTime(DateTime.now())}',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 24),
            ] else ...[
              // Device / Laptop Icon
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2), width: 2),
                ),
                child: const Icon(Icons.laptop_mac_rounded, color: Color(0xFF4F46E5), size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Log in to GymOS Web?',
                style: GoogleFonts.inter(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A computer browser is requesting access to your gym account.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),

              // Device & Login Time Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    // Target Web Device
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Icon(Icons.desktop_windows_rounded, size: 20, color: Color(0xFF4F46E5)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Web Device',
                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _webDeviceName,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_ipAddress != null && _ipAddress!.isNotEmpty && _ipAddress != 'null') ...[
                                const SizedBox(height: 2),
                                Text(
                                  'IP: $_ipAddress',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 20),

                    // Login Request Time
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Icon(Icons.access_time_filled_rounded, size: 20, color: Color(0xFFF59E0B)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Login Time',
                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _formatTime(_requestTime),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 20),

                    // Approving Account
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Icon(Icons.shield_rounded, size: 20, color: Color(0xFF10B981)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Approving Account',
                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '$gymName ($role)',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 13),
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
                        backgroundColor: const Color(0xFF4F46E5),
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
