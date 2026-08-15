import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/google_drive_service.dart';

class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});
  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isActionInProgress = false;
  String _actionMessage = '';
  double _actionProgress = 0.0;

  // Stats
  String _dbSizeStr = '—';
  int _totalRecords = 0;
  String _lastBackupTime = 'Never';
  int _backupCount = 0;

  // Backup History
  List<Map<String, dynamic>> _backupsList = [];

  // Google Drive
  bool _driveConnected = false;
  String _driveEmail = '';
  final _driveTokenController = TextEditingController();
  final _driveFolderController = TextEditingController();

  // Restore
  final _restoreJsonController = TextEditingController();

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _driveTokenController.dispose();
    _driveFolderController.dispose();
    _restoreJsonController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadDatabaseStats(),
      _loadBackupHistory(),
      _loadDriveStatus(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadDatabaseStats() async {
    try {
      if (!AdminSupabaseService.isInitialized) return;
      final client = AdminSupabaseService.client;
      
      final gyms = await client.from('gyms').select('id');
      final members = await client.from('members').select('id');
      final staff = await client.from('staff').select('id');
      int txCount = 0;
      try {
        final tx = await client.from('finance_transactions').select('id');
        txCount = (tx as List).length;
      } catch (_) {}

      final total = (gyms as List).length + (members as List).length + (staff as List).length + txCount;
      final double estimatedKb = 5.2 + (total * 1.1);
      final sizeStr = estimatedKb > 1024
          ? '${(estimatedKb / 1024).toStringAsFixed(1)} MB'
          : '${estimatedKb.toStringAsFixed(1)} KB';

      if (mounted) {
        setState(() {
          _dbSizeStr = sizeStr;
          _totalRecords = total;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  Future<void> _loadBackupHistory() async {
    try {
      if (!AdminSupabaseService.isInitialized) return;
      final client = AdminSupabaseService.client;
      final res = await client
          .from('database_backups')
          .select('id, backup_name, size_bytes, total_records, table_counts, status, drive_url, created_at')
          .order('created_at', ascending: false)
          .limit(50);

      final list = List<Map<String, dynamic>>.from(res);
      if (mounted) {
        setState(() {
          _backupsList = list;
          _backupCount = list.length;
          if (list.isNotEmpty) {
            final cAt = DateTime.tryParse(list.first['created_at'] ?? '');
            _lastBackupTime = cAt != null ? _formatRelativeTime(cAt) : 'Never';
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading backups: $e');
    }
  }

  Future<void> _loadDriveStatus() async {
    await GoogleDriveService.loadCredentials();
    if (GoogleDriveService.isConnected) {
      final user = await GoogleDriveService.getUserInfo();
      if (mounted) {
        setState(() {
          _driveConnected = true;
          _driveEmail = user?['emailAddress'] ?? 'Connected';
        });
      }
    }
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM yyyy').format(dt);
  }

  String _formatBytes(int bytes) {
    if (bytes > 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  // ============== ACTIONS ==============

  /// 1. BACKUP NOW — calls save_daily_backup() RPC
  Future<void> _backupNow() async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Creating full database backup...';
      _actionProgress = 0.1;
    });

    try {
      final client = AdminSupabaseService.client;

      setState(() => _actionProgress = 0.3);
      final result = await client.rpc('save_daily_backup');
      setState(() => _actionProgress = 0.7);

      final data = result as Map<String, dynamic>? ?? {};
      final success = data['success'] == true;
      final sizeReadable = data['size_readable'] ?? '—';
      final totalRecords = data['total_records'] ?? 0;
      final backupId = data['backup_id'];

      // Upload to Google Drive if connected
      String? driveUrl;
      if (GoogleDriveService.isConnected && backupId != null) {
        setState(() {
          _actionMessage = 'Uploading to Google Drive...';
          _actionProgress = 0.8;
        });
        try {
          // Fetch the backup data for Drive upload
          final backupRow = await client
              .from('database_backups')
              .select('backup_data')
              .eq('id', backupId)
              .single();
          final backupJson = jsonEncode(backupRow['backup_data']);
          final fileName = 'gymos_backup_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';
          driveUrl = await GoogleDriveService.uploadBackup(backupJson: backupJson, fileName: fileName);
          if (driveUrl != null) {
            await client.from('database_backups').update({'drive_url': driveUrl}).eq('id', backupId);
          }
        } catch (e) {
          debugPrint('Drive upload warning: $e');
        }
      }

      setState(() => _actionProgress = 1.0);
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? '✅ Backup complete! $totalRecords records ($sizeReadable)${driveUrl != null ? " • Uploaded to Drive" : ""}'
                : '⚠️ Backup finished with warnings'),
            backgroundColor: success ? AdminTheme.success : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
        _loadBackupHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  /// 2. DOWNLOAD BACKUP — downloads JSON file via browser
  Future<void> _downloadBackup(Map<String, dynamic> backup) async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Preparing download...';
    });

    try {
      final client = AdminSupabaseService.client;
      final res = await client
          .from('database_backups')
          .select('backup_data')
          .eq('id', backup['id'])
          .single();

      final jsonStr = jsonEncode(res['backup_data']);
      final bytes = utf8.encode(jsonStr);
      final blob = html.Blob([bytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final fileName = 'gymos_backup_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';

      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📥 Downloaded $fileName'), backgroundColor: AdminTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  /// 3. RESTORE FROM JSON — 1-click full database import
  Future<void> _restoreFromJson(String jsonStr) async {
    final confirm = await showAdminConfirmDialog(
      context,
      title: '⚠️ Full Database Restore',
      message: 'This will MERGE/OVERWRITE your entire database with the backup data. All existing records will be updated or new ones inserted. This action cannot be undone.\n\nAre you absolutely sure?',
      confirmText: 'Yes, Restore Everything',
      isDangerous: true,
      icon: Icons.warning_amber_rounded,
    );
    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Restoring full database...';
      _actionProgress = 0.2;
    });

    try {
      final backupData = jsonDecode(jsonStr);
      setState(() => _actionProgress = 0.4);

      final client = AdminSupabaseService.client;
      final result = await client.rpc('full_database_import', params: {'p_backup': backupData});
      setState(() => _actionProgress = 0.9);

      final data = result as Map<String, dynamic>? ?? {};
      final tablesRestored = data['tables_restored'] ?? 0;
      final recordsInserted = data['records_inserted'] ?? 0;
      final errors = List<String>.from(data['errors'] ?? []);

      setState(() => _actionProgress = 1.0);
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        setState(() => _isActionInProgress = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('🎉 Database Restored!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tables Restored: $tablesRestored'),
                Text('Records Inserted: $recordsInserted'),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Warnings (${errors.length}):', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ...errors.map((e) => Text('• $e', style: const TextStyle(fontSize: 12))),
                ],
              ],
            ),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  /// 4. DELETE BACKUP
  Future<void> _deleteBackup(Map<String, dynamic> backup) async {
    final confirm = await showAdminConfirmDialog(
      context,
      title: 'Delete Backup?',
      message: 'This will permanently delete "${backup['backup_name']}". This cannot be undone.',
      confirmText: 'Delete',
      isDangerous: true,
    );
    if (confirm != true) return;

    try {
      await AdminSupabaseService.client.from('database_backups').delete().eq('id', backup['id']);
      _loadBackupHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup deleted'), backgroundColor: AdminTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  /// 5. RESTORE FROM BACKUP HISTORY
  Future<void> _restoreFromBackup(Map<String, dynamic> backup) async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Loading backup data...';
    });

    try {
      final client = AdminSupabaseService.client;
      final res = await client
          .from('database_backups')
          .select('backup_data')
          .eq('id', backup['id'])
          .single();

      setState(() => _isActionInProgress = false);
      final jsonStr = jsonEncode(res['backup_data']);
      await _restoreFromJson(jsonStr);
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading backup: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  /// 6. CONNECT GOOGLE DRIVE
  Future<void> _connectDrive() async {
    final token = _driveTokenController.text.trim();
    if (token.isEmpty) return;

    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Connecting to Google Drive...';
    });

    await GoogleDriveService.saveCredentials(
      accessToken: token,
      folderId: _driveFolderController.text.trim().isNotEmpty ? _driveFolderController.text.trim() : null,
    );

    final valid = await GoogleDriveService.testConnection();
    if (valid) {
      final user = await GoogleDriveService.getUserInfo();
      if (mounted) {
        setState(() {
          _driveConnected = true;
          _driveEmail = user?['emailAddress'] ?? 'Connected';
          _isActionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('☁️ Connected as ${_driveEmail}'), backgroundColor: AdminTheme.success),
        );
      }
    } else {
      await GoogleDriveService.disconnect();
      if (mounted) {
        setState(() {
          _driveConnected = false;
          _isActionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid token. Please check and try again.'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  Future<void> _disconnectDrive() async {
    await GoogleDriveService.disconnect();
    setState(() {
      _driveConnected = false;
      _driveEmail = '';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Drive disconnected'), backgroundColor: AdminTheme.success),
      );
    }
  }

  // ============== BUILD ==============

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);

    if (_isLoading) {
      return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 6));
    }

    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: AnimationLimiter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: AnimationConfiguration.toStaggeredList(
                duration: const Duration(milliseconds: 300),
                childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Database & Backup Center', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                            const SizedBox(height: 4),
                            Text('Enterprise daily backup, 1-click restore & Google Drive sync',
                                style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _backupNow,
                        icon: const Icon(Icons.backup_rounded, size: 18),
                        label: Text('Backup Now', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdminTheme.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Stats cards
                  _buildStatsRow(context),
                  const SizedBox(height: 24),

                  // Tabbed content
                  _buildTabs(context),
                ],
              ),
            ),
          ),
        ),

        // Action overlay
        if (_isActionInProgress) _buildActionOverlay(context),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final stats = [
      {'icon': Icons.storage_rounded, 'color': AdminTheme.primary, 'label': 'Database Size', 'value': _dbSizeStr},
      {'icon': Icons.dataset_rounded, 'color': AdminTheme.teal, 'label': 'Total Records', 'value': NumberFormat('#,##0').format(_totalRecords)},
      {'icon': Icons.schedule_rounded, 'color': AdminTheme.info, 'label': 'Last Backup', 'value': _lastBackupTime},
      {'icon': Icons.backup_rounded, 'color': AdminTheme.success, 'label': 'Backups Saved', 'value': '$_backupCount'},
      {'icon': Icons.cloud_done_rounded, 'color': _driveConnected ? AdminTheme.success : Colors.grey, 'label': 'Google Drive', 'value': _driveConnected ? 'Connected' : 'Not Connected'},
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: stats.map((s) {
        return Container(
          width: AdminResponsive.isMobile(context) ? double.infinity : 200,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AdminTheme.cardColor(context),
            borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
            border: Border.all(color: AdminTheme.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: (s['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(s['icon'] as IconData, size: 22, color: s['color'] as Color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['label'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                    const SizedBox(height: 2),
                    Text(s['value'] as String, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AdminTheme.textColor(context))),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '📦 Backup History'),
              Tab(text: '📤 Upload & Restore'),
              Tab(text: '☁️ Google Drive'),
            ],
          ),
          SizedBox(
            height: 500,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBackupHistoryTab(context),
                _buildRestoreTab(context),
                _buildDriveTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============== TAB 1: BACKUP HISTORY ==============

  Widget _buildBackupHistoryTab(BuildContext context) {
    if (_backupsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.backup_outlined, size: 48, color: AdminTheme.mutedTextColor(context)),
            const SizedBox(height: 12),
            Text('No backups yet', style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.mutedTextColor(context))),
            const SizedBox(height: 8),
            Text('Click "Backup Now" to create your first backup', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _backupsList.length,
      separatorBuilder: (_, __) => Divider(color: AdminTheme.borderColor(context), height: 1),
      itemBuilder: (context, index) {
        final b = _backupsList[index];
        final cAt = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
        final sizeBytes = b['size_bytes'] as int? ?? 0;
        final totalRecords = b['total_records'] as int? ?? 0;
        final driveUrl = b['drive_url'] as String?;
        final status = b['status'] as String? ?? 'Success';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: (status == 'Success' ? AdminTheme.success : Colors.orange).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  status == 'Success' ? Icons.check_circle_rounded : Icons.warning_rounded,
                  size: 20,
                  color: status == 'Success' ? AdminTheme.success : Colors.orange,
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b['backup_name'] as String? ?? 'Unnamed Backup',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('${_formatBytes(sizeBytes)}  •  $totalRecords records  •  ${DateFormat('dd MMM yyyy, hh:mm a').format(cAt)}',
                            style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                        if (driveUrl != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.cloud_done_rounded, size: 14, color: AdminTheme.success),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download_rounded, size: 18),
                    color: AdminTheme.primary,
                    onPressed: () => _downloadBackup(b),
                  ),
                  IconButton(
                    tooltip: 'Restore from this backup',
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    color: AdminTheme.info,
                    onPressed: () => _restoreFromBackup(b),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: AdminTheme.danger,
                    onPressed: () => _deleteBackup(b),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ============== TAB 2: UPLOAD & RESTORE ==============

  Widget _buildRestoreTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.info.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.info.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AdminTheme.info, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '1-Click Full Restore: Paste your GymOS Enterprise Backup JSON below. This will restore ALL tables including gyms, members, staff, subscriptions, payments, settings — everything!',
                    style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.info),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // JSON input
          Text('Backup JSON Payload', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          const SizedBox(height: 8),
          TextField(
            controller: _restoreJsonController,
            maxLines: 12,
            style: GoogleFonts.firaCode(fontSize: 11, color: AdminTheme.textColor(context)),
            decoration: InputDecoration(
              hintText: 'Paste your full backup JSON here...\n\nExample: {"_meta": {"version": "2.0", ...}, "gyms": [...], "members": [...], ...}',
              hintStyle: GoogleFonts.firaCode(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
              filled: true,
              fillColor: AdminTheme.surfaceColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AdminTheme.borderColor(context)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Actions row
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  final text = _restoreJsonController.text.trim();
                  if (text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please paste backup JSON first'), backgroundColor: Colors.orange),
                    );
                    return;
                  }
                  _restoreFromJson(text);
                },
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: Text('Restore Full Database', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _restoreJsonController.text = data!.text!;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('📋 Pasted from clipboard'), backgroundColor: AdminTheme.success),
                    );
                  }
                },
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste from Clipboard'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _restoreJsonController.clear(),
                icon: const Icon(Icons.clear_rounded, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Migration guide
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.cardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🚀 Server Migration Guide', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                const SizedBox(height: 12),
                _migrationStep('1', 'On OLD server → Click "Backup Now" to create fresh backup'),
                _migrationStep('2', 'Download the backup JSON file'),
                _migrationStep('3', 'On NEW server → Run the full_backup_system.sql in SQL Editor'),
                _migrationStep('4', 'Paste the backup JSON above → Click "Restore Full Database"'),
                _migrationStep('5', 'All gyms, members, staff, payments, settings restored in 1 click!'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _migrationStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: AdminTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(num, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AdminTheme.primary))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)))),
        ],
      ),
    );
  }

  // ============== TAB 3: GOOGLE DRIVE ==============

  Widget _buildDriveTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (_driveConnected ? AdminTheme.success : Colors.orange).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (_driveConnected ? AdminTheme.success : Colors.orange).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  _driveConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: _driveConnected ? AdminTheme.success : Colors.orange,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _driveConnected ? 'Google Drive Connected' : 'Google Drive Not Connected',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _driveConnected ? AdminTheme.success : Colors.orange),
                      ),
                      if (_driveConnected)
                        Text(_driveEmail, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                    ],
                  ),
                ),
                if (_driveConnected)
                  OutlinedButton(
                    onPressed: _disconnectDrive,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AdminTheme.danger),
                    ),
                    child: Text('Disconnect', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.danger)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (!_driveConnected) ...[
            Text('Connect Google Drive', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
            const SizedBox(height: 8),
            Text(
              'Backups will automatically upload to your Google Drive when connected. Use a Google OAuth2 Access Token to connect.',
              style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
            ),
            const SizedBox(height: 20),

            Text('OAuth2 Access Token', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
            const SizedBox(height: 8),
            TextField(
              controller: _driveTokenController,
              maxLines: 3,
              obscureText: true,
              style: GoogleFonts.firaCode(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Paste your Google OAuth2 access token here...',
                hintStyle: GoogleFonts.firaCode(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                filled: true,
                fillColor: AdminTheme.surfaceColor(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            Text('Drive Folder ID (Optional)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
            const SizedBox(height: 8),
            TextField(
              controller: _driveFolderController,
              style: GoogleFonts.firaCode(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'e.g. 1ABC_xyz... (leave empty for root folder)',
                hintStyle: GoogleFonts.firaCode(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                filled: true,
                fillColor: AdminTheme.surfaceColor(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _connectDrive,
              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text('Connect Google Drive', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
            const SizedBox(height: 24),

            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📖 How to get Google Drive Access Token', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                  const SizedBox(height: 10),
                  _migrationStep('1', 'Go to Google OAuth Playground: https://developers.google.com/oauthplayground'),
                  _migrationStep('2', 'Select "Drive API v3" → check "https://www.googleapis.com/auth/drive.file"'),
                  _migrationStep('3', 'Click "Authorize APIs" → Sign in with Google'),
                  _migrationStep('4', 'Click "Exchange authorization code for tokens"'),
                  _migrationStep('5', 'Copy the "Access Token" and paste it above'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============== ACTION OVERLAY ==============

  Widget _buildActionOverlay(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AdminTheme.cardColor(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(color: AdminTheme.primary, strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                _actionMessage,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _actionProgress > 0 ? _actionProgress : null,
                  backgroundColor: AdminTheme.borderColor(context),
                  color: AdminTheme.primary,
                  minHeight: 6,
                ),
              ),
              if (_actionProgress > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${(_actionProgress * 100).toInt()}%', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
