import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/theme.dart';
import '../../core/config/env.dart';
import '../../features/authentication/auth_viewmodel.dart';
import '../../core/services/supabase_service.dart';
import 'attendance_viewmodel.dart';
import 'emergency_attendance_hub_screen.dart';
import 'owner_attendance_correction_screen.dart';

class OwnerQrSettingsScreen extends StatefulWidget {
  const OwnerQrSettingsScreen({super.key});

  @override
  State<OwnerQrSettingsScreen> createState() => _OwnerQrSettingsScreenState();
}

class _OwnerQrSettingsScreenState extends State<OwnerQrSettingsScreen> {
  bool _biometricEnabled = false;
  String _deviceSecret = '';
  bool _loadingBiometric = true;
  bool _showSecret = false;
  int _connectedDevicesCount = 0;
  String _biometricConnectionMode = 'bridge'; // 'bridge' or 'cloud'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBiometricSettings());
  }

  String _resolveGymId() {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final attVm = Provider.of<AttendanceViewModel>(context, listen: false);
    return authVm.activeAssociation?.gymId ??
        authVm.gymInfo?['id'] ??
        attVm.settings?.gymId ??
        '';
  }

  Future<void> _loadBiometricSettings() async {
    final gymId = _resolveGymId();
    if (gymId.isEmpty) {
      if (mounted) setState(() => _loadingBiometric = false);
      return;
    }

    try {
      final res = await SupabaseService.client.rpc(
        'get_or_create_gym_biometric_settings',
        params: {'p_gym_id': gymId},
      );

      if (mounted && res != null) {
        final data = Map<String, dynamic>.from(res as Map);
        setState(() {
          _biometricEnabled = data['enabled'] == true;
          _deviceSecret = (data['secret'] ?? '').toString();
          _connectedDevicesCount = (data['device_count'] as num?)?.toInt() ?? 0;
          _loadingBiometric = false;
        });
      }
    } catch (e) {
      debugPrint('[Biometric] Error loading settings: $e');
      if (mounted) setState(() => _loadingBiometric = false);
    }
  }

  Future<void> _toggleBiometric(bool val) async {
    final gymId = _resolveGymId();
    if (gymId.isEmpty) return;

    setState(() => _biometricEnabled = val);
    try {
      await SupabaseService.client.rpc(
        'toggle_gym_biometric_attendance',
        params: {'p_gym_id': gymId, 'p_enabled': val},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(val ? 'Biometric Attendance Enabled' : 'Biometric Attendance Disabled'),
            backgroundColor: val ? AppTheme.success : AppTheme.textSecondary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _biometricEnabled = !val);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _regenerateSecret() async {
    final gymId = _resolveGymId();
    if (gymId.isEmpty) return;

    try {
      final newSecret = await SupabaseService.client.rpc(
        'regenerate_gym_biometric_secret',
        params: {'p_gym_id': gymId},
      );
      if (mounted && newSecret != null) {
        setState(() => _deviceSecret = newSecret.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ New Secret Key Generated!'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to regenerate: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<AttendanceViewModel>(context);
    final authVm = Provider.of<AuthViewModel>(context);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? vm.settings?.gymId ?? '';

    // If biometric secret wasn't loaded because gymId was delayed during initial post-frame callback
    if (_deviceSecret.isEmpty && !_loadingBiometric && gymId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadBiometricSettings());
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Attendance Settings',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: vm.settings == null
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section: Status ──
                  Row(
                    children: [
                      Text(
                        'Enable Attendance Module',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const Spacer(),
                      Switch(
                        value: vm.settings?.isEnabled ?? true,
                        activeColor: AppTheme.primary,
                        onChanged: (val) => vm.toggleAttendanceEnabled(val),
                      ),
                    ],
                  ),
                  const Divider(height: 32, color: Color(0xFFF3F4F6)),

                      Text(
                        'Attendance Verification Method',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F9FB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: () {
                              final m = vm.settings?.method ?? 'Static QR';
                              if (m == 'Biometric') return 'Biometric';
                              if (m == 'QR + Biometric') return 'QR + Biometric';
                              if (m == 'Dynamic QR' || m == 'Dynamic QR + WiFi' || m == 'QR Only' || m == 'Dynamic QR + Gym WiFi') {
                                return 'Dynamic QR';
                              }
                              return 'Static QR';
                            }(),
                            isExpanded: true,
                            items: const [
                              DropdownMenuItem(
                                value: 'Static QR',
                                child: Row(
                                  children: [
                                    Icon(Icons.qr_code_rounded, size: 18, color: AppTheme.primary),
                                    SizedBox(width: 10),
                                    Text('Static QR Code', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5)),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'Dynamic QR',
                                child: Row(
                                  children: [
                                    Icon(Icons.qr_code_scanner_rounded, size: 18, color: AppTheme.primary),
                                    SizedBox(width: 10),
                                    Text('Dynamic QR (Auto Refresh)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5)),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'Biometric',
                                child: Row(
                                  children: [
                                    Icon(Icons.fingerprint_rounded, size: 18, color: AppTheme.primary),
                                    SizedBox(width: 10),
                                    Text('Biometric (Fingerprint & Face)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5)),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'QR + Biometric',
                                child: Row(
                                  children: [
                                    Icon(Icons.devices_other_rounded, size: 18, color: AppTheme.primary),
                                    SizedBox(width: 10),
                                    Text('QR + Biometric (Both)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13.5)),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                vm.updateAttendanceMethod(val);
                                if (val == 'Biometric' || val == 'QR + Biometric') {
                                  if (!_biometricEnabled) _toggleBiometric(true);
                                }
                              }
                            },
                          ),
                        ),
                      ),
                      if (vm.settings?.method == 'Biometric' || vm.settings?.method == 'QR + Biometric' || _biometricEnabled) ...[
                        const SizedBox(height: 16),
                        _buildBiometricCard(),
                      ],
                      
                      if (vm.settings?.method == 'Dynamic QR' || vm.settings?.method == 'QR Only' || vm.settings?.method == 'Dynamic QR + WiFi' || vm.settings?.method == 'QR + WiFi') ...[
                        const SizedBox(height: 16),
                        Text(
                          'QR Code Refresh Time',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [30, 60, 90, 120, 300].map((seconds) {
                            final isSelected = vm.settings?.qrValiditySeconds == seconds;
                            String label = '';
                            if (seconds < 60) {
                              label = '${seconds}s';
                            } else if (seconds == 90) {
                              label = '1.5m';
                            } else {
                              label = '${seconds ~/ 60}m';
                            }

                            return ChoiceChip(
                              label: Text(label),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) vm.updateQrValiditySeconds(seconds);
                              },
                              selectedColor: AppTheme.primary,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : AppTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 24),

                  // ── Section: WiFi Config ──
                  if (vm.isWiFiVerificationEnabled) ...[
                    Text(
                      'WiFi Verification Configuration',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF0F0F2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Registered SSID', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                                  const SizedBox(height: 4),
                                  Text(
                                    vm.savedGymWiFiSSID.isEmpty ? "None Registered" : vm.savedGymWiFiSSID,
                                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: vm.isGymWiFiConnected ? const Color(0xFFDCFCE7) : AppTheme.dangerLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  vm.isGymWiFiConnected ? 'Connected' : 'Not Connected',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: vm.isGymWiFiConnected ? const Color(0xFF16A34A) : AppTheme.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      vm.setCurrentConnectedSSID('FitZone_Gym_5G');
                                      vm.updateWiFiSettings('FitZone_Gym_5G', '');
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Registered active WiFi: FitZone_Gym_5G'),
                                          backgroundColor: AppTheme.success,
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: Text(
                                      'Register WiFi',
                                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: OutlinedButton(
                                    onPressed: () => _showManualWifiDialog(context, vm),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppTheme.primary),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: Text(
                                      'Manual Setup',
                                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.primary),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],



                  // ── Section: Static QR ──
                  if (vm.settings?.method == 'Static QR' || vm.settings?.method == 'QR + Biometric') ...[
                    Text(
                      'Static QR Settings',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF0F0F2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Static Token', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                                  const SizedBox(height: 4),
                                  Text(
                                    vm.settings?.staticQrToken.substring(0, 12) ?? 'Not Generated',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Text('Locked', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                                  Switch(
                                    value: vm.settings?.staticQrLocked ?? false,
                                    activeColor: AppTheme.primary,
                                    onChanged: (val) => vm.toggleStaticQrLock(val),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: (vm.settings?.staticQrLocked ?? false)
                                      ? null
                                      : () => vm.generateNewStaticQr(),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppTheme.primary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Text('Regenerate Token', style: GoogleFonts.inter(fontSize: 11.5)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    final token = vm.settings?.staticQrToken ?? '';
                                    if (token.isNotEmpty) {
                                      final url = 'https://api.qrserver.com/v1/create-qr-code/?size=500x500&data=$token';
                                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  child: Text('Download QR', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white)),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Section: Display Management ──
                  Row(
                    children: [
                      Text(
                        'Display Management',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          final link = await vm.getOrGenerateDisplayLink();
                          if (!context.mounted) return;
                          if (link.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to generate display link'), backgroundColor: AppTheme.danger),
                            );
                            return;
                          }
                          Clipboard.setData(ClipboardData(text: link));
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text('Display Link Generated'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Copy this link and open it on your Smart TV or tablet browser:'),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                                    child: Text(link, style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic)),
                                  ),
                                ],
                              ),
                               actions: [
                                TextButton.icon(
                                  onPressed: () {
                                    launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
                                  },
                                  icon: const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.primary),
                                  label: const Text('Open Link', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: link));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Display link copied to clipboard!'), backgroundColor: AppTheme.success),
                                    );
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('Copy Link', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Close', style: TextStyle(color: AppTheme.textMuted)),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_to_queue_rounded, size: 16, color: AppTheme.primary),
                        label: Text('Get Link', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (vm.displaySessions.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9FB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF3F4F6)),
                      ),
                      child: Center(
                        child: Text(
                          'No displays registered yet',
                          style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: vm.displaySessions.map((session) {
                        final isOnline = DateTime.now().difference(session.lastSeen).inSeconds < 45;
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ]
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.tv_rounded, color: AppTheme.primary, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          session.deviceName ?? 'Generic Display',
                                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: isOnline ? Colors.green : Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              isOnline ? 'Online' : 'Offline',
                                              style: GoogleFonts.inter(fontSize: 11, color: isOnline ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '• Public ID: ${session.displayPublicId}',
                                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textMuted),
                                    onSelected: (action) async {
                                      if (action == 'RENAME') {
                                        _showRenameDialog(context, vm, session.id, session.deviceName ?? '');
                                      } else if (action == 'TOGGLE_STATUS') {
                                        await vm.manageDisplayDevice(session.id, 'TOGGLE_STATUS');
                                      } else if (action == 'REVERIFY') {
                                        await vm.manageDisplayDevice(session.id, 'REVERIFY');
                                      } else if (action == 'REMOVE') {
                                        await vm.manageDisplayDevice(session.id, 'REMOVE');
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(value: 'RENAME', child: Text('Rename Display')),
                                      PopupMenuItem(
                                        value: 'TOGGLE_STATUS', 
                                        child: Text(session.isEnabled ? 'Disable Display' : 'Enable Display'),
                                      ),
                                      const PopupMenuItem(value: 'REVERIFY', child: Text('Force Re-verify')),
                                      const PopupMenuItem(value: 'REMOVE', child: Text('Remove Device', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 24, color: Color(0xFFF3F4F6)),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Status', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: session.isVerified
                                              ? const Color(0xFFDCFCE7)
                                              : const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          session.isVerified ? 'Verified' : 'Pending Verification',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            color: session.isVerified ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('Last Seen', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('hh:mm a, dd MMM').format(session.lastSeen.toLocal()),
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),

                  // ── Section: Emergency & Recovery ──
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFFF3F4F6)),
                  const SizedBox(height: 16),
                  Text(
                    'Emergency & Recovery',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use only when QR attendance is unavailable',
                    style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),

                  // Manual Attendance
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const EmergencyAttendanceHubScreen()),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFF0F0F2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.edit_calendar_rounded, color: Color(0xFFD97706), size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Manual Attendance',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mark attendance for members and staff manually',
                                    style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Attendance Correction
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OwnerAttendanceCorrectionScreen()),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFF0F0F2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.edit_note_rounded, color: Color(0xFFDC2626), size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Attendance Correction',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Owner',
                                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.danger),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Correct attendance status, times, and shifts',
                                    style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showManualWifiDialog(BuildContext context, AttendanceViewModel vm) {
    final controller = TextEditingController(text: vm.savedGymWiFiSSID);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Manual WiFi Setup', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Gym WiFi SSID',
            labelStyle: GoogleFonts.inter(fontSize: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              vm.updateWiFiSettings(controller.text, '');
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Registered WiFi: ${controller.text}'), backgroundColor: AppTheme.success),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, AttendanceViewModel vm, String displayId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename Display Device', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Display Name',
            labelStyle: GoogleFonts.inter(fontSize: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              await vm.manageDisplayDevice(displayId, 'RENAME', name: controller.text);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fingerprint_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Biometric & Gate Turnstile',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    Text(
                      _connectedDevicesCount > 0
                          ? 'Fingerprint, Face & RFID • $_connectedDevicesCount Connected'
                          : 'Fingerprint, Face Recognition & RFID Cards',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _biometricEnabled,
                activeColor: AppTheme.primary,
                onChanged: _loadingBiometric ? null : (val) => _toggleBiometric(val),
              ),
            ],
          ),
          if (_biometricEnabled) ...[
            const Divider(height: 24),

            // Connection Mode Tabs (PC Bridge vs Direct Cloud)
            Text(
              'Integration Mode',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _biometricConnectionMode = 'bridge'),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _biometricConnectionMode == 'bridge' ? AppTheme.primaryLight : const Color(0xFFF9F9FB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _biometricConnectionMode == 'bridge' ? AppTheme.primary : const Color(0xFFE5E7EB),
                          width: _biometricConnectionMode == 'bridge' ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.computer_rounded,
                                size: 16,
                                color: _biometricConnectionMode == 'bridge' ? AppTheme.primary : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'PC Sync Bridge',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _biometricConnectionMode == 'bridge' ? AppTheme.primary : AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Offline-Safe • Recommended',
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              color: _biometricConnectionMode == 'bridge' ? AppTheme.primary : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _biometricConnectionMode = 'cloud'),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: _biometricConnectionMode == 'cloud' ? AppTheme.primaryLight : const Color(0xFFF9F9FB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _biometricConnectionMode == 'cloud' ? AppTheme.primary : const Color(0xFFE5E7EB),
                          width: _biometricConnectionMode == 'cloud' ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_upload_rounded,
                                size: 16,
                                color: _biometricConnectionMode == 'cloud' ? AppTheme.primary : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Direct Cloud',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _biometricConnectionMode == 'cloud' ? AppTheme.primary : AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'eSSL ADMS / Realtime Cloud',
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              color: _biometricConnectionMode == 'cloud' ? AppTheme.primary : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Mode Explanation Banner
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _biometricConnectionMode == 'bridge'
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _biometricConnectionMode == 'bridge'
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFBFDBFE),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _biometricConnectionMode == 'bridge'
                        ? Icons.offline_bolt_rounded
                        : Icons.wifi_tethering_rounded,
                    size: 16,
                    color: _biometricConnectionMode == 'bridge' ? const Color(0xFF047857) : const Color(0xFF1D4ED8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _biometricConnectionMode == 'bridge'
                          ? 'PC Bridge Mode: Reception PC par chalta hai. Internet band ya PC power cut hone par bhi SQLite WAL buffer me attendance safe rehti hai aur internet aane par automatic sync hoti hai.'
                          : 'Direct Cloud Mode: Machine directly internet/SIM se judi hoti hai aur Cloud Webhook URL par attendance push karti hai.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _biometricConnectionMode == 'bridge' ? const Color(0xFF047857) : const Color(0xFF1D4ED8),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Device Connection Secret
            Text(
              'Gym Biometric Secret Key',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _showSecret ? _deviceSecret : '••••••••••••••••••••••••••••••••',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: Icon(_showSecret ? Icons.visibility_off : Icons.visibility, size: 18, color: AppTheme.textMuted),
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primary),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _deviceSecret));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Secret Key copied to clipboard!'), behavior: SnackBarBehavior.floating),
                      );
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // If Cloud mode: show Webhook API URL
            if (_biometricConnectionMode == 'cloud') ...[
              Text(
                'Cloud Webhook API URL (Push Endpoint)',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${Env.supabaseUrl}/rest/v1/rpc/process_biometric_punch_batch',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primary),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: '${Env.supabaseUrl}/rest/v1/rpc/process_biometric_punch_batch'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('API URL copied to clipboard!'), behavior: SnackBarBehavior.floating),
                        );
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 2-Way Expiry Sync Badge
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock_rounded, size: 18, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Two-Way Expiry Gate Lock Active',
                          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.purple),
                        ),
                        Text(
                          'App me membership renew ya edit hone par machine me auto validity time update ho jati hai.',
                          style: GoogleFonts.inter(fontSize: 10.5, color: Colors.purple.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Regenerate Secret Key button
            OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Regenerate Secret Key?'),
                    content: const Text(
                      'Existing biometric devices and PC bridge tools will stop connecting until updated with the new key.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _regenerateSecret();
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                        child: const Text('Regenerate', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Regenerate Secret Key', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
