import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/services/supabase_service.dart';
import '../attendance/owner_scanner_screen.dart';

class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _devices = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLinkedDevices();
  }

  Future<void> _loadLinkedDevices() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await SupabaseService.client.rpc('get_linked_web_devices');
      final data = res as Map<String, dynamic>?;

      if (data != null && data['success'] == true) {
        final list = List<Map<String, dynamic>>.from(data['devices'] ?? []);
        if (mounted) {
          setState(() {
            _devices = list;
            _isLoading = false;
          });
        }
      } else {
        // Fallback direct query if RPC error
        final userId = SupabaseService.client.auth.currentUser?.id;
        if (userId != null) {
          final rows = await SupabaseService.client
              .from('web_login_sessions')
              .select('*')
              .eq('user_id', userId)
              .inFilter('status', ['approved', 'consumed'])
              .order('created_at', ascending: false);

          if (mounted) {
            setState(() {
              _devices = List<Map<String, dynamic>>.from(rows);
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _devices = [];
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load linked devices. Pull to refresh.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmRevoke(Map<String, dynamic> device) async {
    final deviceId = device['id']?.toString();
    final deviceName = device['device_name']?.toString() ?? 'Web Browser';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.dangerLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: AppTheme.danger, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Log out device?',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to log out from "$deviceName"? The session on that computer will be ended immediately.',
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'Log Out',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && deviceId != null) {
      await _revokeDevice(deviceId, deviceName);
    }
  }

  Future<void> _revokeDevice(String deviceId, String deviceName) async {
    // Optimistic UI update
    setState(() {
      _devices.removeWhere((d) => d['id']?.toString() == deviceId);
    });

    try {
      await SupabaseService.client.rpc(
        'revoke_web_login_session',
        params: {'p_session_id': deviceId},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Logged out from $deviceName',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error revoking web session: $e');
      _loadLinkedDevices();
    }
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return 'Active now';
    try {
      final dt = raw is DateTime ? raw : DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final timeStr = DateFormat('hh:mm a').format(dt);

      if (isToday) {
        return 'Today at $timeStr';
      }

      final yesterday = now.subtract(const Duration(days: 1));
      final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
      if (isYesterday) {
        return 'Yesterday at $timeStr';
      }

      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Linked Devices',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadLinkedDevices,
        color: AppTheme.primary,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            // Top Hero Card
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF6366F1),
                    Color(0xFF4F46E5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.devices_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Use GymOS on Web',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Access your gym dashboard, manage members, attendance, and finances on your PC or Laptop.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final scanned = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(builder: (_) => const OwnerQRScannerScreen(isCheckIn: true)),
                        );
                        if (scanned == true) {
                          _loadLinkedDevices();
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                      label: Text(
                        'Link a Device',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF4F46E5),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Section Title
            Row(
              children: [
                Text(
                  'DEVICE STATUS',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _devices.isNotEmpty ? AppTheme.successLight : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_devices.length} Active',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _devices.isNotEmpty ? AppTheme.success : AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_isLoading) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_devices.isEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.laptop_chromebook_rounded, color: Colors.grey.shade400, size: 30),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Linked Devices',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap "Link a Device" above to scan the QR code on your computer web browser.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ..._devices.map((device) {
                final deviceName = device['device_name']?.toString() ?? 'Web Browser';
                final approvedAt = device['approved_at'] ?? device['created_at'];
                final formattedTime = _formatDateTime(approvedAt);
                final ipAddress = device['ip_address']?.toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Laptop icon container
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.laptop_mac_rounded,
                          color: Color(0xFF4F46E5),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Device Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    deviceName,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Active',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.success,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Login: $formattedTime',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (ipAddress != null && ipAddress.isNotEmpty && ipAddress != 'null') ...[
                              const SizedBox(height: 2),
                              Text(
                                'IP: $ipAddress',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Log out button
                      IconButton(
                        tooltip: 'Log out device',
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: AppTheme.danger,
                            size: 18,
                          ),
                        ),
                        onPressed: () => _confirmRevoke(device),
                      ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 24),

            // Security note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your web sessions remain active continuously until you log out. If you don\'t recognize any device above, log out immediately.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
