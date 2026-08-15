import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/google_drive_service.dart';

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

  double _totalRevenue = 0.0;
  double _totalExpense = 0.0;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _staff = [];

  String _memberSearch = '';
  String _staffSearch = '';

  // Quick Action States
  late bool _isLocked;
  late String _gymStatus;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _isLocked = widget.gym['is_locked'] == true;
    _gymStatus = widget.gym['status']?.toString() ?? 'Active';
    _loadFinanceData();
    _loadMembersData();
    _loadStaffData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFinanceData() async {
    if (!AdminSupabaseService.isInitialized) {
      setState(() {
        _totalRevenue = 450000.00;
        _totalExpense = 120000.00;
        _transactions = [
          {'type': 'Revenue', 'category': 'Membership', 'amount': 1500.00, 'transaction_date': DateTime.now().toIso8601String(), 'notes': 'Monthly fee'},
          {'type': 'Expense', 'category': 'Rent', 'amount': 35000.00, 'transaction_date': DateTime.now().toIso8601String(), 'notes': 'Monthly Rent'},
        ];
        _loadingFinance = false;
      });
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

      setState(() {
        _totalRevenue = rev;
        _totalExpense = exp;
        _transactions = txList;
        _loadingFinance = false;
      });
    } catch (e) {
      debugPrint('Error loading finance data: $e');
      setState(() => _loadingFinance = false);
    }
  }

  Future<void> _loadMembersData() async {
    if (!AdminSupabaseService.isInitialized) {
      setState(() {
        _members = [
          {'full_name': 'Rahul Sharma', 'email': 'rahul@gmail.com', 'phone': '9876543210', 'membership_name': 'Gold Plan', 'status': 'Active'},
        ];
        _loadingMembers = false;
      });
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final response = await client
          .from('members')
          .select('*, member_memberships(membership_plans(name))')
          .eq('gym_id', widget.gym['id'])
          .order('created_at', ascending: false);

      final membersList = List<Map<String, dynamic>>.from(response);
      setState(() {
        _members = membersList.map((m) {
          final memberships = m['member_memberships'] as List?;
          final activeMem = memberships != null && memberships.isNotEmpty ? memberships.first : null;
          final planName = activeMem != null && activeMem['membership_plans'] != null 
              ? activeMem['membership_plans']['name'] as String? ?? 'No Plan'
              : 'No Plan';

          return {
            'id': m['id'],
            'full_name': m['full_name'] ?? 'Unnamed Member',
            'email': m['email'] ?? '-',
            'phone': m['phone_number'] ?? m['phone'] ?? '-',
            'membership_name': planName,
            'status': m['payment_status'] ?? 'Active',
            'avatar_url': m['avatar_url'] ?? m['photo_url'],
          };
        }).toList();
        _loadingMembers = false;
      });
    } catch (e) {
      debugPrint('Error loading members: $e');
      setState(() => _loadingMembers = false);
    }
  }

  Future<void> _loadStaffData() async {
    if (!AdminSupabaseService.isInitialized) {
      setState(() {
        _staff = [
          {'full_name': 'Vikram Rathore', 'email': 'vikram@fitzone.com', 'phone': '9876543220', 'role': 'Manager', 'salary': 35000.00},
        ];
        _loadingStaff = false;
      });
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final response = await client
          .from('staff')
          .select('*, profiles(*)')
          .eq('gym_id', widget.gym['id'])
          .order('created_at', ascending: false);

      final staffList = List<Map<String, dynamic>>.from(response);
      setState(() {
        _staff = staffList.map((s) {
          final profile = s['profiles'] as Map<String, dynamic>?;
          return {
            'full_name': profile?['full_name'] ?? s['name'] ?? 'Unnamed Staff',
            'email': profile?['email'] ?? '-',
            'phone': profile?['phone_number'] ?? s['phone'] ?? '-',
            'role': s['role'] ?? 'Staff',
            'salary': double.tryParse(s['salary']?.toString() ?? '0') ?? 0.0,
            'avatar_url': profile?['avatar_url'],
          };
        }).toList();
        _loadingStaff = false;
      });
    } catch (e) {
      debugPrint('Error loading staff: $e');
      setState(() => _loadingStaff = false);
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
      setState(() => _isLocked = nextState);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextState ? '🔒 Gym has been LOCKED' : '🔓 Gym has been UNLOCKED'),
          backgroundColor: nextState ? Colors.orange : AdminTheme.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating lock state: $e'), backgroundColor: AdminTheme.danger));
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
      setState(() => _gymStatus = nextStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextStatus == 'Suspended' ? '⏸️ Gym Suspended' : '✅ Gym Activated'),
          backgroundColor: nextStatus == 'Suspended' ? AdminTheme.danger : AdminTheme.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating status: $e'), backgroundColor: AdminTheme.danger));
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

      final backupId = data['backup_id'];
      final totalRecords = data['total_records'] ?? 0;
      final sizeReadable = data['size_readable'] ?? '—';
      final backupJson = jsonEncode(data['backup_json']);

      // Upload to Google Drive if connected
      String? driveUrl;
      String? driveError;
      if (GoogleDriveService.isConnected && backupId != null) {
        try {
          final cleanGymName = gymName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
          final fileName = 'gym_backup_${cleanGymName}_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';
          final uploadRes = await GoogleDriveService.uploadBackup(backupJson: backupJson, fileName: fileName);
          if (uploadRes.success && uploadRes.driveUrl != null) {
            driveUrl = uploadRes.driveUrl;
            await client.from('database_backups').update({'drive_url': driveUrl}).eq('id', backupId);
          } else {
            driveError = uploadRes.error;
          }
        } catch (e) {
          driveError = e.toString();
        }
      }

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AdminTheme.success, size: 24),
                const SizedBox(width: 10),
                Text('📦 $gymName Backup Complete!', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 550,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminTheme.cardColor(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdminTheme.borderColor(context)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Records:', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                            Text('$totalRecords records', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Backup Size:', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                            Text(sizeReadable, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Google Drive:', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                            if (driveUrl != null)
                              InkWell(
                                onTap: () => launchUrl(Uri.parse(driveUrl!)),
                                child: Text('✅ Uploaded (Open File ↗)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AdminTheme.teal)),
                              )
                            else if (driveError != null)
                              Text('⚠️ $driveError', style: GoogleFonts.inter(fontSize: 11, color: Colors.orange))
                            else
                              Text('⚪ Not Connected', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('ℹ️ This backup is saved in "Database & Backup Center" and can be restored or downloaded anytime.',
                      style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                ],
              ),
            ),
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download JSON File'),
                style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary),
                onPressed: () {
                  final bytes = utf8.encode(backupJson);
                  final blob = html.Blob([bytes], 'application/json');
                  final url = html.Url.createObjectUrlFromBlob(blob);
                  final cleanGymName = gymName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
                  final fileName = 'gym_backup_${cleanGymName}_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';
                  final anchor = html.AnchorElement(href: url)
                    ..setAttribute('download', fileName)
                    ..click();
                  html.Url.revokeObjectUrl(url);
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy JSON'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: backupJson));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('📋 Backup JSON copied to clipboard!'), backgroundColor: AdminTheme.success),
                  );
                },
              ),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Delete Gym & Cascade Wipe?'),
        content: const Text(
          'This will AUTO-EXPORT a backup JSON first, then completely remove all gym data across all tables and unlink all accounts. NO dummy accounts will remain.',
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

    try {
      await _exportBackup();
      if (AdminSupabaseService.isInitialized) {
        await AdminSupabaseService.client.rpc('delete_gym_cascade', params: {'p_gym_id': widget.gym['id']});
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Gym auto-exported & completely wiped cleanly!'), backgroundColor: AdminTheme.success),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete error: $e'), backgroundColor: AdminTheme.danger));
    }
  }

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
              'Super Admin Management Portal • Privacy Enforced',
              style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AdminTheme.primary,
          unselectedLabelColor: AdminTheme.secondaryTextColor(context),
          indicatorColor: AdminTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_rounded), text: 'Financials'),
            Tab(icon: Icon(Icons.people_rounded), text: 'Members'),
            Tab(icon: Icon(Icons.badge_rounded), text: 'Staff List'),
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

  Widget _buildFinanceTab(NumberFormat fmt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month/Year Filter Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monthly Profit Summary', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
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
          // Stats Row
          Row(
            children: [
              Expanded(
                child: _statCard('Revenue (${months[_selectedMonth - 1]})', fmt.format(_totalRevenue), Icons.arrow_upward_rounded, AdminTheme.success),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard('Expense (${months[_selectedMonth - 1]})', fmt.format(_totalExpense), Icons.arrow_downward_rounded, Colors.red),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard('Net Profit', fmt.format(_totalRevenue - _totalExpense), Icons.account_balance_wallet_rounded, AdminTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text('Ledger Transactions', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: _transactions.isEmpty
                ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No transactions for selected month.')))
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _transactions.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      final isRev = tx['type'] == 'Revenue';
                      final amt = double.tryParse(tx['amount'].toString()) ?? 0.0;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRev ? AdminTheme.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          child: Icon(isRev ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: isRev ? AdminTheme.success : Colors.red, size: 18),
                        ),
                        title: Text(tx['category'] ?? 'Other', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(tx['notes'] ?? "", style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                        trailing: Text('${isRev ? "+" : "-"}${fmt.format(amt)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: isRev ? AdminTheme.success : Colors.red)),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    final filtered = _members.where((m) => m['full_name'].toString().toLowerCase().contains(_memberSearch.toLowerCase())).toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => _memberSearch = val),
            decoration: InputDecoration(
              hintText: 'Search members by name...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AdminTheme.surfaceColor(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              itemCount: filtered.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                childAspectRatio: 2.2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (context, index) {
                final m = filtered[index];
                return Container(
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminTheme.borderColor(context)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AdminTheme.primary.withValues(alpha: 0.1),
                        child: Text(m['full_name'][0], style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AdminTheme.primary)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(m['full_name'], style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(m['membership_name'], style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context))),
                          ],
                        ),
                      )
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

  Widget _buildStaffTab() {
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
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final s = filtered[index];
                return ListTile(
                  title: Text(s['full_name'], style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  subtitle: Text('${s['role']} • ₹${s['salary']}'),
                );
              },
            ),
          )
        ],
      ),
    );
  }

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
}
