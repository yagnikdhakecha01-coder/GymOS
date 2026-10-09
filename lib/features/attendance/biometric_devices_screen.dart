import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/auth_viewmodel.dart';
import 'attendance_viewmodel.dart';

class BiometricDevicesScreen extends StatefulWidget {
  const BiometricDevicesScreen({super.key});

  @override
  State<BiometricDevicesScreen> createState() => _BiometricDevicesScreenState();
}

class _BiometricDevicesScreenState extends State<BiometricDevicesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _unlinkedPunches = [];
  List<Map<String, dynamic>> _recentPunches = [];
  String _deviceSecret = '';
  int _activeTab = 0; // 0 = Devices, 1 = Live Punches

  static const String _admsEndpoint = 'https://gilxxyvwqucwwwqaxosx.supabase.co/functions/v1/biometric-adms';

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  String _resolveGymId() {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final attVm = Provider.of<AttendanceViewModel>(context, listen: false);
    return authVm.activeAssociation?.gymId ??
        authVm.gymInfo?['id'] ??
        attVm.settings?.gymId ??
        '';
  }

  Future<void> _loadAllData() async {
    final gymId = _resolveGymId();
    if (gymId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);
    try {
      // 1. Fetch devices
      final devRes = await SupabaseService.client.rpc('get_gym_biometric_devices', params: {'p_gym_id': gymId});
      List<Map<String, dynamic>> devices = [];
      if (devRes != null && devRes['devices'] != null) {
        devices = List<Map<String, dynamic>>.from(devRes['devices']);
      }

      // 2. Fetch unlinked punches
      final unlinkedRes = await SupabaseService.client.rpc('get_unlinked_biometric_punches', params: {'p_gym_id': gymId});
      List<Map<String, dynamic>> unlinked = [];
      if (unlinkedRes != null && unlinkedRes['unlinked_punches'] != null) {
        unlinked = List<Map<String, dynamic>>.from(unlinkedRes['unlinked_punches']);
      }

      // 3. Fetch recent punches
      final punchesRes = await SupabaseService.client.rpc('get_recent_biometric_punches', params: {'p_gym_id': gymId, 'p_limit': 25});
      List<Map<String, dynamic>> punches = [];
      if (punchesRes != null && punchesRes['punches'] != null) {
        punches = List<Map<String, dynamic>>.from(punchesRes['punches']);
      }

      // 4. Fetch secret
      final secRes = await SupabaseService.client.rpc('get_or_create_gym_biometric_settings', params: {'p_gym_id': gymId});
      String secret = '';
      if (secRes != null && secRes['secret'] != null) {
        secret = secRes['secret'].toString();
      }

      if (mounted) {
        setState(() {
          _devices = devices;
          _unlinkedPunches = unlinked;
          _recentPunches = punches;
          _deviceSecret = secret;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[BiometricDevicesScreen] Error loading data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncAllMembersToMachine() async {
    final gymId = _resolveGymId();
    if (gymId.isEmpty) return;

    try {
      final res = await SupabaseService.client.rpc('enqueue_full_gym_member_biometric_sync', params: {'p_gym_id': gymId});
      if (mounted) {
        final count = res?['enqueued_count'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✔ $count member expiry & access records pushed to sync queue!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _testDevicePing(String deviceSerial) async {
    if (deviceSerial.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Testing connection with Cloud ADMS...'), duration: Duration(seconds: 1)),
    );

    try {
      final res = await SupabaseService.client.rpc('poll_adms_commands', params: {'p_device_serial': deviceSerial});
      if (mounted) {
        if (res != null && res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🟢 Device Active & Linked Successfully!'),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          _loadAllData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Device response: ${res?['error'] ?? 'No heartbeat yet. Ensure machine Cloud Server is ON.'}'),
              backgroundColor: AppTheme.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection check failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _removeDevice(String deviceId) async {
    final gymId = _resolveGymId();
    if (gymId.isEmpty) return;

    try {
      await SupabaseService.client.rpc('remove_gym_biometric_device', params: {'p_gym_id': gymId, 'p_device_id': deviceId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device unlinked.'), backgroundColor: AppTheme.textPrimary),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _openLinkPinDialog(int pin) async {
    final gymId = _resolveGymId();
    if (gymId.isEmpty) return;

    // Fetch members to choose from
    List<Map<String, dynamic>> members = [];
    try {
      final res = await SupabaseService.client
          .from('members')
          .select('id, name, phone, biometric_pin')
          .eq('gym_id', gymId)
          .order('name');
      members = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Error fetching members: $e');
    }

    if (!mounted) return;

    String? selectedMemberId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Link PIN #$pin to Member',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select which gym member owns this face/biometric user ID on the machine:',
                style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                  color: const Color(0xFFF9F9FB),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedMemberId,
                    hint: Text('Choose Member', style: GoogleFonts.inter(fontSize: 13)),
                    items: members.map((m) {
                      final hasPin = m['biometric_pin'] != null ? ' (PIN: #${m['biometric_pin']})' : '';
                      return DropdownMenuItem<String>(
                        value: m['id'].toString(),
                        child: Text(
                          '${m['name']}$hasPin',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => setDlgState(() => selectedMemberId = val),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: selectedMemberId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final res = await SupabaseService.client.rpc('link_biometric_pin_to_member', params: {
                          'p_gym_id': gymId,
                          'p_member_id': selectedMemberId,
                          'p_pin': pin,
                        });
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(res?['message'] ?? 'Successfully linked!'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                        _loadAllData();
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Failed to link: $e'), backgroundColor: AppTheme.danger),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Link Member'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPairDeviceModal({Map<String, dynamic>? existingDevice}) {
    final gymId = _resolveGymId();
    if (gymId.isEmpty) return;

    final nameCtrl = TextEditingController(text: existingDevice?['device_name'] ?? 'Main Entrance Face Terminal');
    final snCtrl = TextEditingController(text: existingDevice?['device_serial_number'] ?? '');
    final ipCtrl = TextEditingController(text: existingDevice?['ip_address'] ?? '192.168.1.201');
    final portCtrl = TextEditingController(text: (existingDevice?['port'] ?? 4370).toString());

    String selectedBrand = existingDevice?['device_brand'] ?? 'eSSL';
    String selectedCategory = existingDevice?['device_category'] ?? 'face';
    String selectedMode = existingDevice?['connection_mode'] ?? 'cloud_adms';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
                      child: const Icon(Icons.face_retouching_natural_rounded, color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        existingDevice != null ? 'Edit Terminal Settings' : 'Pair New Biometric / Face Machine',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Terminal Name
                Text('Device / Gate Name', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Main Gate Turnstile Face Terminal',
                    filled: true,
                    fillColor: const Color(0xFFF9F9FB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),

                // Brand Selector
                Text('Hardware Brand', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['eSSL', 'ZKTeco', 'Realtime', 'Hikvision', 'Other'].map((b) {
                    final isSel = selectedBrand == b;
                    return ChoiceChip(
                      label: Text(b),
                      selected: isSel,
                      onSelected: (val) {
                        if (val) setModalState(() => selectedBrand = b);
                      },
                      selectedColor: AppTheme.primaryLight,
                      labelStyle: TextStyle(
                        color: isSel ? AppTheme.primary : AppTheme.textPrimary,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Category Selector
                Text('Terminal Type', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    {'key': 'face', 'label': 'Face Recognition 👤'},
                    {'key': 'fingerprint', 'label': 'Fingerprint 👆'},
                    {'key': 'turnstile', 'label': 'Turnstile Gate 🚧'},
                  ].map((cat) {
                    final isSel = selectedCategory == cat['key'];
                    return ChoiceChip(
                      label: Text(cat['label']!),
                      selected: isSel,
                      onSelected: (val) {
                        if (val) setModalState(() => selectedCategory = cat['key']!);
                      },
                      selectedColor: AppTheme.primaryLight,
                      labelStyle: TextStyle(
                        color: isSel ? AppTheme.primary : AppTheme.textPrimary,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Connection Mode
                Text('Connection Method', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setModalState(() => selectedMode = 'cloud_adms'),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selectedMode == 'cloud_adms' ? const Color(0xFFEFF6FF) : const Color(0xFFF9F9FB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedMode == 'cloud_adms' ? const Color(0xFF3B82F6) : AppTheme.border,
                              width: selectedMode == 'cloud_adms' ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.cloud_done_rounded, size: 16, color: selectedMode == 'cloud_adms' ? const Color(0xFF2563EB) : AppTheme.textMuted),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Cloud ADMS',
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: selectedMode == 'cloud_adms' ? const Color(0xFF2563EB) : AppTheme.textPrimary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Zero PC needed • Direct WiFi/SIM', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => setModalState(() => selectedMode = 'lan_bridge'),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selectedMode == 'lan_bridge' ? const Color(0xFFECFDF5) : const Color(0xFFF9F9FB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedMode == 'lan_bridge' ? const Color(0xFF10B981) : AppTheme.border,
                              width: selectedMode == 'lan_bridge' ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.computer_rounded, size: 16, color: selectedMode == 'lan_bridge' ? const Color(0xFF059669) : AppTheme.textMuted),
                                  const SizedBox(width: 6),
                                  Text(
                                    'PC Bridge',
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: selectedMode == 'lan_bridge' ? const Color(0xFF059669) : AppTheme.textPrimary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('LAN Port 4370 • Reception PC', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Fields based on mode
                if (selectedMode == 'cloud_adms') ...[
                  Text('Device Serial Number (SN)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Machine ke peeche sticker par ya Menu > System Info me milega (e.g. CK99812401)', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: snCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. CK99812401',
                      filled: true,
                      fillColor: const Color(0xFFF9F9FB),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Setup Guide Card for Machine Menu
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.settings_suggest_rounded, size: 16, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Text('eSSL Machine Settings (Type on Machine Screen):', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('1. Go to: Menu > Comm. > Cloud Server / ADMS', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text('2. Server Address: $_admsEndpoint', style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 16, color: AppTheme.primary),
                              onPressed: () {
                                Clipboard.setData(const ClipboardData(text: _admsEndpoint));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server Address copied!')));
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        Text('3. Server Port: 443 | Enable Cloud: ON', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Machine Local IP', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: ipCtrl,
                              decoration: InputDecoration(
                                hintText: '192.168.1.201',
                                filled: true,
                                fillColor: const Color(0xFFF9F9FB),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Port', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: portCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: '4370',
                                filled: true,
                                fillColor: const Color(0xFFF9F9FB),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Gym Secret Key for PC Bridge:', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_deviceSecret, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16, color: AppTheme.primary),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _deviceSecret));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Secret copied!')));
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final sn = snCtrl.text.trim();
                      if (selectedMode == 'cloud_adms' && sn.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device Serial Number is required!')));
                        return;
                      }

                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(ctx);
                      try {
                        final res = await SupabaseService.client.rpc('register_gym_biometric_device', params: {
                          'p_gym_id': gymId,
                          'p_device_name': nameCtrl.text.trim(),
                          'p_serial_number': sn.isNotEmpty ? sn : 'LAN_${DateTime.now().millisecondsSinceEpoch}',
                          'p_brand': selectedBrand,
                          'p_category': selectedCategory,
                          'p_mode': selectedMode,
                          'p_ip': ipCtrl.text.trim(),
                          'p_port': int.tryParse(portCtrl.text.trim()) ?? 4370,
                          'p_device_id': existingDevice?['id'],
                        });

                        if (res != null && res['success'] == true) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(res['message'] ?? 'Terminal linked successfully!'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                          _loadAllData();
                        } else {
                          messenger.showSnackBar(
                            SnackBar(content: Text(res?['error'] ?? 'Registration failed'), backgroundColor: AppTheme.danger),
                          );
                        }
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(existingDevice != null ? 'Save Changes' : 'Pair & Connect Terminal', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Biometric & Face Terminals',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary, size: 22),
            onPressed: _loadAllData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _loadAllData,
              color: AppTheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Overview Banner
                    _buildOverviewCard(),
                    const SizedBox(height: 16),

                    // Unlinked Face Discovery Alert (If any exist)
                    if (_unlinkedPunches.isNotEmpty) ...[
                      _buildUnlinkedPunchesCard(),
                      const SizedBox(height: 16),
                    ],

                    // Navigation Tabs (Terminals vs Live Stream)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _activeTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _activeTab == 0 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: _activeTab == 0 ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)] : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'Connected Devices (${_devices.length})',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: _activeTab == 0 ? FontWeight.bold : FontWeight.w500,
                                      color: _activeTab == 0 ? AppTheme.primary : AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _activeTab = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _activeTab == 1 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: _activeTab == 1 ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)] : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'Live Face Activity (${_recentPunches.length})',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: _activeTab == 1 ? FontWeight.bold : FontWeight.w500,
                                      color: _activeTab == 1 ? AppTheme.primary : AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_activeTab == 0) _buildDevicesTab() else _buildLivePunchesTab(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildOverviewCard() {
    final onlineCount = _devices.where((d) => d['status'] == 'online').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C3AED), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C3AED).withValues(alpha: 0.25),
            blurRadius: 12,
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
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.security_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Hardware Gatekeeper Active',
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Offline-First • Zero Cloud Latency At Door',
                      style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showPairDeviceModal(),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, size: 15, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 3),
                        Text(
                          'Pair Device',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricItem('Total Machines', '${_devices.length}'),
              Container(width: 1, height: 28, color: Colors.white24),
              _metricItem('Online Now', '$onlineCount', highlight: onlineCount > 0),
              Container(width: 1, height: 28, color: Colors.white24),
              InkWell(
                onTap: _syncAllMembersToMachine,
                child: Column(
                  children: [
                    const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                    const SizedBox(height: 2),
                    Text('Sync Members', style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricItem(String label, String value, {bool highlight = false}) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: highlight ? const Color(0xFF86EFAC) : Colors.white,
          ),
        ),
        Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white70)),
      ],
    );
  }

  Widget _buildUnlinkedPunchesCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Unlinked Faces Detected (${_unlinkedPunches.length})',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF92400E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Faces punched on the machine that are not yet mapped to a GymOS member. Tap to map in 1 click:',
            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFB45309)),
          ),
          const SizedBox(height: 10),
          ..._unlinkedPunches.map((up) {
            final pin = up['biometric_pin'] as int;
            final count = up['punch_count'] ?? 1;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.face_unlock_rounded, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('User PIN #$pin • $count punches', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  OutlinedButton(
                    onPressed: () => _openLinkPinDialog(pin),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                      side: const BorderSide(color: AppTheme.primary),
                    ),
                    child: const Text('Link Member', style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDevicesTab() {
    if (_devices.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            const Icon(Icons.devices_other_rounded, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text('No Terminals Paired Yet', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Pair your eSSL, ZKTeco, or Realtime Face machine to enable automated gate access and offline validity enforcement.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _showPairDeviceModal(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Pair eSSL Face Terminal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _devices.map((dev) {
        final isOnline = dev['status'] == 'online';
        final brand = dev['device_brand'] ?? 'eSSL';
        final sn = dev['device_serial_number'] ?? 'N/A';
        final totalPunches = dev['total_punches_synced'] ?? 0;
        final mode = dev['connection_mode'] == 'cloud_adms' ? 'Cloud ADMS' : 'PC Bridge';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      dev['device_category'] == 'fingerprint'
                          ? Icons.fingerprint_rounded
                          : Icons.face_retouching_natural_rounded,
                      color: isOnline ? const Color(0xFF16A34A) : AppTheme.textMuted,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dev['device_name'] ?? 'Face Terminal',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(4)),
                              child: Text(brand, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: dev['connection_mode'] == 'cloud_adms' ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                mode,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: dev['connection_mode'] == 'cloud_adms' ? const Color(0xFF2563EB) : const Color(0xFF059669),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textMuted),
                    onSelected: (act) {
                      if (act == 'PING') _testDevicePing(sn);
                      if (act == 'SYNC') _syncAllMembersToMachine();
                      if (act == 'EDIT') _showPairDeviceModal(existingDevice: dev);
                      if (act == 'DELETE') _removeDevice(dev['id'].toString());
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'PING', child: Text('Test Ping / Refresh')),
                      const PopupMenuItem(value: 'SYNC', child: Text('Sync Members to Terminal')),
                      const PopupMenuItem(value: 'EDIT', child: Text('Edit Settings')),
                      const PopupMenuItem(value: 'DELETE', child: Text('Remove Terminal', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFF3F4F6)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF16A34A) : Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline ? 'Online (Active)' : 'Offline',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isOnline ? const Color(0xFF16A34A) : Colors.red),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('SN: $sn', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted)),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: sn));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Serial number copied!')));
                        },
                        child: const Icon(Icons.copy_rounded, size: 12, color: AppTheme.primary),
                      ),
                    ],
                  ),
                  Text('Punches: $totalPunches', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLivePunchesTab() {
    if (_recentPunches.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('No attendance punches recorded yet.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
        ),
      );
    }

    return Column(
      children: _recentPunches.map((p) {
        final timeStr = p['punch_time'] ?? '';
        String formattedTime = timeStr;
        try {
          final dt = DateTime.parse(timeStr).toLocal();
          formattedTime = DateFormat('dd MMM • hh:mm a').format(dt);
        } catch (_) {}

        final name = p['member_name'] ?? 'Member';
        final pin = p['biometric_pin'] ?? '';
        final status = p['processed_status'] ?? 'SUCCESS';
        final isDenied = status == 'EXPIRED_ATTENDANCE';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDenied ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDenied ? Icons.lock_rounded : Icons.face_rounded,
                  size: 16,
                  color: isDenied ? Colors.red : const Color(0xFF16A34A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    Text('PIN #$pin • $formattedTime', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDenied ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isDenied ? 'Gate Locked' : 'Face Verified',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDenied ? Colors.red : const Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
