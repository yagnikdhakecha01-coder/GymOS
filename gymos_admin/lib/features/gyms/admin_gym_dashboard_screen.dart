import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/google_drive_service.dart';
import '../../core/widgets/full_screen_image_viewer.dart';

class AdminGymDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> gym;

  const AdminGymDashboardScreen({super.key, required this.gym});

  @override
  State<AdminGymDashboardScreen> createState() => _AdminGymDashboardScreenState();
}

class _AdminGymDashboardScreenState extends State<AdminGymDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loadingFinance = true;
  bool _loadingMembers = true;
  bool _loadingStaff = true;
  bool _loadingUnlinked = true;
  bool _loadingDiagnostics = true;

  double _totalRevenue = 0.0;
  double _totalExpense = 0.0;
  double _totalPending = 0.0;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _unlinkedEntries = [];
  List<Map<String, dynamic>> _diagnostics = [];
  List<Map<String, dynamic>> _gymPlans = [];

  String _memberSearch = '';
  String _staffSearch = '';
  String _unlinkedSearch = '';
  String _deletedMemberSearch = '';

  List<Map<String, dynamic>> _deletedMembers = [];
  bool _loadingDeletedMembers = false;
  bool _showDeletedMembersView = false;

  // Quick Action States
  late bool _isLocked;
  late String _gymStatus;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _isLocked = widget.gym['is_locked'] == true;
    _gymStatus = widget.gym['status']?.toString() ?? 'Active';
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadFinanceData(),
      _loadMembersData(),
      _loadStaffData(),
      _loadDeletedMembersData(),
    ]);
    if (mounted) {
      await Future.wait([
        _loadUnlinkedEntries(),
        _loadDiagnosticsData(),
      ]);
    }
  }

  Future<void> _loadFinanceData() async {
    if (!AdminSupabaseService.isInitialized) {
      if (mounted) {
        setState(() {
          _totalRevenue = 450000.00;
          _totalExpense = 120000.00;
          _transactions = [
            {'id': 'dummy-1', 'type': 'Revenue', 'category': 'Membership', 'amount': 1500.00, 'transaction_date': DateTime.now().toIso8601String(), 'notes': 'Monthly fee'},
            {'id': 'dummy-2', 'type': 'Expense', 'category': 'Rent', 'amount': 35000.00, 'transaction_date': DateTime.now().toIso8601String(), 'notes': 'Monthly Rent'},
          ];
          _loadingFinance = false;
        });
      }
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final response = await client
          .from('finance_transactions')
          .select()
          .eq('gym_id', widget.gym['id'])
          .order('transaction_date', ascending: false);

      double rev = 0.0;
      double exp = 0.0;
      final txList = List<Map<String, dynamic>>.from(response);

      for (var tx in txList) {
        final txDate = tx['transaction_date'] != null ? DateTime.tryParse(tx['transaction_date']) : null;
        if (txDate != null && txDate.month == _selectedMonth && txDate.year == _selectedYear) {
          final amt = double.tryParse(tx['amount'].toString()) ?? 0.0;
          if (tx['type'] == 'Revenue') {
            rev += amt;
          } else if (tx['type'] == 'Expense') {
            exp += amt;
          }
        }
      }

      // Fetch pending balances of members
      double pendingSum = 0.0;
      try {
        final membersRes = await client
            .from('members')
            .select('pending_amount')
            .eq('gym_id', widget.gym['id']);
        for (var m in (membersRes as List)) {
          pendingSum += double.tryParse(m['pending_amount']?.toString() ?? '0') ?? 0.0;
        }
      } catch (err) {
        debugPrint('Error fetching pending dues: $err');
      }

      if (mounted) {
        setState(() {
          _totalRevenue = rev;
          _totalExpense = exp;
          _totalPending = pendingSum;
          _transactions = txList;
          _loadingFinance = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading finance data: $e');
      if (mounted) setState(() => _loadingFinance = false);
    }
  }

  Future<void> _loadMembersData() async {
    if (!AdminSupabaseService.isInitialized) {
      if (mounted) {
        setState(() {
          _members = [
            {
              'id': 'dummy-m-1',
              'full_name': 'Rahul Sharma',
              'email': 'rahul@gmail.com',
              'phone': '9876543210',
              'membership_name': 'Gold Plan',
              'status': 'Active',
              'payment_status': 'Paid',
              'total_received_amount': 12000.0,
              'pending_amount': 0.0,
            },
          ];
          _loadingMembers = false;
        });
      }
      return;
    }

    try {
      final client = AdminSupabaseService.client;

      // 1. Fetch membership plans to map ID -> Title
      final Map<String, String> planMap = {};
      try {
        final plansRes = await client
            .from('membership_plans')
            .select('id, title, price, duration_months')
            .eq('gym_id', widget.gym['id']);
        for (var p in plansRes) {
          if (p['id'] != null && p['title'] != null) {
            planMap[p['id'].toString()] = p['title'].toString();
          }
        }
        _gymPlans = List<Map<String, dynamic>>.from(plansRes);
      } catch (pe) {
        debugPrint('Error loading plans for mapping: $pe');
      }

      // 2. Fetch members directly
      final response = await client
          .from('members')
          .select('*')
          .eq('gym_id', widget.gym['id'])
          .order('created_at', ascending: false);

      final membersList = List<Map<String, dynamic>>.from(response);

      if (mounted) {
        setState(() {
          _members = membersList.map((m) {
            final name = (m['name'] != null && m['name'].toString().trim().isNotEmpty)
                ? m['name'].toString().trim()
                : (m['full_name'] != null && m['full_name'].toString().trim().isNotEmpty
                    ? m['full_name'].toString().trim()
                    : 'Unnamed Member');

            final planId = m['membership_plan_id']?.toString();
            final planTitle = planId != null && planMap.containsKey(planId)
                ? planMap[planId]!
                : (m['membership_name']?.toString() ?? 'No Plan');

            return {
              'id': m['id']?.toString() ?? '',
              'full_name': name,
              'email': m['email'] != null && m['email'].toString().trim().isNotEmpty ? m['email'].toString() : '-',
              'phone': m['phone'] != null && m['phone'].toString().trim().isNotEmpty ? m['phone'].toString() : (m['phone_number']?.toString() ?? '-'),
              'membership_name': planTitle,
              'membership_plan_id': planId,
              'status': m['status']?.toString() ?? 'Active',
              'payment_status': m['payment_status']?.toString() ?? 'Pending',
              'avatar_url': m['avatar'] ?? m['avatar_url'] ?? m['photo_url'],
              'total_received_amount': double.tryParse(m['total_received_amount']?.toString() ?? '0') ?? 0.0,
              'pending_amount': double.tryParse(m['pending_amount']?.toString() ?? '0') ?? 0.0,
              'discount_amount': double.tryParse(m['discount_amount']?.toString() ?? '0') ?? 0.0,
              'join_date': m['join_date']?.toString() ?? '-',
              'gender': m['gender']?.toString() ?? '-',
              'dob': m['dob']?.toString() ?? '-',
              'notes': m['notes']?.toString() ?? '',
              'medical_details': m['medical_details']?.toString() ?? '',
              'created_at': m['created_at'],
              'raw': m,
            };
          }).toList();
          _loadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading members: $e');
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _loadDeletedMembersData() async {
    if (!AdminSupabaseService.isInitialized) return;
    try {
      if (mounted) setState(() => _loadingDeletedMembers = true);
      final client = AdminSupabaseService.client;
      final response = await client
          .from('deleted_members')
          .select('*')
          .eq('gym_id', widget.gym['id'])
          .order('deleted_at', ascending: false);

      if (mounted) {
        setState(() {
          _deletedMembers = List<Map<String, dynamic>>.from(response);
          _loadingDeletedMembers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading deleted members: $e');
      if (mounted) setState(() => _loadingDeletedMembers = false);
    }
  }

  Future<void> _loadStaffData() async {
    if (!AdminSupabaseService.isInitialized) {
      if (mounted) {
        setState(() {
          _staff = [
            {'id': 'dummy-s-1', 'full_name': 'Vikram Rathore', 'email': 'vikram@fitzone.com', 'phone': '9876543220', 'role': 'Manager', 'salary': 35000.00, 'salary_due': 0.0, 'status': 'Active'},
          ];
          _loadingStaff = false;
        });
      }
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final response = await client
          .from('staff')
          .select('*')
          .eq('gym_id', widget.gym['id'])
          .order('created_at', ascending: false);

      final staffList = List<Map<String, dynamic>>.from(response);
      if (mounted) {
        setState(() {
          _staff = staffList.map((s) {
            final name = (s['name'] != null && s['name'].toString().trim().isNotEmpty)
                ? s['name'].toString().trim()
                : (s['full_name'] != null && s['full_name'].toString().trim().isNotEmpty
                    ? s['full_name'].toString().trim()
                    : 'Unnamed Staff');

            return {
              'id': s['id']?.toString() ?? '',
              'full_name': name,
              'email': s['email'] != null && s['email'].toString().trim().isNotEmpty ? s['email'].toString() : '-',
              'phone': s['phone'] != null && s['phone'].toString().trim().isNotEmpty ? s['phone'].toString() : (s['phone_number']?.toString() ?? '-'),
              'role': s['role']?.toString() ?? 'Staff',
              'department': s['department']?.toString() ?? 'General',
              'status': s['status']?.toString() ?? 'Active',
              'salary': double.tryParse(s['salary']?.toString() ?? '0') ?? 0.0,
              'salary_due': double.tryParse(s['salary_due']?.toString() ?? '0') ?? 0.0,
              'avatar_url': s['avatar'] ?? s['avatar_url'],
              'shift': s['shift']?.toString() ?? '-',
              'join_date': s['join_date']?.toString() ?? '-',
              'raw': s,
            };
          }).toList();
          _loadingStaff = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading staff: $e');
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  Future<void> _loadUnlinkedEntries() async {
    if (!AdminSupabaseService.isInitialized) {
      if (mounted) setState(() => _loadingUnlinked = false);
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final currentMemberIds = _members.map((m) => m['id'].toString()).toSet();

      final res = await client
          .from('finance_transactions')
          .select('*')
          .eq('gym_id', widget.gym['id'])
          .eq('category', 'Membership')
          .order('transaction_date', ascending: false);

      final unlinked = <Map<String, dynamic>>[];
      for (var tx in res) {
        final refId = tx['reference_id']?.toString();
        if (refId == null || refId.trim().isEmpty || !currentMemberIds.contains(refId)) {
          unlinked.add(Map<String, dynamic>.from(tx));
        }
      }

      if (mounted) {
        setState(() {
          _unlinkedEntries = unlinked;
          _loadingUnlinked = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading unlinked entries: $e');
      if (mounted) setState(() => _loadingUnlinked = false);
    }
  }

  Future<void> _loadDiagnosticsData() async {
    if (!AdminSupabaseService.isInitialized) {
      if (mounted) setState(() => _loadingDiagnostics = false);
      return;
    }
    try {
      final client = AdminSupabaseService.client;
      final res = await client.rpc('admin_diagnose_gym_health', params: {'p_gym_id': widget.gym['id']});
      if (mounted) {
        setState(() {
          _diagnostics = List<Map<String, dynamic>>.from(res ?? []);
          _loadingDiagnostics = false;
        });
      }
    } catch (e) {
      debugPrint('Error running diagnostics: $e');
      if (mounted) setState(() => _loadingDiagnostics = false);
    }
  }

  Future<void> _runAutoRepair(String actionType, String targetId) async {
    try {
      final client = AdminSupabaseService.client;
      final res = await client.rpc('admin_auto_repair_anomaly', params: {
        'p_gym_id': widget.gym['id'],
        'p_action_type': actionType,
        'p_target_id': targetId,
      });
      final data = res as Map<String, dynamic>? ?? {};
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message']?.toString() ?? 'Repair action executed'),
            backgroundColor: data['success'] == true ? AdminTheme.success : AdminTheme.danger,
          ),
        );
        _loadDiagnosticsData();
        _loadMembersData();
        _loadFinanceData();
        _loadUnlinkedEntries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error repairing anomaly: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  // --- QUICK ACTIONS ---
  Future<void> _toggleLock() async {
    final nextState = !_isLocked;
    try {
      if (AdminSupabaseService.isInitialized) {
        await AdminSupabaseService.client
            .from('gyms')
            .update({'is_locked': nextState})
            .eq('id', widget.gym['id']);
      }
      if (mounted) {
        setState(() => _isLocked = nextState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextState ? '🔒 Gym has been LOCKED' : '🔓 Gym has been UNLOCKED'),
            backgroundColor: nextState ? Colors.orange : AdminTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating lock state: $e'), backgroundColor: AdminTheme.danger));
      }
    }
  }

  Future<void> _toggleSuspend() async {
    final nextStatus = _gymStatus == 'Active' ? 'Suspended' : 'Active';
    try {
      if (AdminSupabaseService.isInitialized) {
        await AdminSupabaseService.client
            .from('gyms')
            .update({'status': nextStatus})
            .eq('id', widget.gym['id']);
      }
      if (mounted) {
        setState(() => _gymStatus = nextStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextStatus == 'Suspended' ? '⏸️ Gym Suspended' : '✅ Gym Activated'),
            backgroundColor: nextStatus == 'Suspended' ? AdminTheme.danger : AdminTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating status: $e'), backgroundColor: AdminTheme.danger));
      }
    }
  }

  Future<void> _exportBackup() async {
    final gymName = widget.gym['name']?.toString() ?? 'Gym';
    final gymId = widget.gym['id'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text('Creating backup for $gymName...', style: GoogleFonts.inter(fontSize: 13)),
          ],
        ),
      ),
    );

    try {
      final client = AdminSupabaseService.client;
      final result = await client.rpc('export_single_gym_backup', params: {'p_gym_id': gymId});
      final data = result as Map<String, dynamic>? ?? {};

      if (data['success'] != true) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup failed: ${data['message'] ?? 'Unknown error'}'), backgroundColor: AdminTheme.danger),
          );
        }
        return;
      }

      final backupId = data['backup_id'];
      final backupJson = jsonEncode(data['backup_json']);
      final ownerMobile = data['owner_mobile']?.toString() ?? '';
      final cleanName = gymName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      final cleanMobile = ownerMobile.replaceAll(RegExp(r'[^\d]+'), '');
      final fileName = 'gym_backup_${cleanName}_${cleanMobile}_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';

      // 1. Trigger browser file download
      final bytes = utf8.encode(backupJson);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);

      // 2. Upload to Google Drive if connected
      String? driveUrl;
      if (GoogleDriveService.isConnected && backupId != null) {
        try {
          final uploadRes = await GoogleDriveService.uploadBackup(backupJson: backupJson, fileName: fileName);
          if (uploadRes.success && uploadRes.driveUrl != null) {
            driveUrl = uploadRes.driveUrl;
            await client.from('database_backups').update({'drive_url': driveUrl}).eq('id', backupId);
          }
        } catch (e) {
          debugPrint('Drive upload error: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AdminTheme.success),
                SizedBox(width: 8),
                Text('Backup Exported!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('File: $fileName', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('✅ Downloaded to your computer.'),
                if (driveUrl != null) ...[
                  const SizedBox(height: 4),
                  const Text('☁️ Uploaded to Google Drive.'),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e'), backgroundColor: AdminTheme.danger));
      }
    }
  }

  Future<void> _deleteGymWithAutoBackup() async {
    final gymName = widget.gym['name']?.toString() ?? 'Gym';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Delete Gym & Cascade Wipe?'),
        content: Text(
          'This will:\n'
          '1. 📦 Auto-backup ALL data of "$gymName" (20+ tables)\n'
          '2. ☁️ Upload backup to Google Drive\n'
          '3. 🗑️ Delete ALL gym data from database\n'
          '4. 🔒 Logout all members, staff & owner\n\n'
          'The backup can be restored anytime from Google Drive via Database → Upload & Restore → Select from Drive.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Auto-Backup & Wipe Gym'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text('Backing up $gymName before deletion...', style: GoogleFonts.inter(fontSize: 13)),
          ],
        ),
      ),
    );

    try {
      final client = AdminSupabaseService.client;
      final gymId = widget.gym['id'];

      final result = await client.rpc('export_single_gym_backup', params: {'p_gym_id': gymId});
      final data = result as Map<String, dynamic>? ?? {};

      if (data['success'] != true) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup failed: ${data['message'] ?? 'Unknown error'}'), backgroundColor: AdminTheme.danger),
          );
        }
        return;
      }

      final backupId = data['backup_id'];
      final backupJson = jsonEncode(data['backup_json']);
      final ownerMobile = data['owner_mobile']?.toString() ?? '';

      String? driveUrl;
      if (GoogleDriveService.isConnected && backupId != null) {
        try {
          final cleanName = gymName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
          final cleanMobile = ownerMobile.replaceAll(RegExp(r'[^\d]+'), '');
          final fileName = 'gym_backup_${cleanName}_${cleanMobile}_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';
          final uploadRes = await GoogleDriveService.uploadBackup(backupJson: backupJson, fileName: fileName);
          if (uploadRes.success && uploadRes.driveUrl != null) {
            driveUrl = uploadRes.driveUrl;
            await client.from('database_backups').update({'drive_url': driveUrl}).eq('id', backupId);
          }
        } catch (e) {
          debugPrint('Drive upload during delete: $e');
        }
      }

      await client.rpc('delete_gym_cascade', params: {'p_gym_id': gymId});

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);

        String msg = '✅ "$gymName" backed up & completely wiped!';
        if (driveUrl != null) {
          msg += ' ☁️ Saved to Google Drive.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AdminTheme.success, duration: const Duration(seconds: 5)),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete error: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  // --- UNLINKED ENTRY DELETION ---
  Future<void> _deleteUnlinkedEntry(Map<String, dynamic> entry) async {
    final txId = entry['id'];
    final refId = entry['reference_id']?.toString();
    final amt = entry['amount']?.toString() ?? '0';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AdminTheme.danger),
            SizedBox(width: 8),
            Text('Delete Unlinked Entry Everywhere?'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete this unlinked transaction of ₹$amt?\n\n'
          'Reference ID: ${refId ?? 'None'}\n\n'
          'This will wipe this record from finance_transactions and purge any lingering orphaned records from attendance, memberships, and payment history.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Everywhere'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final client = AdminSupabaseService.client;
      await client.rpc('admin_delete_unlinked_entry', params: {
        'p_tx_id': txId,
        'p_gym_id': widget.gym['id'],
        'p_ref_id': refId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Unlinked entry deleted everywhere successfully.'),
            backgroundColor: AdminTheme.success,
          ),
        );
        _loadFinanceData();
        _loadUnlinkedEntries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete entry: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  // --- SUB-DIALOG: MARK / UPDATE ATTENDANCE (MEMBER OR STAFF) ---
  Future<void> _showUpsertAttendanceDialog(
    BuildContext parentContext,
    Map<String, dynamic> target, {
    required bool isStaff,
    Map<String, dynamic>? existingLog,
    required VoidCallback onSaved,
  }) async {
    final isEdit = existingLog != null;
    String selectedDate = existingLog?['date']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    String selectedStatus = existingLog?['status']?.toString() ?? 'Present';

    TimeOfDay? checkInTime;
    TimeOfDay? checkOutTime;
    if (existingLog?['check_in'] != null) {
      final dt = DateTime.tryParse(existingLog!['check_in'].toString())?.toLocal();
      if (dt != null) checkInTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    } else {
      checkInTime = const TimeOfDay(hour: 7, minute: 0);
    }

    if (existingLog?['check_out'] != null) {
      final dt = DateTime.tryParse(existingLog!['check_out'].toString())?.toLocal();
      if (dt != null) checkOutTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }

    await showDialog(
      context: parentContext,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AdminTheme.cardColor(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusLg)),
              title: Row(
                children: [
                  Icon(isEdit ? Icons.edit_calendar_rounded : Icons.add_circle_outline_rounded, color: AdminTheme.primary),
                  const SizedBox(width: 8),
                  Text(isEdit ? 'Edit Attendance Entry' : 'Mark Attendance (${isStaff ? 'Staff' : 'Member'})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AdminTheme.surfaceColor(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AdminTheme.borderColor(context)),
                        ),
                        child: Row(
                          children: [
                            Icon(isStaff ? Icons.badge_rounded : Icons.person_rounded, color: AdminTheme.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${target['full_name'] ?? target['name'] ?? 'User'} • ${isStaff ? (target['role'] ?? 'Staff') : 'Gym Member'}',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AdminTheme.textColor(context)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today_rounded, color: AdminTheme.primary),
                        title: const Text('Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        subtitle: Text(selectedDate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.surfaceColor(context), foregroundColor: AdminTheme.textColor(context)),
                          child: const Text('Select Date'),
                          onPressed: () async {
                            final initial = DateTime.tryParse(selectedDate) ?? DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedDate = DateFormat('yyyy-MM-dd').format(picked);
                              });
                            }
                          },
                        ),
                      ),
                      const Divider(),
                      DropdownButtonFormField<String>(
                        initialValue: ['Present', 'Absent', 'Late', 'Half Day', 'Holiday', 'Approved Leave'].contains(selectedStatus) ? selectedStatus : 'Present',
                        items: ['Present', 'Absent', 'Late', 'Half Day', 'Holiday', 'Approved Leave'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedStatus = val);
                        },
                        decoration: const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.check_circle_outline_rounded)),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Check In', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              subtitle: Text(checkInTime != null ? checkInTime!.format(context) : 'Not Set', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: checkInTime != null ? AdminTheme.success : Colors.grey)),
                              trailing: IconButton(
                                icon: const Icon(Icons.access_time_rounded, size: 20),
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: checkInTime ?? const TimeOfDay(hour: 7, minute: 0),
                                  );
                                  if (picked != null) setDialogState(() => checkInTime = picked);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Check Out', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              subtitle: Text(checkOutTime != null ? checkOutTime!.format(context) : 'Not Set', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: checkOutTime != null ? AdminTheme.primary : Colors.grey)),
                              trailing: IconButton(
                                icon: const Icon(Icons.access_time_filled_rounded, size: 20),
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: checkOutTime ?? const TimeOfDay(hour: 8, minute: 30),
                                  );
                                  if (picked != null) setDialogState(() => checkOutTime = picked);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
                  onPressed: () async {
                    Navigator.pop(dialogCtx);
                    try {
                      final client = AdminSupabaseService.client;
                      final baseDt = DateTime.tryParse(selectedDate) ?? DateTime.now();

                      String? checkInIso;
                      if (checkInTime != null) {
                        final inDt = DateTime(baseDt.year, baseDt.month, baseDt.day, checkInTime!.hour, checkInTime!.minute);
                        checkInIso = inDt.toUtc().toIso8601String();
                      }

                      String? checkOutIso;
                      if (checkOutTime != null) {
                        final outDt = DateTime(baseDt.year, baseDt.month, baseDt.day, checkOutTime!.hour, checkOutTime!.minute);
                        checkOutIso = outDt.toUtc().toIso8601String();
                      }

                      final res = await client.rpc('admin_upsert_attendance', params: {
                        'p_gym_id': widget.gym['id'],
                        'p_user_type': isStaff ? 'Staff' : 'Member',
                        'p_target_id': target['id'],
                        'p_date': selectedDate,
                        'p_status': selectedStatus,
                        'p_check_in': checkInIso,
                        'p_check_out': checkOutIso,
                        'p_log_id': existingLog?['id'],
                      });

                      final data = res as Map<String, dynamic>? ?? {};
                      if (mounted) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: Text(data['success'] == true ? '✅ Attendance record saved for $selectedDate' : 'Failed: ${data['error']}'),
                            backgroundColor: data['success'] == true ? AdminTheme.success : AdminTheme.danger,
                          ),
                        );
                        onSaved();
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(content: Text('Error saving attendance: $e'), backgroundColor: AdminTheme.danger),
                        );
                      }
                    }
                  },
                  child: const Text('Save Attendance'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- STAFF DETAILS & ATTENDANCE DIALOG ---
  void _showStaffDetailsDialog(Map<String, dynamic> s) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setStaffModalState) {
            return Dialog(
              backgroundColor: AdminTheme.cardColor(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusLg)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850, maxHeight: 850),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AdminTheme.radiusLg)),
                        border: Border(bottom: BorderSide(color: AdminTheme.borderColor(context))),
                      ),
                      child: Row(
                        children: [
                          InteractiveAvatarWrapper(
                            imageUrl: s['avatar_url']?.toString(),
                            title: s['full_name']?.toString() ?? 'Staff Member',
                            subtitle: 'Staff Console • Role: ${s['role'] ?? 'Staff'}',
                            radius: 26,
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.indigo.withValues(alpha: 0.15),
                              backgroundImage: (s['avatar_url'] != null && s['avatar_url'].toString().isNotEmpty) ? NetworkImage(s['avatar_url']) : null,
                              child: (s['avatar_url'] == null || s['avatar_url'].toString().isEmpty)
                                  ? Text(s['full_name'] != null && s['full_name'].toString().isNotEmpty ? s['full_name'][0].toUpperCase() : '?', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo))
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(s['full_name'] ?? 'Staff', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                                    const SizedBox(width: 8),
                                    _statusChip(s['status'] ?? 'Active'),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Staff Console • Role: ${s['role']} • ID: ${s['id']}',
                                  style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(dialogCtx)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: DefaultTabController(
                        length: 3,
                        child: Column(
                          children: [
                            TabBar(
                              labelColor: Colors.indigo,
                              unselectedLabelColor: AdminTheme.secondaryTextColor(context),
                              indicatorColor: Colors.indigo,
                              tabs: const [
                                Tab(icon: Icon(Icons.badge_rounded, size: 18), text: 'Staff Profile'),
                                Tab(icon: Icon(Icons.payments_rounded, size: 18), text: 'Salary & Payments History'),
                                Tab(icon: Icon(Icons.event_available_rounded, size: 18), text: 'Staff Attendance Manager'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _StaffInfoEditor(
                                    staff: s,
                                    onSaved: () {
                                      setStaffModalState(() {});
                                      _loadStaffData();
                                    },
                                  ),
                                  _StaffSalaryManager(
                                    gymId: widget.gym['id'],
                                    staff: s,
                                    onUpdated: () {
                                      setStaffModalState(() {});
                                      _loadStaffData();
                                      _loadFinanceData();
                                    },
                                  ),
                                  _UserAttendanceManager(
                                    gymId: widget.gym['id'],
                                    target: s,
                                    isStaff: true,
                                    onUpsertRequested: (existingLog, reload) {
                                      _showUpsertAttendanceDialog(
                                        context,
                                        s,
                                        isStaff: true,
                                        existingLog: existingLog,
                                        onSaved: reload,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- OWNER LEVEL MEMBER DIALOG WITH MASTER CONTROLS ---
  void _showMemberDetailsDialog(Map<String, dynamic> m) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
            final name = m['full_name']?.toString() ?? 'Member';
            final phone = m['phone']?.toString() ?? '-';
            final email = m['email']?.toString() ?? '-';
            final status = m['status']?.toString() ?? 'Active';
            final payStatus = m['payment_status']?.toString() ?? 'Pending';
            final planName = m['membership_name']?.toString() ?? 'No Plan';
            final totalRec = double.tryParse(m['total_received_amount']?.toString() ?? '0') ?? 0.0;
            final pendingAmt = double.tryParse(m['pending_amount']?.toString() ?? '0') ?? 0.0;
            final discountAmt = double.tryParse(m['discount_amount']?.toString() ?? '0') ?? 0.0;
            final joinDate = m['join_date']?.toString() ?? '-';
            final gender = m['gender']?.toString() ?? '-';
            final dob = m['dob']?.toString() ?? '-';
            final notes = m['notes']?.toString() ?? '';
            final medical = m['medical_details']?.toString() ?? '';
            final avatarUrl = m['avatar_url']?.toString();

            return Dialog(
              backgroundColor: AdminTheme.cardColor(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusLg)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920, maxHeight: 920),
                child: Column(
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                      decoration: BoxDecoration(
                        color: AdminTheme.primary.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AdminTheme.radiusLg)),
                        border: Border(bottom: BorderSide(color: AdminTheme.borderColor(context))),
                      ),
                      child: Row(
                        children: [
                          InteractiveAvatarWrapper(
                            imageUrl: avatarUrl,
                            title: name,
                            subtitle: 'Member Profile Photo • ID: ${m['id']}',
                            radius: 26,
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: AdminTheme.primary.withValues(alpha: 0.15),
                              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AdminTheme.primary))
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                                    const SizedBox(width: 8),
                                    _statusChip(status),
                                    const SizedBox(width: 6),
                                    _paymentBadge(payStatus),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Super Admin Master Console • ID: ${m['id']}',
                                  style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Body with 5 Master Tabs
                    Expanded(
                      child: DefaultTabController(
                        length: 5,
                        child: Column(
                          children: [
                            TabBar(
                              isScrollable: true,
                              labelColor: AdminTheme.primary,
                              unselectedLabelColor: AdminTheme.secondaryTextColor(context),
                              indicatorColor: AdminTheme.primary,
                              tabs: const [
                                Tab(icon: Icon(Icons.person_outline_rounded, size: 18), text: 'Profile & Overview'),
                                Tab(icon: Icon(Icons.military_tech_rounded, size: 18), text: 'Level & Badges'),
                                Tab(icon: Icon(Icons.event_available_rounded, size: 18), text: 'Attendance Manager'),
                                Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Membership & Financials'),
                                Tab(icon: Icon(Icons.admin_panel_settings_outlined, size: 18), text: 'Owner Actions'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  // Tab 1: Profile & Plan
                                  SingleChildScrollView(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(child: _miniInfoCard(context, 'Assigned Plan', planName, Icons.card_membership_rounded, Colors.indigo)),
                                            const SizedBox(width: 12),
                                            Expanded(child: _miniInfoCard(context, 'Total Received', currencyFormat.format(totalRec), Icons.payments_rounded, AdminTheme.success)),
                                            const SizedBox(width: 12),
                                            Expanded(child: _miniInfoCard(context, 'Pending Balance', currencyFormat.format(pendingAmt), Icons.pending_actions_rounded, pendingAmt > 0 ? AdminTheme.danger : Colors.grey)),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        _sectionCard(
                                          context,
                                          title: 'Personal & Contact Information',
                                          icon: Icons.contact_phone_outlined,
                                          children: [
                                            _detailRow(context, 'Mobile Phone', phone, canCopy: true),
                                            _detailRow(context, 'Email Address', email, canCopy: true),
                                            _detailRow(context, 'Gender', gender),
                                            _detailRow(context, 'Date of Birth', dob),
                                            _detailRow(context, 'Joining Date', joinDate),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        _sectionCard(
                                          context,
                                          title: 'Financial & Membership Accounting',
                                          icon: Icons.account_balance_outlined,
                                          children: [
                                            _detailRow(context, 'Membership Plan', planName),
                                            _detailRow(context, 'Total Received', currencyFormat.format(totalRec)),
                                            _detailRow(context, 'Pending Balance', currencyFormat.format(pendingAmt), isNegative: pendingAmt > 0),
                                            _detailRow(context, 'Discount Applied', currencyFormat.format(discountAmt)),
                                            _detailRow(context, 'Payment Status', payStatus),
                                          ],
                                        ),
                                        if (notes.isNotEmpty || medical.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          _sectionCard(
                                            context,
                                            title: 'Notes & Medical Info',
                                            icon: Icons.notes_rounded,
                                            children: [
                                              if (notes.isNotEmpty) _detailRow(context, 'Staff Notes', notes),
                                              if (medical.isNotEmpty) _detailRow(context, 'Medical Conditions', medical),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  // Tab 2: Gamification (Level, XP, 15 Badges)
                                  _MemberGamificationEditor(
                                    gymId: widget.gym['id'],
                                    member: m,
                                    onSaveSuccess: () {
                                      setModalState(() {});
                                      _loadMembersData();
                                    },
                                  ),

                                  // Tab 3: Attendance Manager
                                  _UserAttendanceManager(
                                    gymId: widget.gym['id'],
                                    target: m,
                                    isStaff: false,
                                    onUpsertRequested: (existingLog, reload) {
                                      _showUpsertAttendanceDialog(
                                        context,
                                        m,
                                        isStaff: false,
                                        existingLog: existingLog,
                                        onSaved: reload,
                                      );
                                    },
                                  ),

                                  // Tab 4: Membership & Financials
                                  _MemberMembershipEditor(
                                    gymId: widget.gym['id'],
                                    member: m,
                                    gymPlans: _gymPlans,
                                    onSaveSuccess: (newPaid, newPending, newStatus) {
                                      setModalState(() {
                                        m['total_received_amount'] = newPaid;
                                        m['pending_amount'] = newPending;
                                        m['payment_status'] = newStatus;
                                      });
                                      _loadMembersData();
                                      _loadFinanceData();
                                    },
                                  ),

                                  // Tab 5: Owner Actions
                                  SingleChildScrollView(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Owner Level Management Controls', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                                        const SizedBox(height: 6),
                                        Text('As Super Admin, you have full privileges to modify member data, collect payments, and manage status.', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
                                        const SizedBox(height: 20),

                                        _actionCard(
                                          context,
                                          title: 'Collect / Record Payment',
                                          subtitle: 'Record an incoming payment from this member and deduct from pending balance.',
                                          icon: Icons.payments_rounded,
                                          btnColor: AdminTheme.success,
                                          btnText: 'Record Payment',
                                          onTap: () => _showRecordPaymentDialog(dialogCtx, m, setModalState),
                                        ),
                                        const SizedBox(height: 16),

                                        _actionCard(
                                          context,
                                          title: 'Edit Member Profile',
                                          subtitle: 'Update member name, contact info, notes, and active status.',
                                          icon: Icons.edit_note_rounded,
                                          btnColor: AdminTheme.primary,
                                          btnText: 'Edit Details',
                                          onTap: () => _showEditMemberDialog(dialogCtx, m, setModalState),
                                        ),
                                        const SizedBox(height: 16),

                                        _actionCard(
                                          context,
                                          title: 'Delete Member (Safe Archive & 1-Click Restore)',
                                          subtitle: 'Remove from active members and finances. Backup is safely saved in Deleted Members archive with 1-click restore.',
                                          icon: Icons.delete_sweep_rounded,
                                          btnColor: AdminTheme.danger,
                                          btnText: 'Delete Member',
                                          onTap: () => _confirmDeleteMember(m, modalCtx: dialogCtx),
                                        ),
                                        const SizedBox(height: 24),

                                        _buildMemberHistoryTab(context, m['id']),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMemberHistoryTab(BuildContext context, String memberId) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        AdminSupabaseService.client
            .from('finance_transactions')
            .select('*')
            .eq('reference_id', memberId)
            .order('transaction_date', ascending: false)
            .limit(20),
        AdminSupabaseService.client
            .from('attendance_logs')
            .select('*')
            .eq('member_id', memberId)
            .order('date', ascending: false)
            .limit(20),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AdminTheme.primary));
        }

        final txList = (snapshot.data?[0] as List<dynamic>?) ?? [];
        final attList = (snapshot.data?[1] as List<dynamic>?) ?? [];
        final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment Transactions (${txList.length})', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (txList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AdminTheme.surfaceColor(context), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Text('No recorded payments for this member.')),
                )
              else
                ...txList.map((tx) {
                  final amt = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
                  final date = tx['transaction_date']?.toString().split('T').first ?? '-';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdminTheme.borderColor(context)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tx['notes'] ?? 'Payment', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('$date • ${tx['payment_method'] ?? 'UPI'}', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                          ],
                        ),
                        Text(currencyFormat.format(amt), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AdminTheme.success)),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 24),
              Text('Recent Attendance Logs (${attList.length})', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (attList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AdminTheme.surfaceColor(context), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Text('No attendance records logged for this member.')),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: attList.map((att) {
                    final status = att['status']?.toString() ?? 'Present';
                    final date = att['date']?.toString() ?? '-';
                    final isPres = status.toLowerCase() == 'present';
                    return Chip(
                      avatar: Icon(isPres ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 14, color: isPres ? AdminTheme.success : AdminTheme.danger),
                      label: Text('$date: $status', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                      backgroundColor: isPres ? AdminTheme.successLight : AdminTheme.dangerLight,
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  // --- SUB DIALOG: RECORD PAYMENT ---
  Future<void> _showRecordPaymentDialog(BuildContext parentCtx, Map<String, dynamic> m, StateSetter setModalState) async {
    final amtController = TextEditingController();
    final notesController = TextEditingController(text: 'Membership Payment');
    String paymentMethod = 'UPI';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Record Payment for ${m['full_name']}'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amtController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee_rounded)),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    items: ['UPI', 'Cash', 'Card', 'Bank Transfer'].map((pm) => DropdownMenuItem(value: pm, child: Text(pm))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => paymentMethod = val);
                    },
                    decoration: const InputDecoration(labelText: 'Payment Method', prefixIcon: Icon(Icons.account_balance_wallet_rounded)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes', prefixIcon: Icon(Icons.note_rounded)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.success),
                onPressed: () async {
                  final payAmt = double.tryParse(amtController.text.trim()) ?? 0.0;
                  if (payAmt <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount.')));
                    return;
                  }

                  Navigator.pop(ctx);

                  try {
                    final client = AdminSupabaseService.client;
                    final oldReceived = double.tryParse(m['total_received_amount']?.toString() ?? '0') ?? 0.0;
                    final oldPending = double.tryParse(m['pending_amount']?.toString() ?? '0') ?? 0.0;

                    final newReceived = oldReceived + payAmt;
                    final newPending = max(0.0, oldPending - payAmt);
                    final newStatus = newPending <= 0 ? 'Paid' : 'Partial';

                    // 1. Update Member
                    await client.from('members').update({
                      'total_received_amount': newReceived,
                      'pending_amount': newPending,
                      'payment_status': newStatus,
                    }).eq('id', m['id']);

                    // 2. Insert into finance_transactions
                    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                    await client.from('finance_transactions').insert({
                      'gym_id': widget.gym['id'],
                      'amount': payAmt,
                      'type': 'Revenue',
                      'category': 'Membership',
                      'payment_method': paymentMethod,
                      'transaction_date': DateTime.now().toIso8601String(),
                      'reference_id': m['id'],
                      'notes': notesController.text.trim(),
                      'entry_date': todayStr,
                      'revenue_date': todayStr,
                      'created_by_info': 'Super Admin',
                    });

                    // Update local state in modal
                    setModalState(() {
                      m['total_received_amount'] = newReceived;
                      m['pending_amount'] = newPending;
                      m['payment_status'] = newStatus;
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Payment recorded successfully!'), backgroundColor: AdminTheme.success),
                      );
                      _loadFinanceData();
                      _loadMembersData();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Payment failed: $e'), backgroundColor: AdminTheme.danger),
                      );
                    }
                  }
                },
                child: const Text('Confirm Payment'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- SUB DIALOG: EDIT MEMBER ---
  Future<void> _showEditMemberDialog(BuildContext parentCtx, Map<String, dynamic> m, StateSetter setModalState) async {
    final nameController = TextEditingController(text: m['full_name']);
    final phoneController = TextEditingController(text: m['phone'] == '-' ? '' : m['phone']);
    final emailController = TextEditingController(text: m['email'] == '-' ? '' : m['email']);
    final notesController = TextEditingController(text: m['notes']);
    String selectedStatus = m['status'] ?? 'Active';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Member Profile'),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Member Name', prefixIcon: Icon(Icons.person_rounded)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_rounded)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email_rounded)),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: ['Active', 'Pending Activation', 'Inactive', 'Blocked'].contains(selectedStatus) ? selectedStatus : 'Active',
                      items: ['Active', 'Pending Activation', 'Inactive', 'Blocked'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedStatus = val);
                      },
                      decoration: const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.shield_outlined)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Notes', prefixIcon: Icon(Icons.notes_rounded)),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary),
                onPressed: () async {
                  final newName = nameController.text.trim();
                  if (newName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name cannot be empty.')));
                    return;
                  }

                  Navigator.pop(ctx);

                  try {
                    final client = AdminSupabaseService.client;
                    await client.from('members').update({
                      'name': newName,
                      'phone': phoneController.text.trim(),
                      'email': emailController.text.trim(),
                      'status': selectedStatus,
                      'notes': notesController.text.trim(),
                    }).eq('id', m['id']);

                    setModalState(() {
                      m['full_name'] = newName;
                      m['phone'] = phoneController.text.trim();
                      m['email'] = emailController.text.trim();
                      m['status'] = selectedStatus;
                      m['notes'] = notesController.text.trim();
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Member profile updated!'), backgroundColor: AdminTheme.success),
                      );
                      _loadMembersData();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Update failed: $e'), backgroundColor: AdminTheme.danger),
                      );
                    }
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- DELETE & ARCHIVE MEMBER (WITH 1-CLICK RESTORE GUARANTEE) ---
  Future<void> _confirmDeleteMember(Map<String, dynamic> m, {BuildContext? modalCtx}) async {
    final name = m['full_name'] ?? 'Member';
    String selectedScope = 'profile_only';

    final resultScope = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.delete_sweep_rounded, color: AdminTheme.danger),
              const SizedBox(width: 8),
              Expanded(child: Text('Delete "$name"?', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select what information you want to remove for this member:',
                  style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(ctx)),
                ),
                const SizedBox(height: 14),

                // Option 1: Profile Only (Recommended)
                InkWell(
                  onTap: () => setDialogState(() => selectedScope = 'profile_only'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedScope == 'profile_only'
                          ? AdminTheme.primary.withValues(alpha: 0.08)
                          : AdminTheme.surfaceColor(ctx),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selectedScope == 'profile_only'
                            ? AdminTheme.primary
                            : AdminTheme.borderColor(ctx),
                        width: selectedScope == 'profile_only' ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Radio<String>(
                          value: 'profile_only',
                          groupValue: selectedScope,
                          onChanged: (val) => setDialogState(() => selectedScope = val!),
                          activeColor: AdminTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Delete Profile Only',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AdminTheme.textColor(ctx)),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AdminTheme.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Recommended',
                                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminTheme.primary),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Removes member from active member list and frees up slot, but keeps past payment transactions in your financial ledger so revenue reports remain accurate.',
                                style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(ctx), height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Option 2: Full Cascade
                InkWell(
                  onTap: () => setDialogState(() => selectedScope = 'all'),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedScope == 'all'
                          ? AdminTheme.danger.withValues(alpha: 0.08)
                          : AdminTheme.surfaceColor(ctx),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selectedScope == 'all'
                            ? AdminTheme.danger
                            : AdminTheme.borderColor(ctx),
                        width: selectedScope == 'all' ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Radio<String>(
                          value: 'all',
                          groupValue: selectedScope,
                          onChanged: (val) => setDialogState(() => selectedScope = val!),
                          activeColor: AdminTheme.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delete Member & All Linked Records',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AdminTheme.danger),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Removes member, active finance transactions, memberships, and attendance logs. All items are backed up in the Deleted Archive.',
                                style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(ctx), height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Safe Archive Notice
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AdminTheme.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AdminTheme.success.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_rounded, size: 16, color: AdminTheme.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Safe Archive Guarantee: No data is permanently destroyed. You can restore this member with 1-click anytime.',
                          style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.success, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedScope == 'all' ? AdminTheme.danger : AdminTheme.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: Text(selectedScope == 'all' ? 'Delete Everything' : 'Delete Profile Only'),
              onPressed: () => Navigator.pop(ctx, selectedScope),
            ),
          ],
        ),
      ),
    );

    if (resultScope == null) return;

    try {
      final client = AdminSupabaseService.client;
      final res = await client.rpc('admin_archive_delete_member', params: {
        'p_member_id': m['id'],
        'p_gym_id': widget.gym['id'],
        'p_delete_scope': resultScope,
      });

      final result = Map<String, dynamic>.from(res as Map);
      if (result['success'] == true) {
        if (modalCtx != null && mounted) {
          Navigator.pop(modalCtx);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Member "$name" deleted & archived. You can restore anytime!'),
              backgroundColor: AdminTheme.success,
              action: SnackBarAction(
                label: 'Open Restore Tab',
                textColor: Colors.white,
                onPressed: () {
                  _tabController.animateTo(5);
                },
              ),
            ),
          );
          _loadMembersData();
          _loadFinanceData();
          _loadDeletedMembersData();
          _loadUnlinkedEntries();
        }
      } else {
        throw Exception(result['message'] ?? 'Failed to delete member');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete member: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  // --- 1-CLICK RESTORE DELETED MEMBER ---
  Future<void> _restoreDeletedMember(Map<String, dynamic> dm) async {
    final name = dm['full_name'] ?? 'Member';
    try {
      final client = AdminSupabaseService.client;
      final res = await client.rpc('admin_restore_deleted_member', params: {
        'p_deleted_id': dm['id'],
      });

      final result = Map<String, dynamic>.from(res as Map);
      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ "$name" and all financial/attendance records restored successfully!'),
              backgroundColor: AdminTheme.success,
            ),
          );
          _loadMembersData();
          _loadFinanceData();
          _loadDeletedMembersData();
          _loadUnlinkedEntries();
        }
      } else {
        throw Exception(result['message'] ?? 'Failed to restore member');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restore member: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  // --- PERMANENT PURGE DELETED MEMBER ---
  Future<void> _permanentPurgeDeletedMember(Map<String, dynamic> dm) async {
    final name = dm['full_name'] ?? 'Member';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AdminTheme.danger),
            SizedBox(width: 8),
            Text('Permanently Wipe Member?'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "$name" from the archive?\n\n'
          'This will wipe all backup snapshots. This action CANNOT be undone.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Permanent Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final client = AdminSupabaseService.client;
      await client.rpc('admin_purge_deleted_member', params: {
        'p_deleted_id': dm['id'],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Member "$name" permanently removed from archive.'), backgroundColor: AdminTheme.danger),
        );
        _loadDeletedMembersData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to purge: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  // --- RESTORE ALL DELETED MEMBERS (BATCH 1-CLICK) ---
  Future<void> _restoreAllDeletedMembers() async {
    if (_deletedMembers.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings_backup_restore_rounded, color: AdminTheme.success),
            SizedBox(width: 8),
            Text('Restore All Deleted Records?'),
          ],
        ),
        content: Text(
          'Are you sure you want to restore all ${_deletedMembers.length} deleted records back to active status?\n\n'
          'All financial entries will be smartly re-linked without duplicates, and member profiles will become active immediately.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.success, foregroundColor: Colors.white),
            icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
            label: const Text('Restore All'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (mounted) setState(() => _loadingDeletedMembers = true);
      final client = AdminSupabaseService.client;
      int successCount = 0;
      for (final dm in List<Map<String, dynamic>>.from(_deletedMembers)) {
        try {
          await client.rpc('admin_restore_deleted_member', params: {'p_deleted_id': dm['id']});
          successCount++;
        } catch (e) {
          debugPrint('Error restoring item: $e');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Successfully restored $successCount deleted records!'),
            backgroundColor: AdminTheme.success,
          ),
        );
        _loadMembersData();
        _loadFinanceData();
        _loadDeletedMembersData();
        _loadUnlinkedEntries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during batch restore: $e'), backgroundColor: AdminTheme.danger),
        );
        _loadDeletedMembersData();
      }
    }
  }

  // --- BUILD UI ---
  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      backgroundColor: AdminTheme.backgroundColor(context),
      appBar: AppBar(
        backgroundColor: AdminTheme.surfaceColor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AdminTheme.textColor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.gym['name'] ?? 'Gym Console',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
            ),
            Text(
              'Super Admin Management Portal • Full Owner Level Access',
              style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AdminTheme.primary,
          unselectedLabelColor: AdminTheme.secondaryTextColor(context),
          indicatorColor: AdminTheme.primary,
          tabs: [
            const Tab(icon: Icon(Icons.analytics_rounded), text: 'Financials'),
            Tab(icon: const Icon(Icons.people_rounded), text: 'Members (${_members.length})'),
            Tab(icon: const Icon(Icons.badge_rounded), text: 'Staff List (${_staff.length})'),
            Tab(
              icon: Badge(
                isLabelVisible: _diagnostics.isNotEmpty,
                label: Text('${_diagnostics.length}', style: const TextStyle(fontSize: 10)),
                backgroundColor: Colors.orange,
                child: const Icon(Icons.healing_rounded),
              ),
              text: 'Health & Diagnostics (${_diagnostics.length})',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: _unlinkedEntries.isNotEmpty,
                label: Text('${_unlinkedEntries.length}', style: const TextStyle(fontSize: 10)),
                backgroundColor: AdminTheme.danger,
                child: const Icon(Icons.link_off_rounded),
              ),
              text: 'Unlinked Entries',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: _deletedMembers.isNotEmpty,
                label: Text('${_deletedMembers.length}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: AdminTheme.danger,
                child: const Icon(Icons.settings_backup_restore_rounded),
              ),
              text: 'Restore (${_deletedMembers.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Quick Action Bar
          _buildQuickActionBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _loadingFinance
                    ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
                    : _buildFinanceTab(currencyFormat),
                _loadingMembers
                    ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
                    : _buildMembersTab(),
                _loadingStaff
                    ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
                    : _buildStaffTab(),
                _loadingDiagnostics
                    ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
                    : _buildDiagnosticsTab(),
                _loadingUnlinked
                    ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
                    : _buildUnlinkedTab(currencyFormat),
                _loadingDeletedMembers
                    ? const Center(child: CircularProgressIndicator(color: AdminTheme.danger))
                    : _buildRestoreTab(currencyFormat),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBar() {
    return Container(
      color: AdminTheme.surfaceColor(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _actionChip(_isLocked ? 'Unlock Gym' : 'Lock Gym', _isLocked ? Icons.lock_open_rounded : Icons.lock_rounded, _isLocked ? Colors.orange : AdminTheme.primary, _toggleLock),
            const SizedBox(width: 10),
            _actionChip(_gymStatus == 'Active' ? 'Suspend Gym' : 'Activate Gym', _gymStatus == 'Active' ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, _gymStatus == 'Active' ? AdminTheme.danger : AdminTheme.success, _toggleSuspend),
            const SizedBox(width: 10),
            _actionChip('Export Backup', Icons.download_rounded, Colors.blue, _exportBackup),
            const SizedBox(width: 10),
            _actionChip('Delete Gym (Wipe)', Icons.delete_forever_rounded, AdminTheme.danger, _deleteGymWithAutoBackup),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.2)),
      onPressed: onTap,
    );
  }

  // --- FINANCIALS TAB ---
  Widget _buildFinanceTab(NumberFormat fmt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monthly Financial Ledger', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              Row(
                children: [
                  DropdownButton<int>(
                    value: _selectedMonth,
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedMonth = val);
                        _loadFinanceData();
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<int>(
                    value: _selectedYear,
                    items: [2024, 2025, 2026, 2027].map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedYear = val);
                        _loadFinanceData();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stats Row: Revenue, Expense, Net Profit, Pending Dues
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _statCard('Revenue (${months[_selectedMonth - 1]})', fmt.format(_totalRevenue), Icons.arrow_upward_rounded, AdminTheme.success),
                _statCard('Expense (${months[_selectedMonth - 1]})', fmt.format(_totalExpense), Icons.arrow_downward_rounded, Colors.red),
                _statCard('Net Profit', fmt.format(_totalRevenue - _totalExpense), Icons.account_balance_wallet_rounded, AdminTheme.primary),
                _statCard('Total Pending Due', fmt.format(_totalPending), Icons.pending_actions_rounded, Colors.orange),
              ];
              if (constraints.maxWidth < 900) {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards.map((c) => SizedBox(width: (constraints.maxWidth - 12) / 2, child: c)).toList(),
                );
              }
              return Row(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ledger Transactions (${_transactions.length})', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_card_rounded, size: 16),
                label: Text('Record Transaction', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _showRecordTransactionDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: _transactions.isEmpty
                ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No transactions recorded.')))
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _transactions.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      final isRev = tx['type'] == 'Revenue';
                      final amt = double.tryParse(tx['amount'].toString()) ?? 0.0;
                      final txDateStr = tx['transaction_date']?.toString();
                      final txDate = txDateStr != null ? DateTime.tryParse(txDateStr) : null;
                      final dateFormatted = txDate != null ? DateFormat('dd MMM yyyy').format(txDate) : '';

                      // Check for linked member or staff
                      String linkedName = '';
                      if (tx['reference_id'] != null && tx['reference_id'].toString().isNotEmpty) {
                        final refId = tx['reference_id'].toString();
                        final memberMatch = _members.firstWhere((m) => m['id'] == refId, orElse: () => {});
                        if (memberMatch.isNotEmpty && memberMatch['full_name'] != null) {
                          linkedName = memberMatch['full_name'];
                        } else {
                          final staffMatch = _staff.firstWhere((s) => s['id'] == refId, orElse: () => {});
                          if (staffMatch.isNotEmpty && staffMatch['full_name'] != null) {
                            linkedName = staffMatch['full_name'];
                          }
                        }
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRev ? AdminTheme.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          child: Icon(isRev ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: isRev ? AdminTheme.success : Colors.red, size: 18),
                        ),
                        title: Row(
                          children: [
                            Text(tx['category'] ?? 'Other', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                            if (linkedName.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AdminTheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AdminTheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(tx['category'] == 'Salary' ? Icons.badge_outlined : Icons.person_outline, size: 11, color: AdminTheme.primary),
                                    const SizedBox(width: 4),
                                    Text(linkedName, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminTheme.primary)),
                                  ],
                                ),
                              ),
                            ],
                            if (tx['payment_method'] != null && tx['payment_method'].toString().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AdminTheme.borderColor(context), borderRadius: BorderRadius.circular(4)),
                                child: Text(tx['payment_method'], style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                            if (dateFormatted.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('• $dateFormatted', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                            ],
                          ],
                        ),
                        subtitle: Text(tx['notes'] ?? "", style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${isRev ? "+" : "-"}${fmt.format(amt)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: isRev ? AdminTheme.success : Colors.red)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Edit Transaction',
                              onPressed: () => _showEditTransactionDialog(tx),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              tooltip: 'Delete Transaction',
                              onPressed: () => _deleteTransaction(tx),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }

  // --- RECORD NEW TRANSACTION DIALOG ---
  void _showRecordTransactionDialog() {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String type = 'Revenue';
    String category = 'Membership';
    String method = 'Cash';
    String? selectedMemberId;
    String? selectedStaffId;
    DateTime txDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AdminTheme.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                CircleAvatar(backgroundColor: AdminTheme.primary.withValues(alpha: 0.1), child: const Icon(Icons.add_card_rounded, color: AdminTheme.primary)),
                const SizedBox(width: 12),
                Text('Record Transaction', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Revenue'),
                          selected: type == 'Revenue',
                          selectedColor: AdminTheme.success.withValues(alpha: 0.2),
                          onSelected: (val) {
                            if (val) setDialogState(() { type = 'Revenue'; category = 'Membership'; });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Expense'),
                          selected: type == 'Expense',
                          selectedColor: Colors.red.withValues(alpha: 0.2),
                          onSelected: (val) {
                            if (val) setDialogState(() { type = 'Expense'; category = 'Salary'; });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee_rounded)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_rounded)),
                    items: (type == 'Revenue'
                            ? ['Membership', 'Personal Training', 'Supplements', 'Merchandise', 'Registration Fee', 'Other Revenue']
                            : ['Salary', 'Rent', 'Electricity', 'Equipment Maintenance', 'Water', 'Marketing', 'Other Expense'])
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) => setDialogState(() {
                      category = val ?? category;
                      selectedMemberId = null;
                      selectedStaffId = null;
                    }),
                  ),
                  if (category == 'Membership' && _members.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedMemberId,
                      decoration: const InputDecoration(labelText: 'Link to Member (Optional)', prefixIcon: Icon(Icons.person_outline)),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('-- No Member Linked --')),
                        ..._members.map((m) => DropdownMenuItem<String?>(
                              value: m['id']?.toString(),
                              child: Text('${m['full_name']} (Due: ₹${m['pending_amount']})', overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) => setDialogState(() => selectedMemberId = val),
                    ),
                  ],
                  if (category == 'Salary' && _staff.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedStaffId,
                      decoration: const InputDecoration(labelText: 'Link to Staff (Optional)', prefixIcon: Icon(Icons.badge_outlined)),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('-- No Staff Linked --')),
                        ..._staff.map((s) => DropdownMenuItem<String?>(
                              value: s['id']?.toString(),
                              child: Text('${s['full_name']} (Salary Due: ₹${s['salary_due']})', overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) => setDialogState(() => selectedStaffId = val),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: method,
                    decoration: const InputDecoration(labelText: 'Payment Method', prefixIcon: Icon(Icons.payment_rounded)),
                    items: ['Cash', 'UPI', 'Bank Transfer', 'Cheque', 'Card', 'Other']
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => method = val ?? method),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_rounded, size: 20),
                    title: Text('Date: ${DateFormat('dd MMM yyyy').format(txDate)}', style: GoogleFonts.inter(fontSize: 13)),
                    trailing: TextButton(
                      child: const Text('Change'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: txDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setDialogState(() => txDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes / Description', prefixIcon: Icon(Icons.notes_rounded)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  if (amt <= 0) return;
                  Navigator.pop(ctx);
                  try {
                    final refId = (category == 'Membership' ? selectedMemberId : (category == 'Salary' ? selectedStaffId : null));
                    await AdminSupabaseService.client.from('finance_transactions').insert({
                      'gym_id': widget.gym['id'],
                      'type': type,
                      'category': category,
                      'amount': amt,
                      'payment_method': method,
                      'reference_id': refId,
                      'transaction_date': txDate.toIso8601String(),
                      'expense_date': type == 'Expense' ? DateFormat('yyyy-MM-dd').format(txDate) : null,
                      'revenue_date': type == 'Revenue' ? DateFormat('yyyy-MM-dd').format(txDate) : null,
                      'notes': notesCtrl.text.trim(),
                      'created_by_info': 'Super Admin',
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ $type of ₹$amt recorded!'), backgroundColor: AdminTheme.success),
                      );
                      await Future.wait([
                        _loadFinanceData(),
                        _loadMembersData(),
                        _loadStaffData(),
                      ]);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error recording transaction: $e'), backgroundColor: AdminTheme.danger),
                      );
                    }
                  }
                },
                child: const Text('Save Transaction'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- EDIT TRANSACTION DIALOG ---
  void _showEditTransactionDialog(Map<String, dynamic> tx) {
    final amountCtrl = TextEditingController(text: (tx['amount'] ?? '').toString());
    final notesCtrl = TextEditingController(text: (tx['notes'] ?? '').toString());
    String type = tx['type']?.toString() ?? 'Expense';
    String category = tx['category']?.toString() ?? 'Salary';
    String method = tx['payment_method']?.toString() ?? 'Cash';
    String? selectedRefId = tx['reference_id']?.toString();
    DateTime txDate = DateTime.tryParse(tx['transaction_date']?.toString() ?? '') ?? DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final catList = (type == 'Revenue'
              ? ['Membership', 'Personal Training', 'Supplements', 'Merchandise', 'Registration Fee', 'Other Revenue']
              : ['Salary', 'Rent', 'Electricity', 'Equipment Maintenance', 'Water', 'Marketing', 'Other Expense']);
          if (!catList.contains(category)) {
            catList.add(category);
          }

          final methodList = ['Cash', 'UPI', 'Bank Transfer', 'Cheque', 'Card', 'Other'];
          if (!methodList.contains(method)) {
            methodList.add(method);
          }

          return AlertDialog(
            backgroundColor: AdminTheme.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                CircleAvatar(backgroundColor: Colors.blue.withValues(alpha: 0.1), child: const Icon(Icons.edit_note_rounded, color: Colors.blue)),
                const SizedBox(width: 12),
                Text('Edit Transaction Entry', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Revenue'),
                          selected: type == 'Revenue',
                          selectedColor: AdminTheme.success.withValues(alpha: 0.2),
                          onSelected: (val) {
                            if (val) setDialogState(() { type = 'Revenue'; category = 'Membership'; });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Expense'),
                          selected: type == 'Expense',
                          selectedColor: Colors.red.withValues(alpha: 0.2),
                          onSelected: (val) {
                            if (val) setDialogState(() { type = 'Expense'; category = 'Salary'; });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee_rounded)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_rounded)),
                    items: catList.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setDialogState(() => category = val ?? category),
                  ),
                  if (category == 'Membership' && _members.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: _members.any((m) => m['id'] == selectedRefId) ? selectedRefId : null,
                      decoration: const InputDecoration(labelText: 'Linked Member', prefixIcon: Icon(Icons.person_outline)),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('-- No Member Linked --')),
                        ..._members.map((m) => DropdownMenuItem<String?>(
                              value: m['id']?.toString(),
                              child: Text('${m['full_name']} (Due: ₹${m['pending_amount']})', overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) => setDialogState(() => selectedRefId = val),
                    ),
                  ],
                  if (category == 'Salary' && _staff.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: _staff.any((s) => s['id'] == selectedRefId) ? selectedRefId : null,
                      decoration: const InputDecoration(labelText: 'Linked Staff', prefixIcon: Icon(Icons.badge_outlined)),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('-- No Staff Linked --')),
                        ..._staff.map((s) => DropdownMenuItem<String?>(
                              value: s['id']?.toString(),
                              child: Text('${s['full_name']} (Salary Due: ₹${s['salary_due']})', overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) => setDialogState(() => selectedRefId = val),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: method,
                    decoration: const InputDecoration(labelText: 'Payment Method', prefixIcon: Icon(Icons.payment_rounded)),
                    items: methodList.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) => setDialogState(() => method = val ?? method),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_rounded, size: 20),
                    title: Text('Date: ${DateFormat('dd MMM yyyy').format(txDate)}', style: GoogleFonts.inter(fontSize: 13)),
                    trailing: TextButton(
                      child: const Text('Change'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: txDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setDialogState(() => txDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes / Description', prefixIcon: Icon(Icons.notes_rounded)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  if (amt <= 0) return;
                  Navigator.pop(ctx);
                  try {
                    await AdminSupabaseService.client.from('finance_transactions').update({
                      'type': type,
                      'category': category,
                      'amount': amt,
                      'payment_method': method,
                      'reference_id': (category == 'Membership' || category == 'Salary') ? selectedRefId : tx['reference_id'],
                      'transaction_date': txDate.toIso8601String(),
                      'expense_date': type == 'Expense' ? DateFormat('yyyy-MM-dd').format(txDate) : null,
                      'revenue_date': type == 'Revenue' ? DateFormat('yyyy-MM-dd').format(txDate) : null,
                      'notes': notesCtrl.text.trim(),
                    }).eq('id', tx['id']);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Transaction updated & balances synchronized!'), backgroundColor: AdminTheme.success),
                      );
                      await Future.wait([
                        _loadFinanceData(),
                        _loadMembersData(),
                        _loadStaffData(),
                      ]);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating transaction: $e'), backgroundColor: AdminTheme.danger),
                      );
                    }
                  }
                },
                child: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- DELETE TRANSACTION ---
  void _deleteTransaction(Map<String, dynamic> tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Transaction?'),
        content: Text('Are you sure you want to delete this ${tx['type']} entry of ₹${tx['amount']} (${tx['category']})? This will automatically recalculate member balances & dues. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await AdminSupabaseService.client.from('finance_transactions').delete().eq('id', tx['id']);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Transaction deleted & balances synchronized!'), backgroundColor: Colors.red),
                  );
                  await Future.wait([
                    _loadFinanceData(),
                    _loadMembersData(),
                    _loadStaffData(),
                  ]);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting transaction: $e'), backgroundColor: AdminTheme.danger),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // --- MEMBERS TAB ---
  Widget _buildMembersTab() {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final filtered = _members.where((m) {
      final name = m['full_name'].toString().toLowerCase();
      final phone = m['phone'].toString().toLowerCase();
      final q = _memberSearch.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _memberSearch = val),
                  decoration: InputDecoration(
                    hintText: 'Search members by name or mobile number...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AdminTheme.surfaceColor(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Direct Shortcut to Restore Tab
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(
                    color: _deletedMembers.isNotEmpty ? Colors.redAccent.withValues(alpha: 0.5) : AdminTheme.borderColor(context),
                  ),
                  backgroundColor: _deletedMembers.isNotEmpty ? Colors.redAccent.withValues(alpha: 0.05) : Colors.transparent,
                ),
                icon: Icon(
                  Icons.settings_backup_restore_rounded,
                  size: 18,
                  color: _deletedMembers.isNotEmpty ? Colors.redAccent : AdminTheme.secondaryTextColor(context),
                ),
                label: Text(
                  'Restore Tab (${_deletedMembers.length})',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _deletedMembers.isNotEmpty ? Colors.redAccent : AdminTheme.secondaryTextColor(context),
                  ),
                ),
                onPressed: () => _tabController.animateTo(5),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (filtered.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline_rounded, size: 64, color: AdminTheme.mutedTextColor(context)),
                    const SizedBox(height: 12),
                    Text('No members found', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                    const SizedBox(height: 4),
                    Text('Check your search filter or add members via the Gym OS mobile app.', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                itemCount: filtered.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  childAspectRatio: 1.75,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemBuilder: (context, index) {
                  final m = filtered[index];
                  final name = m['full_name'] ?? 'Member';
                  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                  final avatar = m['avatar_url'];
                  final pending = m['pending_amount'] as double? ?? 0.0;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showMemberDetailsDialog(m),
                      hoverColor: AdminTheme.primary.withValues(alpha: 0.04),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AdminTheme.surfaceColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AdminTheme.borderColor(context)),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                InteractiveAvatarWrapper(
                                  imageUrl: avatar?.toString(),
                                  title: name,
                                  subtitle: 'Member Profile Photo • ${m['phone'] ?? ''}',
                                  radius: 22,
                                  showZoomBadge: false,
                                  child: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AdminTheme.primary.withValues(alpha: 0.12),
                                    backgroundImage: (avatar != null && avatar.toString().isNotEmpty) ? NetworkImage(avatar) : null,
                                    child: (avatar == null || avatar.toString().isEmpty)
                                        ? Text(initial, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: AdminTheme.primary))
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: AdminTheme.textColor(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(m['phone'] ?? '-', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context))),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                  tooltip: 'Delete & Archive Member',
                                  onPressed: () => _confirmDeleteMember(m),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: AdminTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                                  child: Text(m['membership_name'] ?? 'No Plan', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminTheme.primary)),
                                ),
                                const Spacer(),
                                _statusChip(m['status'] ?? 'Active'),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _paymentBadge(m['payment_status'] ?? 'Pending'),
                                if (pending > 0)
                                  Text('Due: ${currencyFormat.format(pending)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AdminTheme.danger))
                                else
                                  Text('Clear', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminTheme.success)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // --- DEDICATED RESTORE / ARCHIVE TAB ---
  Widget _buildRestoreTab(NumberFormat currencyFormat) {
    final filtered = _deletedMembers.where((dm) {
      final name = (dm['full_name'] ?? '').toString().toLowerCase();
      final phone = (dm['phone'] ?? '').toString().toLowerCase();
      final q = _deletedMemberSearch.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AdminTheme.primary.withValues(alpha: 0.1),
                  AdminTheme.surfaceColor(context),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdminTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.settings_backup_restore_rounded, color: AdminTheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gym Recycle Bin & 1-Click Restore Hub',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'All deleted members, attendance records, and transactions are safely stored here. Click "Restore" to bring them back instantly without data loss or duplicates.',
                        style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context), height: 1.3),
                      ),
                    ],
                  ),
                ),
                if (_deletedMembers.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.restore_page_rounded, size: 18),
                    label: Text('Restore All (${_deletedMembers.length})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: _restoreAllDeletedMembers,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Search and Action Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _deletedMemberSearch = val),
                  decoration: InputDecoration(
                    hintText: 'Search deleted records by member name or phone number...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AdminTheme.surfaceColor(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: AdminTheme.borderColor(context)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
                onPressed: _loadDeletedMembersData,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Content Area
          if (_loadingDeletedMembers)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: AdminTheme.primary)),
            )
          else if (filtered.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restore_from_trash_rounded, size: 64, color: AdminTheme.mutedTextColor(context)),
                    const SizedBox(height: 12),
                    Text(
                      _deletedMembers.isEmpty ? 'Recycle bin is clean!' : 'No matching deleted records found',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _deletedMembers.isEmpty
                          ? 'No members have been deleted from this gym yet. When any member is deleted, they will safely appear here for 1-click restore.'
                          : 'Try searching with a different name or phone number.',
                      style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                itemCount: filtered.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemBuilder: (context, index) {
                  final dm = filtered[index];
                  final name = dm['full_name'] ?? 'Member';
                  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                  final avatar = dm['avatar_url'];
                  final phone = dm['phone'] ?? '-';
                  final planName = dm['membership_name'] ?? 'No Plan';
                  final totalRec = double.tryParse(dm['total_received_amount']?.toString() ?? '0') ?? 0.0;
                  final pending = double.tryParse(dm['pending_amount']?.toString() ?? '0') ?? 0.0;
                  final deletedAtRaw = dm['deleted_at']?.toString();
                  DateTime? deletedAt = deletedAtRaw != null ? DateTime.tryParse(deletedAtRaw) : null;
                  final deletedDateStr = deletedAt != null
                      ? DateFormat('dd MMM yyyy, hh:mm a').format(deletedAt)
                      : 'Unknown date';
                  final isProfileOnly = (dm['delete_scope'] == 'profile_only');
                  final deletedBy = dm['deleted_by_role'] ?? 'owner';

                  return Container(
                    decoration: BoxDecoration(
                      color: AdminTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AdminTheme.borderColor(context)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            InteractiveAvatarWrapper(
                              imageUrl: avatar?.toString(),
                              title: name,
                              subtitle: 'Member Profile Photo • $phone',
                              radius: 22,
                              showZoomBadge: false,
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: AdminTheme.primary.withValues(alpha: 0.12),
                                backgroundImage: (avatar != null && avatar.toString().isNotEmpty) ? NetworkImage(avatar) : null,
                                child: (avatar == null || avatar.toString().isEmpty)
                                    ? Text(initial, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: AdminTheme.primary))
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: AdminTheme.textColor(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text('📞 $phone', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Archived', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isProfileOnly ? Colors.blue.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isProfileOnly ? 'Profile Only' : 'Full Data',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: isProfileOnly ? Colors.blueAccent : Colors.orangeAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AdminTheme.backgroundColor(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Plan: $planName', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context))),
                              Text('Paid: ${currencyFormat.format(totalRec)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminTheme.success)),
                              if (pending > 0)
                                Text('Due: ${currencyFormat.format(pending)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AdminTheme.danger)),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Deleted: $deletedDateStr',
                              style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context)),
                            ),
                            Text(
                              'By: ${deletedBy.toString().toUpperCase()}',
                              style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.restore_rounded, size: 16),
                                label: const Text('1-Click Restore'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AdminTheme.success,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _restoreDeletedMember(dm),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_forever_rounded, color: AdminTheme.danger, size: 22),
                              tooltip: 'Permanently Wipe from Database',
                              onPressed: () => _permanentPurgeDeletedMember(dm),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // --- STAFF TAB ---
  Widget _buildStaffTab() {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final filtered = _staff.where((s) => s['full_name'].toString().toLowerCase().contains(_staffSearch.toLowerCase())).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => _staffSearch = val),
            decoration: InputDecoration(
              hintText: 'Search staff by name...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AdminTheme.surfaceColor(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          if (filtered.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.badge_outlined, size: 64, color: AdminTheme.mutedTextColor(context)),
                    const SizedBox(height: 12),
                    Text('No staff members found', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                    const SizedBox(height: 4),
                    Text('No staff members are currently registered for ${widget.gym['name'] ?? 'this gym'}.', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final s = filtered[index];
                  final name = s['full_name'] ?? 'Staff';
                  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                  final avatar = s['avatar_url'];
                  final salary = s['salary'] as double? ?? 0.0;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showStaffDetailsDialog(s),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AdminTheme.surfaceColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AdminTheme.borderColor(context)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            InteractiveAvatarWrapper(
                              imageUrl: avatar?.toString(),
                              title: name,
                              subtitle: 'Staff Profile Photo • Role: ${s['role'] ?? 'Staff'}',
                              radius: 24,
                              showZoomBadge: false,
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.indigo.withValues(alpha: 0.12),
                                backgroundImage: (avatar != null && avatar.toString().isNotEmpty) ? NetworkImage(avatar) : null,
                                child: (avatar == null || avatar.toString().isEmpty)
                                    ? Text(initial, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16))
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: AdminTheme.textColor(context))),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Text(s['role'] ?? 'Staff', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${s['phone']} • ${s['email']}', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
                                  Text('Shift: ${s['shift']} • Join Date: ${s['join_date']}', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                                ],
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                final due = double.tryParse(s['salary_due']?.toString() ?? '0') ?? 0.0;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(currencyFormat.format(salary), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: AdminTheme.textColor(context))),
                                    Text('/ month', style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context))),
                                    if (due > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text('Due: ${currencyFormat.format(due)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.settings_rounded, color: Colors.indigo, size: 20),
                              tooltip: 'Manage Staff, Salary & Attendance',
                              onPressed: () => _showStaffDetailsDialog(s),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // --- UNLINKED ENTRIES TAB ---
  Widget _buildUnlinkedTab(NumberFormat fmt) {
    final filtered = _unlinkedEntries.where((tx) {
      final q = _unlinkedSearch.toLowerCase();
      final notes = tx['notes']?.toString().toLowerCase() ?? '';
      final ref = tx['reference_id']?.toString().toLowerCase() ?? '';
      return notes.contains(q) || ref.contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _unlinkedSearch = val),
                  decoration: InputDecoration(
                    hintText: 'Search unlinked entries by notes or reference ID...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AdminTheme.surfaceColor(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                icon: const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(backgroundColor: AdminTheme.primary),
                onPressed: () {
                  setState(() => _loadingUnlinked = true);
                  _loadUnlinkedEntries();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtered.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Found ${filtered.length} unlinked financial record(s) where the original member has been deleted. Click "Delete Everywhere" to cascade clean them completely.',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.amber[900]),
                    ),
                  ),
                ],
              ),
            ),
          if (filtered.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 64, color: AdminTheme.success),
                    const SizedBox(height: 12),
                    Text('All Financial Entries Linked!', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                    const SizedBox(height: 4),
                    Text('No orphaned or unlinked records found for deleted members in this gym.', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  final amt = double.tryParse(entry['amount']?.toString() ?? '0') ?? 0.0;
                  final refId = entry['reference_id']?.toString() ?? 'Missing';
                  final date = entry['transaction_date']?.toString().split('T').first ?? '-';
                  final notes = entry['notes']?.toString() ?? 'Automatic Membership Payment';
                  final method = entry['payment_method']?.toString() ?? 'Cash';

                  return Container(
                    decoration: BoxDecoration(
                      color: AdminTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminTheme.danger.withValues(alpha: 0.2)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AdminTheme.danger.withValues(alpha: 0.1),
                          child: const Icon(Icons.link_off_rounded, color: AdminTheme.danger, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(fmt.format(amt), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: AdminTheme.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                    child: Text('Deleted Member Entry', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminTheme.danger)),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                    child: Text(method, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(notes, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AdminTheme.textColor(context))),
                              const SizedBox(height: 2),
                              Text('Date: $date • Former Member UUID: $refId', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AdminTheme.danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            minimumSize: Size.zero,
                          ),
                          icon: const Icon(Icons.delete_forever_rounded, size: 16),
                          label: const Text('Delete Everywhere'),
                          onPressed: () => _deleteUnlinkedEntry(entry),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // --- STAT CARD ---
  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminTheme.secondaryTextColor(context))),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- HELPER CHIPS & MINI CARDS ---
  Widget _statusChip(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'active':
        color = AdminTheme.success;
        break;
      case 'pending activation':
        color = Colors.orange;
        break;
      case 'inactive':
      case 'blocked':
        color = AdminTheme.danger;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(status, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _paymentBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'paid':
        color = AdminTheme.success;
        break;
      case 'partial':
        color = Colors.orange;
        break;
      case 'pending':
      default:
        color = AdminTheme.danger;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(status, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _miniInfoCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminTheme.secondaryTextColor(context))),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, {required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AdminTheme.primary),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value, {bool canCopy = false, bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
          Row(
            children: [
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isNegative ? AdminTheme.danger : AdminTheme.textColor(context),
                ),
              ),
              if (canCopy && value != '-') ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied "$value" to clipboard.')));
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color btnColor,
    required String btnText,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: btnColor.withValues(alpha: 0.1),
            child: Icon(icon, color: btnColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: Size.zero,
            ),
            onPressed: onTap,
            child: Text(btnText, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- GYM HEALTH & DIAGNOSTICS TAB ("KYA SCENE HAI") ---
  Widget _buildDiagnosticsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gym Health & Anomaly Scanner', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                  const SizedBox(height: 4),
                  Text('Autonomous diagnostic scanner detecting broken payments, expired active memberships, unlinked app logins & missing profiles.', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Re-scan Gym Health'),
                onPressed: () {
                  setState(() => _loadingDiagnostics = true);
                  _loadDiagnosticsData();
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _statCard('Total Anomalies', '${_diagnostics.length}', Icons.healing_rounded, _diagnostics.isEmpty ? AdminTheme.success : Colors.orange)),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  'Critical / High Issues',
                  '${_diagnostics.where((d) => d['severity'] == 'CRITICAL').length}',
                  Icons.warning_amber_rounded,
                  AdminTheme.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  'System Health Status',
                  _diagnostics.isEmpty ? '100% Healthy' : '${max(0, 100 - _diagnostics.length * 5)}% Optimal',
                  Icons.check_circle_outline_rounded,
                  _diagnostics.isEmpty ? AdminTheme.success : Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_diagnostics.isEmpty)
            Expanded(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AdminTheme.success.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, size: 64, color: AdminTheme.success),
                      const SizedBox(height: 16),
                      Text('All Systems 100% Operational!', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                      const SizedBox(height: 8),
                      Text('No broken payments, expired active memberships, or orphaned records found in this gym.', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _diagnostics.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _diagnostics[index];
                  final sev = item['severity']?.toString() ?? 'WARNING';
                  final cat = item['category']?.toString() ?? 'ANOMALY';
                  final title = item['title']?.toString() ?? 'System Anomaly Detected';
                  final desc = item['description']?.toString() ?? '';
                  final actionType = item['action_type']?.toString();
                  final targetId = item['target_id']?.toString() ?? '';
                  final isAuto = item['auto_fixable'] == true;

                  Color sevColor = Colors.orange;
                  IconData sevIcon = Icons.warning_amber_rounded;
                  if (sev == 'CRITICAL') {
                    sevColor = AdminTheme.danger;
                    sevIcon = Icons.error_outline_rounded;
                  } else if (sev == 'NOTICE') {
                    sevColor = Colors.blue;
                    sevIcon = Icons.info_outline_rounded;
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: AdminTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sevColor.withValues(alpha: 0.3)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: sevColor.withValues(alpha: 0.1),
                          child: Icon(sevIcon, color: sevColor, size: 22),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: sevColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                    child: Text(cat, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: sevColor)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(desc, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.textColor(context))),
                              if (targetId.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('Target UUID: $targetId', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                              ],
                            ],
                          ),
                        ),
                        if (isAuto && actionType != null) ...[
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminTheme.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                            label: const Text('1-Click Auto-Repair'),
                            onPressed: () => _runAutoRepair(actionType, targetId),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// =========================================================================
// HELPER MASTER CONTROLLERS & EDITORS
// =========================================================================

// --- 1. MEMBER GAMIFICATION EDITOR (LEVEL, XP, 15 BADGES) ---
class _MemberGamificationEditor extends StatefulWidget {
  final dynamic gymId;
  final Map<String, dynamic> member;
  final VoidCallback onSaveSuccess;

  const _MemberGamificationEditor({
    required this.gymId,
    required this.member,
    required this.onSaveSuccess,
  });

  @override
  State<_MemberGamificationEditor> createState() => _MemberGamificationEditorState();
}

class _MemberGamificationEditorState extends State<_MemberGamificationEditor> {
  bool _loading = true;
  bool _saving = false;

  int _level = 1;
  int _xp = 0;
  String _title = '🌱 Novice Lifter';
  Set<String> _unlockedBadges = {};
  late TextEditingController _xpController;

  static const List<Map<String, String>> _availableBadges = [
    {'key': 'first_step', 'name': 'First Step', 'desc': 'First gym check-in logged'},
    {'key': 'week_warrior', 'name': 'Week Warrior', 'desc': 'Consistent for 7 days'},
    {'key': 'perfect_month', 'name': 'Perfect Month', 'desc': 'High monthly attendance'},
    {'key': 'century_club', 'name': 'Century Club', 'desc': '100 Gym sessions reached'},
    {'key': 'club_365', 'name': '365 Club', 'desc': '1 year of dedication'},
    {'key': 'early_bird', 'name': 'Early Bird', 'desc': 'Morning workouts completed'},
    {'key': 'weekend_warrior', 'name': 'Weekend Warrior', 'desc': 'Weekend training streak'},
    {'key': 'monthly_machine', 'name': 'Monthly Machine', 'desc': 'Consistent month performance'},
    {'key': 'half_year_hero', 'name': 'Half-Year Hero', 'desc': '6 months continuous gym'},
    {'key': 'loyal_member', 'name': 'Loyal Member', 'desc': 'Longstanding member loyalty'},
    {'key': 'attendance_master', 'name': 'Attendance Master', 'desc': 'Top tier attendance streak'},
    {'key': 'rising_star', 'name': 'Rising Star', 'desc': 'Fastest progression rate'},
    {'key': 'elite_member', 'name': 'Elite Member', 'desc': 'Elite training milestones'},
    {'key': 'never_miss_gym', 'name': 'Never Miss Gym', 'desc': 'Unbroken training consistency'},
    {'key': 'gymos_legend', 'name': 'GymOS Legend', 'desc': 'Ultimate gym legend status'},
  ];

  int _xpForLevel(int lvl) {
    int sum = 0;
    for (int i = 1; i < lvl; i++) {
      sum += (100 * pow(i, 1.25)).floor();
    }
    return sum;
  }

  int _levelForXp(int xp) {
    int lvl = 1;
    while (lvl < 99 && _xpForLevel(lvl + 1) <= xp) {
      lvl++;
    }
    return lvl;
  }

  String _calcTitle(int lvl, Set<String> badges) {
    final hasAll = badges.length >= 15;
    final hasNeverMiss = badges.contains('never_miss_gym');
    final has365 = badges.contains('club_365');

    if (lvl >= 99 && hasAll) return '👑 Immortal Titan';
    if (lvl >= 99 && hasNeverMiss) return '⚡ Absolute Titan';
    if (lvl >= 99 && has365) return '🏆 Eternal Titan';
    if (lvl >= 99) return '🌟 Apex Legend';
    if (lvl >= 90) return '💎 Golden Master';
    if (lvl >= 75) return '⚔️ Silver Gladiator';
    if (lvl >= 50) return '🛡️ Bronze Titan';
    if (lvl >= 25) return '🔥 Steel Warrior';
    if (lvl >= 10) return '⚡ Iron Challenger';
    return '🌱 Novice Lifter';
  }

  @override
  void initState() {
    super.initState();
    _xpController = TextEditingController(text: '0');
    _loadProfile();
  }

  @override
  void dispose() {
    _xpController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final client = AdminSupabaseService.client;
      final memberId = widget.member['id'];

      final achRes = await client.from('member_achievements').select('*').eq('member_id', memberId).maybeSingle();
      final badgesRes = await client.from('member_badge_status').select('*').eq('member_id', memberId);

      if (mounted) {
        setState(() {
          if (achRes != null) {
            _level = achRes['current_level'] as int? ?? 1;
            _xp = achRes['current_xp'] as int? ?? 0;
            _title = achRes['current_title']?.toString() ?? '🌱 Novice Lifter';
          }
          _unlockedBadges = (badgesRes as List)
              .where((b) => b['is_unlocked'] == true)
              .map((b) => b['badge_key'].toString())
              .toSet();
          _xpController.text = _xp.toString();
          _title = _calcTitle(_level, _unlockedBadges);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading gamification: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onLevelChanged(int newLvl) {
    setState(() {
      _level = newLvl.clamp(1, 99);
      _xp = _xpForLevel(_level);
      _xpController.text = _xp.toString();
      _title = _calcTitle(_level, _unlockedBadges);
    });
  }

  void _onXpChanged(String text) {
    final parsed = int.tryParse(text);
    if (parsed != null && parsed >= 0) {
      setState(() {
        _xp = parsed;
        _level = _levelForXp(_xp);
        _title = _calcTitle(_level, _unlockedBadges);
      });
    }
  }

  void _maxOut99() {
    setState(() {
      _level = 99;
      _xp = 31192;
      _xpController.text = '31192';
      _unlockedBadges = _availableBadges.map((b) => b['key']!).toSet();
      _title = '👑 Immortal Titan';
    });
  }

  void _resetLevel1() {
    setState(() {
      _level = 1;
      _xp = 0;
      _xpController.text = '0';
      _unlockedBadges.clear();
      _title = '🌱 Novice Lifter';
    });
  }

  Future<void> _saveGamification() async {
    setState(() => _saving = true);
    try {
      final client = AdminSupabaseService.client;
      await client.rpc('admin_update_member_gamification', params: {
        'p_member_id': widget.member['id'],
        'p_level': _level,
        'p_xp': _xp,
        'p_unlocked_badges': _unlockedBadges.toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Gamification updated: Level $_level, $_xp XP, Title: $_title, ${_unlockedBadges.length} Badges unlocked!'),
            backgroundColor: AdminTheme.success,
          ),
        );
        widget.onSaveSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save gamification: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AdminTheme.primary));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Banner: Current Rank & Badges Count
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AdminTheme.primary.withValues(alpha: 0.15),
                  Colors.purple.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AdminTheme.primary,
                  child: Text(
                    '$_level',
                    style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(_title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              '${_unlockedBadges.length} / 15 Badges',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber[900]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Total Cumulative XP: ${NumberFormat('#,###').format(_xp)} XP • Dynamic Level Sync Active',
                        style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      icon: const Icon(Icons.military_tech_rounded, size: 18),
                      label: const Text('Max Out Level 99'),
                      onPressed: _maxOut99,
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reset Level 1'),
                      onPressed: _resetLevel1,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Bi-directional Controls Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Level & Experience Bi-directional Synchronization', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                const SizedBox(height: 6),
                Text('Adjusting Level automatically recalculates cumulative XP. Adjusting XP dynamically recalculates the exact Level and Title.', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                const SizedBox(height: 18),

                // Level Slider & Stepper
                Row(
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.remove_rounded),
                      onPressed: _level > 1 ? () => _onLevelChanged(_level - 1) : null,
                    ),
                    Expanded(
                      child: Slider(
                        value: _level.toDouble(),
                        min: 1,
                        max: 99,
                        divisions: 98,
                        label: 'Level $_level',
                        activeColor: AdminTheme.primary,
                        onChanged: (val) => _onLevelChanged(val.round()),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _level < 99 ? () => _onLevelChanged(_level + 1) : null,
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AdminTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Level: $_level', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // XP Input Field
                TextField(
                  controller: _xpController,
                  keyboardType: TextInputType.number,
                  onChanged: _onXpChanged,
                  decoration: const InputDecoration(
                    labelText: 'Total Cumulative XP',
                    prefixIcon: Icon(Icons.bolt_rounded, color: Colors.amber),
                    helperText: 'Enter exact XP to dynamically compute level, or use the slider above.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 15 Badges Arsenal
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Badges Arsenal (15 Official Badges)', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                    Text('Toggle switch to unlock or lock', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _availableBadges.map((badge) {
                    final isUnlocked = _unlockedBadges.contains(badge['key']);
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          if (isUnlocked) {
                            _unlockedBadges.remove(badge['key']);
                          } else {
                            _unlockedBadges.add(badge['key']!);
                          }
                          _title = _calcTitle(_level, _unlockedBadges);
                        });
                      },
                      child: Container(
                        width: 260,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isUnlocked ? AdminTheme.success.withValues(alpha: 0.08) : AdminTheme.backgroundColor(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isUnlocked ? AdminTheme.success.withValues(alpha: 0.4) : AdminTheme.borderColor(context),
                            width: isUnlocked ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isUnlocked ? AdminTheme.success : Colors.grey.withValues(alpha: 0.3),
                              child: Icon(
                                isUnlocked ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    badge['name']!,
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isUnlocked ? AdminTheme.success : AdminTheme.textColor(context)),
                                  ),
                                  Text(
                                    badge['desc']!,
                                    style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: isUnlocked,
                              activeThumbColor: AdminTheme.success,
                              onChanged: (val) {
                                setState(() {
                                  if (val) {
                                    _unlockedBadges.add(badge['key']!);
                                  } else {
                                    _unlockedBadges.remove(badge['key']);
                                  }
                                  _title = _calcTitle(_level, _unlockedBadges);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Updating Member Gamification...' : 'Save Gamification & Badges Changes', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              onPressed: _saving ? null : _saveGamification,
            ),
          ),
        ],
      ),
    );
  }
}

// --- 2. USER ATTENDANCE MANAGER (MEMBER OR STAFF) ---
class _UserAttendanceManager extends StatefulWidget {
  final dynamic gymId;
  final Map<String, dynamic> target;
  final bool isStaff;
  final Function(Map<String, dynamic>? existingLog, VoidCallback reload) onUpsertRequested;

  const _UserAttendanceManager({
    required this.gymId,
    required this.target,
    required this.isStaff,
    required this.onUpsertRequested,
  });

  @override
  State<_UserAttendanceManager> createState() => _UserAttendanceManagerState();
}

class _UserAttendanceManagerState extends State<_UserAttendanceManager> {
  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      final client = AdminSupabaseService.client;
      final targetId = widget.target['id'];
      final field = widget.isStaff ? 'staff_id' : 'member_id';

      final res = await client
          .from('attendance_logs')
          .select('*')
          .eq(field, targetId)
          .order('date', ascending: false)
          .order('created_at', ascending: false)
          .limit(60);

      if (mounted) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(res);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading attendance logs: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteLog(Map<String, dynamic> log) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Attendance Entry?'),
        content: Text('Are you sure you want to delete attendance record for date ${log['date']} (${log['status']})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final client = AdminSupabaseService.client;
      await client.rpc('admin_delete_attendance', params: {'p_attendance_id': log['id']});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Attendance entry deleted successfully.'), backgroundColor: AdminTheme.success),
        );
        _loadLogs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AdminTheme.primary));
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Attendance History (${_logs.length} sessions)', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Mark / Update Attendance'),
                onPressed: () => widget.onUpsertRequested(null, _loadLogs),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_logs.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text('No attendance records logged yet.', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary),
                      onPressed: () => widget.onUpsertRequested(null, _loadLogs),
                      child: const Text('Log First Attendance'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _logs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final status = log['status']?.toString() ?? 'Present';
                  final date = log['date']?.toString() ?? '-';
                  final checkIn = log['check_in'] != null ? DateFormat('hh:mm a').format(DateTime.parse(log['check_in']).toLocal()) : '--:--';
                  final checkOut = log['check_out'] != null ? DateFormat('hh:mm a').format(DateTime.parse(log['check_out']).toLocal()) : '--:--';
                  final workHours = log['working_hours']?.toString();

                  Color stColor = AdminTheme.success;
                  if (status == 'Absent') stColor = AdminTheme.danger;
                  if (status == 'Late') stColor = Colors.orange;
                  if (status == 'Half Day') stColor = Colors.purple;

                  return Container(
                    decoration: BoxDecoration(
                      color: AdminTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdminTheme.borderColor(context)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: stColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text(status, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: stColor)),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(date, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                            Text('In: $checkIn  •  Out: $checkOut', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context))),
                          ],
                        ),
                        if (workHours != null && double.tryParse(workHours) != null && double.parse(workHours) > 0) ...[
                          const SizedBox(width: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: Text('$workHours hrs', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ),
                        ],
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.edit_calendar_rounded, size: 18, color: AdminTheme.primary),
                          tooltip: 'Edit Record',
                          onPressed: () => widget.onUpsertRequested(log, _loadLogs),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AdminTheme.danger),
                          tooltip: 'Delete Record',
                          onPressed: () => _deleteLog(log),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// --- 3. MEMBER MEMBERSHIP & FINANCIALS EDITOR ---
class _MemberMembershipEditor extends StatefulWidget {
  final dynamic gymId;
  final Map<String, dynamic> member;
  final List<Map<String, dynamic>> gymPlans;
  final Function(double newPaid, double newPending, String newStatus) onSaveSuccess;

  const _MemberMembershipEditor({
    required this.gymId,
    required this.member,
    required this.gymPlans,
    required this.onSaveSuccess,
  });

  @override
  State<_MemberMembershipEditor> createState() => _MemberMembershipEditorState();
}

class _MemberMembershipEditorState extends State<_MemberMembershipEditor> {
  bool _loading = true;
  bool _saving = false;

  String? _selectedPlanId;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  late TextEditingController _totalController;
  late TextEditingController _paidController;
  late TextEditingController _pendingController;
  late TextEditingController _discountController;
  String _memberStatus = 'Active';

  @override
  void initState() {
    super.initState();
    _totalController = TextEditingController();
    _paidController = TextEditingController();
    _pendingController = TextEditingController();
    _discountController = TextEditingController(text: '0');
    _loadMembership();
  }

  @override
  void dispose() {
    _totalController.dispose();
    _paidController.dispose();
    _pendingController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _loadMembership() async {
    try {
      final client = AdminSupabaseService.client;
      final res = await client
          .from('member_memberships')
          .select('*')
          .eq('member_id', widget.member['id'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _memberStatus = widget.member['status']?.toString() ?? 'Active';
          _selectedPlanId = widget.member['membership_plan_id']?.toString() ?? res?['plan_id']?.toString();

          if (res != null) {
            if (res['start_date'] != null) {
              final parsedStart = DateTime.tryParse(res['start_date'].toString());
              if (parsedStart != null) _startDate = parsedStart;
            }
            if (res['end_date'] != null) {
              final parsedEnd = DateTime.tryParse(res['end_date'].toString());
              if (parsedEnd != null) _endDate = parsedEnd;
            }
            _totalController.text = (res['total_amount'] ?? '0').toString();
            _paidController.text = (res['paid_amount'] ?? '0').toString();
            _pendingController.text = (res['pending_amount'] ?? '0').toString();
          } else {
            final rec = widget.member['total_received_amount'] ?? 0.0;
            final pend = widget.member['pending_amount'] ?? 0.0;
            final disc = widget.member['discount_amount'] ?? 0.0;
            _totalController.text = ((double.tryParse(rec.toString()) ?? 0.0) + (double.tryParse(pend.toString()) ?? 0.0)).toString();
            _paidController.text = rec.toString();
            _pendingController.text = pend.toString();
            _discountController.text = disc.toString();
          }
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading membership: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _recalcPending() {
    final total = double.tryParse(_totalController.text) ?? 0.0;
    final paid = double.tryParse(_paidController.text) ?? 0.0;
    final disc = double.tryParse(_discountController.text) ?? 0.0;
    final calcPending = max(0.0, total - paid - disc);
    _pendingController.text = calcPending.toStringAsFixed(0);
  }

  Future<void> _saveMembership() async {
    setState(() => _saving = true);
    try {
      final client = AdminSupabaseService.client;
      final total = double.tryParse(_totalController.text.trim()) ?? 0.0;
      final paid = double.tryParse(_paidController.text.trim()) ?? 0.0;
      final pending = double.tryParse(_pendingController.text.trim()) ?? 0.0;
      final discount = double.tryParse(_discountController.text.trim()) ?? 0.0;

      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      final res = await client.rpc('admin_update_member_membership_and_finance', params: {
        'p_member_id': widget.member['id'],
        'p_plan_id': _selectedPlanId,
        'p_start_date': startStr,
        'p_end_date': endStr,
        'p_total': total,
        'p_paid': paid,
        'p_pending': pending,
        'p_discount': discount,
        'p_status': _memberStatus,
      });

      final data = res as Map<String, dynamic>? ?? {};
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Membership & Financials updated successfully!'), backgroundColor: AdminTheme.success),
        );
        final newPayStatus = data['payment_status']?.toString() ?? (pending <= 0 ? 'Paid' : 'Partial');
        widget.onSaveSuccess(paid, pending, newPayStatus);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save membership: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AdminTheme.primary));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Membership Plan & Financial Accounting Controls', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
          const SizedBox(height: 4),
          Text('Update membership dates, selected plan, payments, pending balances, and member account status.', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
          const SizedBox(height: 20),

          // Plan & Status Selection Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan & Account Status', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: widget.gymPlans.any((p) => p['id'].toString() == _selectedPlanId) ? _selectedPlanId : null,
                  hint: const Text('Select Membership Plan'),
                  items: widget.gymPlans.map((p) {
                    final title = p['title']?.toString() ?? 'Plan';
                    final price = p['price']?.toString() ?? '0';
                    return DropdownMenuItem(value: p['id'].toString(), child: Text('$title (₹$price)'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedPlanId = val;
                        final matched = widget.gymPlans.firstWhere((p) => p['id'].toString() == val, orElse: () => {});
                        if (matched['price'] != null) {
                          _totalController.text = matched['price'].toString();
                          _recalcPending();
                        }
                      });
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Assigned Membership Plan', prefixIcon: Icon(Icons.card_membership_rounded)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: ['Active', 'Pending Activation', 'Inactive', 'Blocked'].contains(_memberStatus) ? _memberStatus : 'Active',
                  items: ['Active', 'Pending Activation', 'Inactive', 'Blocked'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _memberStatus = val);
                  },
                  decoration: const InputDecoration(labelText: 'Member Account Status', prefixIcon: Icon(Icons.shield_outlined)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Membership Duration / Dates Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Membership Validity Dates', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_month_rounded, color: AdminTheme.primary),
                        title: const Text('Start Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat('yyyy-MM-dd').format(_startDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        trailing: OutlinedButton(
                          child: const Text('Pick'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _startDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setState(() => _startDate = picked);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_busy_rounded, color: AdminTheme.danger),
                        title: const Text('End Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat('yyyy-MM-dd').format(_endDate), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        trailing: OutlinedButton(
                          child: const Text('Pick'),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _endDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setState(() => _endDate = picked);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Financial Figures Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment & Fee Breakdown', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _totalController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _recalcPending(),
                        decoration: const InputDecoration(labelText: 'Total Plan Fee (₹)', prefixIcon: Icon(Icons.currency_rupee_rounded)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _paidController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _recalcPending(),
                        decoration: const InputDecoration(labelText: 'Amount Paid (₹)', prefixIcon: Icon(Icons.check_circle_outline_rounded)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pendingController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Pending Balance (₹)', prefixIcon: Icon(Icons.pending_actions_rounded)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _discountController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _recalcPending(),
                        decoration: const InputDecoration(labelText: 'Discount Applied (₹)', prefixIcon: Icon(Icons.discount_outlined)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.success, foregroundColor: Colors.white),
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving...' : 'Save Membership & Financial Details', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              onPressed: _saving ? null : _saveMembership,
            ),
          ),
        ],
      ),
    );
  }
}

// --- 4. STAFF INFO & SALARY EDITOR ---
class _StaffInfoEditor extends StatefulWidget {
  final Map<String, dynamic> staff;
  final VoidCallback onSaved;

  const _StaffInfoEditor({required this.staff, required this.onSaved});

  @override
  State<_StaffInfoEditor> createState() => _StaffInfoEditorState();
}

class _StaffInfoEditorState extends State<_StaffInfoEditor> {
  bool _saving = false;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _roleController;
  late TextEditingController _salaryController;
  late TextEditingController _salaryDueController;
  late TextEditingController _shiftController;
  String _status = 'Active';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.staff['full_name']);
    _phoneController = TextEditingController(text: widget.staff['phone'] == '-' ? '' : widget.staff['phone']);
    _emailController = TextEditingController(text: widget.staff['email'] == '-' ? '' : widget.staff['email']);
    _roleController = TextEditingController(text: widget.staff['role']);
    _salaryController = TextEditingController(text: (widget.staff['salary'] ?? 0).toString());
    _salaryDueController = TextEditingController(text: (widget.staff['salary_due'] ?? 0).toString());
    _shiftController = TextEditingController(text: widget.staff['shift'] == '-' ? '' : widget.staff['shift']);
    _status = widget.staff['status'] ?? 'Active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    _salaryController.dispose();
    _salaryDueController.dispose();
    _shiftController.dispose();
    super.dispose();
  }

  Future<void> _saveStaff() async {
    setState(() => _saving = true);
    try {
      final client = AdminSupabaseService.client;
      final salary = double.tryParse(_salaryController.text.trim()) ?? 0.0;
      final due = double.tryParse(_salaryDueController.text.trim()) ?? 0.0;

      await client.from('staff').update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'role': _roleController.text.trim(),
        'salary': salary,
        'salary_due': due,
        'shift': _shiftController.text.trim(),
        'status': _status,
      }).eq('id', widget.staff['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Staff information updated!'), backgroundColor: AdminTheme.success),
        );
        widget.staff['full_name'] = _nameController.text.trim();
        widget.staff['phone'] = _phoneController.text.trim();
        widget.staff['email'] = _emailController.text.trim();
        widget.staff['role'] = _roleController.text.trim();
        widget.staff['salary'] = salary;
        widget.staff['salary_due'] = due;
        widget.staff['shift'] = _shiftController.text.trim();
        widget.staff['status'] = _status;
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update staff: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Staff Profile & Compensation Management', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
          const SizedBox(height: 16),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Staff Name', prefixIcon: Icon(Icons.person_rounded))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_rounded)))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_rounded)))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: _roleController, decoration: const InputDecoration(labelText: 'Role (e.g. Trainer, Manager)', prefixIcon: Icon(Icons.work_rounded)))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _shiftController, decoration: const InputDecoration(labelText: 'Shift (e.g. Morning, Evening)', prefixIcon: Icon(Icons.access_time_rounded)))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: _salaryController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Salary (₹ / month)', prefixIcon: Icon(Icons.currency_rupee_rounded)))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _salaryDueController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Salary Due (₹)', prefixIcon: Icon(Icons.pending_actions_rounded)))),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: ['Active', 'Suspended', 'Inactive'].contains(_status) ? _status : 'Active',
            items: ['Active', 'Suspended', 'Inactive'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _status = val);
            },
            decoration: const InputDecoration(labelText: 'Staff Status', prefixIcon: Icon(Icons.shield_outlined)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving...' : 'Save Staff Changes', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              onPressed: _saving ? null : _saveStaff,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// STAFF SALARY & PAYMENTS MANAGER (FULL ADMIN CONTROL)
// ============================================================================
class _StaffSalaryManager extends StatefulWidget {
  final String gymId;
  final Map<String, dynamic> staff;
  final VoidCallback onUpdated;

  const _StaffSalaryManager({
    required this.gymId,
    required this.staff,
    required this.onUpdated,
  });

  @override
  State<_StaffSalaryManager> createState() => _StaffSalaryManagerState();
}

class _StaffSalaryManagerState extends State<_StaffSalaryManager> {
  bool _loading = true;
  List<Map<String, dynamic>> _salaryHistory = [];
  double _totalPaid = 0.0;
  late double _baseSalary;
  late double _salaryDue;

  @override
  void initState() {
    super.initState();
    _baseSalary = double.tryParse(widget.staff['salary']?.toString() ?? '0') ?? 0.0;
    _salaryDue = double.tryParse(widget.staff['salary_due']?.toString() ?? '0') ?? 0.0;
    _loadSalaryHistory();
  }

  Future<void> _loadSalaryHistory() async {
    setState(() => _loading = true);
    if (!AdminSupabaseService.isInitialized) {
      setState(() => _loading = false);
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final staffName = (widget.staff['full_name'] ?? widget.staff['name'] ?? '').toString().trim().toLowerCase();
      final staffId = widget.staff['id']?.toString() ?? '';

      // Query finance_transactions with Category Salary
      final txRes = await client
          .from('finance_transactions')
          .select()
          .eq('gym_id', widget.gymId)
          .eq('category', 'Salary')
          .order('transaction_date', ascending: false);

      final List<Map<String, dynamic>> matched = [];
      double paidSum = 0.0;

      for (var row in (txRes as List)) {
        final map = Map<String, dynamic>.from(row);
        final notes = (map['notes'] ?? '').toString().toLowerCase();
        final refId = (map['reference_id'] ?? '').toString();

        final matches = (staffName.isNotEmpty && notes.contains(staffName)) ||
            (staffId.isNotEmpty && (refId == staffId || notes.contains(staffId)));

        if (matches) {
          matched.add(map);
          paidSum += double.tryParse(map['amount']?.toString() ?? '0') ?? 0.0;
        }
      }

      if (mounted) {
        setState(() {
          _salaryHistory = matched;
          _totalPaid = paidSum;
          _baseSalary = double.tryParse(widget.staff['salary']?.toString() ?? '0') ?? 0.0;
          _salaryDue = double.tryParse(widget.staff['salary_due']?.toString() ?? '0') ?? 0.0;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading staff salary history: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showRecordPaymentDialog() {
    final amountCtrl = TextEditingController(text: _salaryDue > 0 ? _salaryDue.toStringAsFixed(0) : _baseSalary.toStringAsFixed(0));
    final notesCtrl = TextEditingController(text: 'Salary Payment - ${widget.staff['full_name'] ?? 'Staff'}');
    String paymentType = 'Salary Payment';
    String paymentMethod = 'Cash';
    DateTime paymentDate = DateTime.now();
    bool deductFromDue = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AdminTheme.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                CircleAvatar(backgroundColor: Colors.green.withValues(alpha: 0.1), child: const Icon(Icons.add_card_rounded, color: Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: Text('Record Salary Payment (${widget.staff['full_name'] ?? 'Staff'})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee_rounded)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: paymentType,
                    decoration: const InputDecoration(labelText: 'Payment Type', prefixIcon: Icon(Icons.category_rounded)),
                    items: ['Salary Payment', 'Salary Advance', 'Bonus', 'Incentive', 'Overtime']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => paymentType = val ?? paymentType),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment Method', prefixIcon: Icon(Icons.payment_rounded)),
                    items: ['Cash', 'UPI', 'Bank Transfer', 'Cheque', 'Other']
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => paymentMethod = val ?? paymentMethod),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_rounded, size: 20),
                    title: Text('Date: ${DateFormat('dd MMM yyyy').format(paymentDate)}', style: GoogleFonts.inter(fontSize: 13)),
                    trailing: TextButton(
                      child: const Text('Change'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: paymentDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setDialogState(() => paymentDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes / Remarks', prefixIcon: Icon(Icons.notes_rounded)),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Deduct from Salary Due balance', style: GoogleFonts.inter(fontSize: 13)),
                    value: deductFromDue,
                    onChanged: (val) => setDialogState(() => deductFromDue = val ?? true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  if (amt <= 0) return;
                  Navigator.pop(ctx);
                  try {
                    final staffName = widget.staff['full_name'] ?? 'Staff';
                    await AdminSupabaseService.client.from('finance_transactions').insert({
                      'gym_id': widget.gymId,
                      'type': 'Expense',
                      'category': 'Salary',
                      'amount': amt,
                      'payment_method': paymentMethod,
                      'transaction_date': paymentDate.toIso8601String(),
                      'expense_date': DateFormat('yyyy-MM-dd').format(paymentDate),
                      'entry_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                      'reference_id': widget.staff['id'],
                      'notes': '$paymentType - $staffName: ${notesCtrl.text.trim()}',
                      'created_by_info': 'Super Admin',
                    });

                    if (deductFromDue) {
                      final newDue = max(0.0, _salaryDue - amt);
                      await AdminSupabaseService.client.from('staff').update({'salary_due': newDue}).eq('id', widget.staff['id']);
                      widget.staff['salary_due'] = newDue;
                      setState(() => _salaryDue = newDue);
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('✅ ₹$amt recorded as $paymentType!'), backgroundColor: AdminTheme.success),
                      );
                      _loadSalaryHistory();
                      widget.onUpdated();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error recording salary: $e'), backgroundColor: AdminTheme.danger),
                      );
                    }
                  }
                },
                child: const Text('Record Payment'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditPaymentDialog(Map<String, dynamic> tx) {
    final oldAmt = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
    final amountCtrl = TextEditingController(text: oldAmt.toString());
    final notesCtrl = TextEditingController(text: (tx['notes'] ?? '').toString());
    String paymentMethod = tx['payment_method']?.toString() ?? 'Cash';
    DateTime paymentDate = DateTime.tryParse(tx['transaction_date']?.toString() ?? '') ?? DateTime.now();
    bool adjustDueDifference = true;

    final methodList = ['Cash', 'UPI', 'Bank Transfer', 'Cheque', 'Other'];
    if (!methodList.contains(paymentMethod)) {
      methodList.add(paymentMethod);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AdminTheme.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                CircleAvatar(backgroundColor: Colors.blue.withValues(alpha: 0.1), child: const Icon(Icons.edit_note_rounded, color: Colors.blue)),
                const SizedBox(width: 12),
                Text('Edit Salary Entry', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount Paid (₹)', prefixIcon: Icon(Icons.currency_rupee_rounded)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment Method', prefixIcon: Icon(Icons.payment_rounded)),
                    items: methodList.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) => setDialogState(() => paymentMethod = val ?? paymentMethod),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_rounded, size: 20),
                    title: Text('Date: ${DateFormat('dd MMM yyyy').format(paymentDate)}', style: GoogleFonts.inter(fontSize: 13)),
                    trailing: TextButton(
                      child: const Text('Change'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: paymentDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setDialogState(() => paymentDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes / Remarks', prefixIcon: Icon(Icons.notes_rounded)),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Auto-adjust difference in Salary Due', style: GoogleFonts.inter(fontSize: 13)),
                    value: adjustDueDifference,
                    onChanged: (val) => setDialogState(() => adjustDueDifference = val ?? true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
                onPressed: () async {
                  final newAmt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  if (newAmt <= 0) return;
                  Navigator.pop(ctx);
                  try {
                    await AdminSupabaseService.client.from('finance_transactions').update({
                      'amount': newAmt,
                      'payment_method': paymentMethod,
                      'transaction_date': paymentDate.toIso8601String(),
                      'expense_date': DateFormat('yyyy-MM-dd').format(paymentDate),
                      'notes': notesCtrl.text.trim(),
                    }).eq('id', tx['id']);

                    if (adjustDueDifference) {
                      final delta = newAmt - oldAmt; // if paid more, due reduces
                      final newDue = max(0.0, _salaryDue - delta);
                      await AdminSupabaseService.client.from('staff').update({'salary_due': newDue}).eq('id', widget.staff['id']);
                      widget.staff['salary_due'] = newDue;
                      setState(() => _salaryDue = newDue);
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Salary entry updated!'), backgroundColor: AdminTheme.success),
                      );
                      _loadSalaryHistory();
                      widget.onUpdated();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating entry: $e'), backgroundColor: AdminTheme.danger),
                      );
                    }
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deletePayment(Map<String, dynamic> tx) {
    final amt = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Salary Payment?'),
        content: Text('Are you sure you want to delete this salary payment entry of ₹$amt? This will reverse the expense and restore ₹$amt back to Salary Due.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await AdminSupabaseService.client.from('finance_transactions').delete().eq('id', tx['id']);
                final newDue = _salaryDue + amt;
                await AdminSupabaseService.client.from('staff').update({'salary_due': newDue}).eq('id', widget.staff['id']);
                widget.staff['salary_due'] = newDue;
                setState(() => _salaryDue = newDue);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✅ Salary entry deleted. Restored ₹$amt to due.'), backgroundColor: Colors.red),
                  );
                  _loadSalaryHistory();
                  widget.onUpdated();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting entry: $e'), backgroundColor: AdminTheme.danger),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditBaseAndDueDialog() {
    final baseCtrl = TextEditingController(text: _baseSalary.toStringAsFixed(0));
    final dueCtrl = TextEditingController(text: _salaryDue.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Adjust Salary & Due Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: baseCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base Salary (₹ / month)', prefixIcon: Icon(Icons.currency_rupee_rounded))),
            const SizedBox(height: 12),
            TextField(controller: dueCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Salary Due (₹)', prefixIcon: Icon(Icons.pending_actions_rounded))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary, foregroundColor: Colors.white),
            onPressed: () async {
              final newBase = double.tryParse(baseCtrl.text.trim()) ?? _baseSalary;
              final newDue = double.tryParse(dueCtrl.text.trim()) ?? _salaryDue;
              Navigator.pop(ctx);
              try {
                await AdminSupabaseService.client.from('staff').update({
                  'salary': newBase,
                  'salary_due': newDue,
                }).eq('id', widget.staff['id']);
                widget.staff['salary'] = newBase;
                widget.staff['salary_due'] = newDue;
                setState(() {
                  _baseSalary = newBase;
                  _salaryDue = newDue;
                });
                widget.onUpdated();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Base salary and due balance updated!'), backgroundColor: AdminTheme.success),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating: $e'), backgroundColor: AdminTheme.danger),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Salary Summary Cards
          Row(
            children: [
              Expanded(
                child: _summaryCard('Monthly Base Salary', currency.format(_baseSalary), Icons.account_balance_wallet_rounded, Colors.indigo, onEdit: _showEditBaseAndDueDialog),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryCard('Salary Due Balance', currency.format(_salaryDue), Icons.pending_actions_rounded, _salaryDue > 0 ? Colors.red : Colors.grey, onEdit: _showEditBaseAndDueDialog),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryCard('Total Paid History', currency.format(_totalPaid), Icons.check_circle_rounded, AdminTheme.success),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Salary Payment Entries (${_salaryHistory.length})', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Record Salary Payment / Advance', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _showRecordPaymentDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: _salaryHistory.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 48, color: AdminTheme.mutedTextColor(context)),
                          const SizedBox(height: 12),
                          Text('No salary payments recorded yet for ${widget.staff['full_name'] ?? 'this staff member'}.',
                              style: GoogleFonts.inter(color: AdminTheme.secondaryTextColor(context))),
                          const SizedBox(height: 8),
                          Text('Click "+ Record Salary Payment / Advance" above to log a payment.',
                              style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _salaryHistory.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = _salaryHistory[index];
                      final amt = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
                      final txDateStr = tx['transaction_date']?.toString();
                      final txDate = txDateStr != null ? DateTime.tryParse(txDateStr) : null;
                      final dateFormatted = txDate != null ? DateFormat('dd MMM yyyy, hh:mm a').format(txDate) : 'Unknown date';
                      final notes = tx['notes'] ?? '';
                      final method = tx['payment_method'] ?? 'Cash';
                      final isAdvance = notes.toString().toLowerCase().contains('advance');

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isAdvance ? Colors.orange.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                          child: Icon(isAdvance ? Icons.timelapse_rounded : Icons.check_circle_rounded,
                              color: isAdvance ? Colors.orange : Colors.green, size: 20),
                        ),
                        title: Row(
                          children: [
                            Text(isAdvance ? 'Salary Advance' : 'Salary Payment', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AdminTheme.borderColor(context), borderRadius: BorderRadius.circular(4)),
                              child: Text(method, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date: $dateFormatted', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                            if (notes.isNotEmpty)
                              Text('Notes: $notes', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context))),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(currency.format(amt), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Edit / Update this payment entry',
                              onPressed: () => _showEditPaymentDialog(tx),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              tooltip: 'Delete entry & restore salary due',
                              onPressed: () => _deletePayment(tx),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color, {VoidCallback? onEdit}) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context))),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 16),
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

