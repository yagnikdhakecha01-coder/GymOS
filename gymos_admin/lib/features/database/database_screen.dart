import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/google_drive_service.dart';
import '../../core/services/audit_service.dart';

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

  // Auto-Backup Configuration
  bool _autoBackupEnabled = true;
  int _autoBackupIntervalDays = 1;
  String _autoBackupTime = '02:00';
  bool _autoDriveUpload = true;
  DateTime? _lastAutoBackupRun;
  DateTime? _nextAutoBackupRun;
  int _totalAutoBackups = 0;
  String _autoBackupStatus = 'Ready';
  bool _isSavingAutoSchedule = false;

  // Google Drive
  bool _driveConnected = false;
  String _driveEmail = '';
  final _driveTokenController = TextEditingController();
  final _driveRefreshTokenController = TextEditingController();
  final _driveFolderController = TextEditingController();

  // Diagnostics & Tracker
  List<String> _diagnosticLogs = [];
  bool _isRunningDiagnostics = false;

  // Restore
  final _restoreJsonController = TextEditingController();

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _driveTokenController.dispose();
    _driveRefreshTokenController.dispose();
    _driveFolderController.dispose();
    _restoreJsonController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadDatabaseStats(),
      _loadBackupHistory(),
      _loadAutoBackupConfig(),
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

  Future<void> _loadAutoBackupConfig() async {
    try {
      if (!AdminSupabaseService.isInitialized) return;
      final client = AdminSupabaseService.client;
      final res = await client
          .from('platform_settings')
          .select('value')
          .eq('key', 'auto_backup_config')
          .maybeSingle();

      if (res != null && res['value'] != null) {
        final cfg = res['value'] as Map<String, dynamic>;
        setState(() {
          _autoBackupEnabled = cfg['enabled'] == true;
          _autoBackupIntervalDays = (cfg['interval_days'] as num?)?.toInt() ?? 1;
          _autoBackupTime = cfg['schedule_time']?.toString() ?? '02:00';
          _autoDriveUpload = cfg['auto_drive_upload'] != false;
          _totalAutoBackups = (cfg['total_auto_backups'] as num?)?.toInt() ?? 0;
          _autoBackupStatus = cfg['last_status']?.toString() ?? 'Active';

          if (cfg['last_run_at'] != null) {
            _lastAutoBackupRun = DateTime.tryParse(cfg['last_run_at'].toString());
          }
          if (cfg['next_run_at'] != null) {
            _nextAutoBackupRun = DateTime.tryParse(cfg['next_run_at'].toString());
          } else {
            _nextAutoBackupRun = DateTime.now().add(Duration(days: _autoBackupIntervalDays));
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading auto-backup config: $e');
    }
  }

  Future<void> _saveAutoBackupSchedule() async {
    setState(() => _isSavingAutoSchedule = true);
    try {
      if (!AdminSupabaseService.isInitialized) return;
      final client = AdminSupabaseService.client;

      final nextRun = DateTime.now().add(Duration(days: _autoBackupIntervalDays));

      await client.from('platform_settings').upsert({
        'key': 'auto_backup_config',
        'value': {
          'enabled': _autoBackupEnabled,
          'interval_days': _autoBackupIntervalDays,
          'schedule_time': _autoBackupTime,
          'auto_drive_upload': _autoDriveUpload,
          'last_run_at': _lastAutoBackupRun?.toIso8601String(),
          'next_run_at': nextRun.toIso8601String(),
          'total_auto_backups': _totalAutoBackups,
          'last_status': _autoBackupEnabled ? 'Active (Cloud Scheduled)' : 'Paused',
        },
        'updated_at': DateTime.now().toIso8601String(),
      });

      await AuditService.log(
        action: 'Updated Auto-Backup Schedule',
        category: 'database',
        details: 'Auto-backup: ${_autoBackupEnabled ? "Enabled" : "Disabled"}, Interval: $_autoBackupIntervalDays day(s), Time: $_autoBackupTime, Drive Sync: $_autoDriveUpload',
        metadata: {
          'enabled': _autoBackupEnabled,
          'interval_days': _autoBackupIntervalDays,
          'schedule_time': _autoBackupTime,
          'auto_drive_upload': _autoDriveUpload,
        },
      );

      setState(() {
        _nextAutoBackupRun = nextRun;
        _isSavingAutoSchedule = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Auto-backup schedule saved successfully! Cloud scheduler updated.'),
            backgroundColor: AdminTheme.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSavingAutoSchedule = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save schedule: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  Future<void> _triggerAutoBackupNow() async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Executing Cloud Auto-Backup Job...';
      _actionProgress = 0.2;
    });

    try {
      final client = AdminSupabaseService.client;
      setState(() => _actionProgress = 0.5);

      final result = await client.rpc('trigger_scheduled_auto_backup');
      final data = result as Map<String, dynamic>? ?? {};

      setState(() => _actionProgress = 0.8);

      final backupId = data['backup_id'];
      String? driveMsg;

      if (_autoDriveUpload && GoogleDriveService.isConnected && backupId != null) {
        setState(() => _actionMessage = 'Uploading to Google Drive folder...');
        final backupRow = await client
            .from('database_backups')
            .select('backup_data')
            .eq('id', backupId)
            .single();

        final backupJson = jsonEncode(backupRow['backup_data']);
        final fileName = 'gymos_auto_backup_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';
        final uploadRes = await GoogleDriveService.uploadBackup(backupJson: backupJson, fileName: fileName);

        if (uploadRes.success && uploadRes.driveUrl != null) {
          await client.from('database_backups').update({'drive_url': uploadRes.driveUrl}).eq('id', backupId);
          driveMsg = '☁️ Uploaded to Google Drive!';
        }
      }

      setState(() => _actionProgress = 1.0);
      await Future.delayed(const Duration(milliseconds: 300));

      await _loadBackupHistory();
      await _loadAutoBackupConfig();

      if (mounted) {
        setState(() => _isActionInProgress = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('🎉 Auto-Backup Executed!'),
            content: Text(
              'Automated cloud backup completed successfully!\n\n'
              '• Status: Completed\n'
              '• Next Auto Run: ${_nextAutoBackupRun != null ? DateFormat('MMM d, yyyy — hh:mm a').format(_nextAutoBackupRun!) : "Scheduled"}\n'
              '${driveMsg != null ? "• Drive: $driveMsg\n" : ""}',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            actions: [
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-backup execution failed: $e'), backgroundColor: AdminTheme.danger),
        );
      }
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
      final sizeReadable = data['size_readable'] ?? '—';
      final totalRecords = data['total_records'] ?? 0;
      final backupId = data['backup_id'];

      // Upload to Google Drive if connected
      String? driveUrl;
      String? driveError;
      if (GoogleDriveService.isConnected && backupId != null) {
        setState(() {
          _actionMessage = 'Uploading to Google Drive...';
          _actionProgress = 0.8;
        });
        try {
          final backupRow = await client
              .from('database_backups')
              .select('backup_data')
              .eq('id', backupId)
              .single();
          final backupJson = jsonEncode(backupRow['backup_data']);
          final fileName = 'gymos_backup_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.json';
          final uploadRes = await GoogleDriveService.uploadBackup(backupJson: backupJson, fileName: fileName);
          if (uploadRes.success && uploadRes.driveUrl != null) {
            driveUrl = uploadRes.driveUrl;
            await client.from('database_backups').update({'drive_url': driveUrl}).eq('id', backupId);
          } else {
            driveError = uploadRes.error ?? 'Upload failed';
          }
        } catch (e) {
          driveError = e.toString();
          debugPrint('Drive upload error: $e');
        }
      }

      await AuditService.log(
        action: 'Manual Backup Created',
        category: 'database',
        details: 'Created full backup with $totalRecords records ($sizeReadable)${driveUrl != null ? " and uploaded to Drive" : ""}',
        metadata: {'backup_id': backupId, 'records': totalRecords, 'size': sizeReadable, 'drive_url': driveUrl},
      );

      setState(() => _actionProgress = 1.0);
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        setState(() => _isActionInProgress = false);
        String msg = '✅ Backup complete! $totalRecords records ($sizeReadable)';
        if (driveUrl != null) {
          msg += ' • ☁️ Uploaded to Google Drive!';
        } else if (driveError != null) {
          msg += ' • ⚠️ Drive Error: $driveError';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: driveError != null ? Colors.orange : AdminTheme.success,
            duration: const Duration(seconds: 4),
          ),
        );
        _loadData();
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

  /// 2. RESTORE FROM BACKUP ROW
  Future<void> _restoreFromBackup(Map<String, dynamic> backup) async {
    final name = backup['backup_name'] ?? 'Backup';
    final confirm = await showAdminConfirmDialog(
      context,
      title: '⚠️ Restore from $name',
      message: 'This will restore all records from this backup snapshot. Any conflicting records will be updated.\n\nAre you sure you want to proceed?',
      confirmText: 'Yes, Restore Database',
      isDangerous: true,
      icon: Icons.warning_amber_rounded,
    );
    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Fetching backup snapshot...';
      _actionProgress = 0.2;
    });

    try {
      final client = AdminSupabaseService.client;
      final res = await client
          .from('database_backups')
          .select('backup_data')
          .eq('id', backup['id'])
          .single();

      final backupData = res['backup_data'];
      setState(() {
        _actionMessage = 'Restoring database tables...';
        _actionProgress = 0.5;
      });

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

  /// 3. DOWNLOAD BACKUP
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

  /// 4. RESTORE FROM JSON
  Future<void> _restoreFromJson(String jsonStr) async {
    final confirm = await showAdminConfirmDialog(
      context,
      title: '⚠️ Full Database Restore',
      message: 'This will MERGE/OVERWRITE your entire database with the backup data. All existing records will be updated or new ones inserted.\n\nAre you absolutely sure?',
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

  /// 5. SELECT FROM DRIVE
  Future<void> _selectFromDrive() async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Loading backups from Google Drive...';
    });

    try {
      final token = await GoogleDriveService.getValidAccessToken();
      if (token == null) throw 'Google Drive not connected';

      final files = await GoogleDriveService.listBackups();
      if (mounted) {
        setState(() => _isActionInProgress = false);
        if (files.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No backup files found on Google Drive'), backgroundColor: Colors.orange),
          );
          return;
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Select Backup from Google Drive'),
            content: SizedBox(
              width: 500,
              height: 350,
              child: ListView.separated(
                itemCount: files.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, i) {
                  final f = files[i];
                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file_rounded, color: AdminTheme.primary),
                    title: Text(f['name'] ?? 'Backup', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text('ID: ${f['id']}', style: GoogleFonts.inter(fontSize: 11)),
                    trailing: ElevatedButton(
                      child: const Text('Restore'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        _downloadAndRestoreFromDrive(f['id'], token);
                      },
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  Future<void> _downloadAndRestoreFromDrive(String fileId, String token) async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Downloading backup from Google Drive...';
      _actionProgress = 0.3;
    });

    try {
      final jsonStr = await GoogleDriveService.fetchFileContent(fileId);
      if (jsonStr == null) throw 'Failed to download file from Google Drive';
      _restoreFromJson(jsonStr);
    } catch (e) {
      if (mounted) {
        setState(() => _isActionInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  /// 6. CONNECT DRIVE
  Future<void> _connectDrive() async {
    final accessToken = _driveTokenController.text.trim();
    final refreshToken = _driveRefreshTokenController.text.trim();
    final folderId = _driveFolderController.text.trim();

    if (accessToken.isEmpty && refreshToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an Access Token or Refresh Token'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'Validating Google Drive connection...';
    });

    try {
      await GoogleDriveService.saveCredentials(
        accessToken: accessToken,
        refreshToken: refreshToken.isNotEmpty ? refreshToken : null,
        folderId: folderId.isNotEmpty ? folderId : null,
      );

      final user = await GoogleDriveService.getUserInfo();
      if (user == null) {
        throw 'Invalid token or unable to connect. Please check permissions.';
      }

      final email = user['emailAddress'] ?? 'Connected';
      if (mounted) {
        setState(() {
          _driveConnected = true;
          _driveEmail = email;
          _isActionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Google Drive connected as $email'), backgroundColor: AdminTheme.success),
        );
      }
    } catch (e) {
      await GoogleDriveService.disconnect();
      if (mounted) {
        setState(() {
          _driveConnected = false;
          _isActionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  /// 7. DISCONNECT DRIVE
  Future<void> _disconnectDrive() async {
    await GoogleDriveService.disconnect();
    setState(() {
      _driveConnected = false;
      _driveEmail = '';
      _driveTokenController.clear();
      _driveRefreshTokenController.clear();
      _driveFolderController.clear();
      _diagnosticLogs.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Drive disconnected'), backgroundColor: Colors.orange),
      );
    }
  }

  /// 8. RUN DRIVE DIAGNOSTICS
  Future<void> _runDriveDiagnostics() async {
    setState(() {
      _isRunningDiagnostics = true;
      _diagnosticLogs = ['Starting Google Drive Diagnostic Suite...'];
    });

    try {
      final logs = await GoogleDriveService.runDiagnostics();
      if (mounted) {
        setState(() {
          _diagnosticLogs = logs;
          _isRunningDiagnostics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _diagnosticLogs.add('❌ Diagnostic Exception: $e');
          _isRunningDiagnostics = false;
        });
      }
    }
  }

  /// 9. DELETE BACKUP
  Future<void> _deleteBackup(Map<String, dynamic> backup) async {
    final confirm = await showAdminConfirmDialog(
      context,
      title: 'Delete Backup Snapshot',
      message: 'Are you sure you want to delete this backup snapshot permanently?',
      confirmText: 'Delete',
      isDangerous: true,
    );
    if (confirm != true) return;

    try {
      final client = AdminSupabaseService.client;
      await client.from('database_backups').delete().eq('id', backup['id']);
      _loadBackupHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup deleted'), backgroundColor: Colors.orange),
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

  // ============== BUILD UI ==============

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);

    if (_isLoading) {
      return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 8));
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
                  _buildHeader(context),
                  const SizedBox(height: 24),
                  _buildStatsRow(context),
                  const SizedBox(height: 24),
                  _buildTabs(context),
                ],
              ),
            ),
          ),
        ),
        if (_isActionInProgress) _buildActionOverlay(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Database Management & Auto-Backup',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AdminTheme.textColor(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Enterprise-grade automated cloud backups, Google Drive sync & 1-click restore',
              style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context)),
            ),
          ],
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _backupNow,
          icon: const Icon(Icons.backup_rounded, size: 18),
          label: Text('Backup Now', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AdminTheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final stats = [
      {'icon': Icons.data_usage_rounded, 'color': AdminTheme.primary, 'label': 'Database Size', 'value': _dbSizeStr},
      {'icon': Icons.table_chart_rounded, 'color': AdminTheme.teal, 'label': 'Total Records', 'value': '$_totalRecords'},
      {'icon': Icons.history_rounded, 'color': AdminTheme.info, 'label': 'Last Backup', 'value': _lastBackupTime},
      {
        'icon': Icons.cloud_done_rounded,
        'color': _driveConnected ? AdminTheme.success : Colors.orange,
        'label': 'Google Drive',
        'value': _driveConnected ? 'Connected' : 'Not Connected',
      },
    ];

    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.cardColor(context),
              borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: (s['color'] as Color).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(s['icon'] as IconData, size: 20, color: s['color'] as Color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s['label'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                      const SizedBox(height: 2),
                      Text(s['value'] as String, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AdminTheme.textColor(context))),
                    ],
                  ),
                ),
              ],
            ),
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
              Tab(text: '⏰ Auto-Backup Schedule'),
              Tab(text: '📤 Upload & Restore'),
              Tab(text: '☁️ Google Drive & Tracker'),
            ],
          ),
          SizedBox(
            height: 650,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBackupHistoryTab(context),
                _buildAutoBackupTab(context),
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
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: (status == 'Success' ? AdminTheme.success : Colors.orange).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  status == 'Success' ? Icons.check_circle_rounded : Icons.warning_rounded,
                  size: 20,
                  color: status == 'Success' ? AdminTheme.success : Colors.orange,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b['backup_name'] ?? 'Full Backup',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('dd MMM yyyy, hh:mm a').format(cAt)} • $totalRecords records • ${_formatBytes(sizeBytes)}',
                      style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
                    ),
                  ],
                ),
              ),
              if (driveUrl != null && driveUrl.isNotEmpty)
                IconButton(
                  tooltip: 'View in Google Drive',
                  icon: const Icon(Icons.cloud_done_rounded, size: 18),
                  color: AdminTheme.teal,
                  onPressed: () => launchUrl(Uri.parse(driveUrl)),
                ),
              IconButton(
                tooltip: 'Download Backup JSON',
                icon: const Icon(Icons.download_rounded, size: 18),
                color: AdminTheme.primary,
                onPressed: () => _downloadBackup(b),
              ),
              IconButton(
                tooltip: 'Restore database from this backup',
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
        );
      },
    );
  }

  // ============== TAB 2: AUTO-BACKUP SCHEDULE (NEW) ==============

  Widget _buildAutoBackupTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner: Cloud Scheduler Status
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: (_autoBackupEnabled ? AdminTheme.success : Colors.orange).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: (_autoBackupEnabled ? AdminTheme.success : Colors.orange).withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (_autoBackupEnabled ? AdminTheme.success : Colors.orange).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _autoBackupEnabled ? Icons.schedule_rounded : Icons.pause_circle_rounded,
                    color: _autoBackupEnabled ? AdminTheme.success : Colors.orange,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _autoBackupEnabled ? 'Auto-Backup Scheduler: ACTIVE' : 'Auto-Backup Scheduler: PAUSED',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _autoBackupEnabled ? AdminTheme.success : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AdminTheme.cardColor(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AdminTheme.borderColor(context)),
                            ),
                            child: Text(
                              'Cloud 24x7',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminTheme.teal),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Executes automatically on the backend even if your admin website or PC is closed.',
                        style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoBackupEnabled,
                  activeColor: AdminTheme.success,
                  onChanged: (val) {
                    setState(() => _autoBackupEnabled = val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 3 Metric Cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminTheme.borderColor(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Frequency', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                      const SizedBox(height: 4),
                      Text(
                        _autoBackupIntervalDays == 1 ? 'Every 1 Day (Daily)' : 'Every $_autoBackupIntervalDays Days',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminTheme.borderColor(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Next Scheduled Run', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                      const SizedBox(height: 4),
                      Text(
                        _nextAutoBackupRun != null ? DateFormat('MMM d, hh:mm a').format(_nextAutoBackupRun!) : 'Next Cycle',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AdminTheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminTheme.borderColor(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Google Drive Auto-Sync', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                      const SizedBox(height: 4),
                      Text(
                        _autoDriveUpload && _driveConnected ? 'Enabled (Auto Upload)' : (_autoDriveUpload ? 'Waiting for Drive login' : 'Disabled'),
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _autoDriveUpload && _driveConnected ? AdminTheme.teal : Colors.orange),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Configuration Form Card
          Text('Schedule Configuration', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
          const SizedBox(height: 16),

          // Interval Dropdown
          Text('Backup Frequency (Days)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _autoBackupIntervalDays,
                isExpanded: true,
                dropdownColor: AdminTheme.cardColor(context),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Every 1 Day — Daily Auto-Backup (Recommended)')),
                  DropdownMenuItem(value: 2, child: Text('Every 2 Days')),
                  DropdownMenuItem(value: 3, child: Text('Every 3 Days')),
                  DropdownMenuItem(value: 7, child: Text('Every 7 Days — Weekly Auto-Backup')),
                  DropdownMenuItem(value: 14, child: Text('Every 14 Days — Bi-Weekly')),
                  DropdownMenuItem(value: 30, child: Text('Every 30 Days — Monthly')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _autoBackupIntervalDays = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Preferred Time
          Text('Preferred Execution Time (UTC / IST)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _autoBackupTime,
                isExpanded: true,
                dropdownColor: AdminTheme.cardColor(context),
                items: const [
                  DropdownMenuItem(value: '02:00', child: Text('02:00 AM (Night — Minimal Traffic, Best for backup)')),
                  DropdownMenuItem(value: '04:00', child: Text('04:00 AM (Early Morning)')),
                  DropdownMenuItem(value: '12:00', child: Text('12:00 PM (Noon)')),
                  DropdownMenuItem(value: '18:00', child: Text('06:00 PM (Evening)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _autoBackupTime = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Auto-Upload to Google Drive Checkbox
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_upload_outlined, color: AdminTheme.teal, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto-Upload Backups to Google Drive', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
                      const SizedBox(height: 2),
                      Text(
                        'Whenever auto-backup runs, immediately upload the file to your "GYM OS BACKUP" Google Drive folder.',
                        style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoDriveUpload,
                  activeColor: AdminTheme.teal,
                  onChanged: (val) {
                    setState(() => _autoDriveUpload = val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Save & Test Buttons
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isSavingAutoSchedule ? null : _saveAutoBackupSchedule,
                icon: _isSavingAutoSchedule
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text('Save Auto-Backup Schedule', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                onPressed: _triggerAutoBackupNow,
                icon: const Icon(Icons.flash_on_rounded, size: 18, color: AdminTheme.teal),
                label: Text('Run Auto-Backup Cloud Job Now (Test)', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AdminTheme.teal)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AdminTheme.teal),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============== TAB 3: UPLOAD & RESTORE ==============

  Widget _buildRestoreTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AdminTheme.info, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '1-Click Full Restore: Paste your GymOS Enterprise Backup JSON below. This will restore ALL tables including gyms, members, staff, subscriptions, payments, settings with 0 generated-column warnings!',
                    style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.info),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

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
              ElevatedButton.icon(
                onPressed: GoogleDriveService.isConnected ? _selectFromDrive : null,
                icon: const Icon(Icons.cloud_download_rounded, size: 18),
                label: Text('Select from Google Drive', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminTheme.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
        ],
      ),
    );
  }

  // ============== TAB 4: GOOGLE DRIVE & TRACKER ==============

  Widget _buildDriveTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (_driveConnected ? AdminTheme.success : Colors.orange).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (_driveConnected ? AdminTheme.success : Colors.orange).withValues(alpha: 0.2)),
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
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRunningDiagnostics ? null : _runDriveDiagnostics,
                        icon: _isRunningDiagnostics
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.speed_rounded, size: 16),
                        label: const Text('Test Drive Upload'),
                        style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.teal),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _disconnectDrive,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AdminTheme.danger),
                        ),
                        child: Text('Disconnect', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.danger)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_diagnosticLogs.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminTheme.borderColor(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.terminal_rounded, size: 16, color: AdminTheme.teal),
                      const SizedBox(width: 8),
                      Text('Google Drive Live Diagnostic Tracker', style: GoogleFonts.firaCode(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14, color: Colors.grey),
                        onPressed: () => setState(() => _diagnosticLogs.clear()),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  ..._diagnosticLogs.map((log) {
                    Color logColor = Colors.white70;
                    if (log.contains('✅') || log.contains('SUCCESS')) logColor = Colors.greenAccent;
                    if (log.contains('❌') || log.contains('FAILED') || log.contains('Error')) logColor = Colors.redAccent;
                    if (log.contains('⚠️') || log.contains('Warning')) logColor = Colors.orangeAccent;
                    if (log.contains('🔗')) logColor = Colors.lightBlueAccent;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: SelectableText(
                        log,
                        style: GoogleFonts.firaCode(fontSize: 11, color: logColor, height: 1.4),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (!_driveConnected) ...[
            Text('Connect Google Drive', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
            const SizedBox(height: 8),
            Text(
              'Backups will automatically upload to your Google Drive when connected. Use OAuth2 Access Token & Refresh Token.',
              style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
            ),
            const SizedBox(height: 20),

            Text('OAuth2 Access Token', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
            const SizedBox(height: 8),
            TextField(
              controller: _driveTokenController,
              maxLines: 2,
              style: GoogleFonts.firaCode(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Paste your Google OAuth2 access token here (starts with ya29...)...',
                hintStyle: GoogleFonts.firaCode(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                filled: true,
                fillColor: AdminTheme.surfaceColor(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            Text('Refresh Token (Permanent Lifetime Auto-Renewal)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
            const SizedBox(height: 4),
            Text('Copy from "Refresh token" in Step 2 of OAuth Playground. With this, token will never expire!', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
            const SizedBox(height: 8),
            TextField(
              controller: _driveRefreshTokenController,
              maxLines: 2,
              style: GoogleFonts.firaCode(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Paste Refresh Token (e.g. 1//04ATsM...) for lifetime auto-renewal...',
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
                hintText: 'e.g. 1ABC_xyz... (leave empty to auto-create "GYM OS BACKUP" folder)',
                hintStyle: GoogleFonts.firaCode(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                filled: true,
                fillColor: AdminTheme.surfaceColor(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
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
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ============== ACTION OVERLAY ==============

  Widget _buildActionOverlay(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AdminTheme.cardColor(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, spreadRadius: 5)],
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
