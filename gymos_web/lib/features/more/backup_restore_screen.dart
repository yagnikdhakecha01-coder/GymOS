import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/services/supabase_service.dart';
import '../../core/repository/gym_repository.dart';
import '../authentication/auth_viewmodel.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _autoBackup = true;
  String _backupLocation = 'Supabase Cloud';
  String _lastBackupDate = 'Never';
  String _lastBackupSize = '0.00 MB';
  bool _isProcessing = false;
  double _progressValue = 0.0;
  String _processMessage = '';
  List<Map<String, dynamic>> _pastBackups = [];
  bool _loadingBackups = true;

  @override
  void initState() {
    super.initState();
    _loadSyncSettings();
    _fetchBackups();
  }

  Future<void> _loadSyncSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoBackup = prefs.getBool('backup_auto_backup') ?? true;
      _backupLocation = prefs.getString('backup_location') ?? 'Supabase Cloud';
    });
  }

  Future<void> _saveSyncSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool('backup_$key', value);
    } else if (value is String) {
      await prefs.setString('backup_$key', value);
    }
  }

  Future<void> _fetchBackups() async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];

    if (gymId == null || !SupabaseService.isInitialized) {
      setState(() {
        _loadingBackups = false;
      });
      return;
    }

    try {
      final List res = await SupabaseService.client
          .from('gym_backups')
          .select('id, backup_name, created_at, size_bytes, provider')
          .eq('gym_id', gymId)
          .order('created_at', ascending: false);

      setState(() {
        _pastBackups = List<Map<String, dynamic>>.from(res);
        if (_pastBackups.isNotEmpty) {
          final first = _pastBackups.first;
          final dateStr = DateTime.tryParse(first['created_at']) ?? DateTime.now();
          _lastBackupDate = DateFormat('dd MMM yyyy, hh:mm a').format(dateStr);
          final size = first['size_bytes'] ?? 0;
          _lastBackupSize = (size / (1024 * 1024)).toStringAsFixed(2) + ' MB';
          _backupLocation = first['provider'] ?? 'Supabase Cloud';
        } else {
          _lastBackupDate = 'Never';
          _lastBackupSize = '0.00 MB';
        }
        _loadingBackups = false;
      });
    } catch (e) {
      debugPrint('Error fetching backups: $e');
      setState(() {
        _loadingBackups = false;
      });
    }
  }

  Future<void> _startBackup() async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final repo = Provider.of<GymRepository>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final userId = authVm.currentUser?.id;

    if (gymId == null || userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Please log in and select a gym first.'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _progressValue = 0.1;
      _processMessage = 'Preparing backup database...';
    });

    try {
      // 1. Gather all gym data from repository
      final backupData = {
        'members': repo.getMembers().map((m) => m.toJson()).toList(),
        'trial_members': repo.getTrialMembers().map((m) => m.toJson()).toList(),
        'staff': repo.getStaff().map((s) => s.toJson()).toList(),
        'workouts': repo.getWorkouts().map((w) => w.toJson()).toList(),
        'diets': repo.getDiets().map((d) => d.toJson()).toList(),
        'memberships': repo.getMemberships().map((m) => m.toJson()).toList(),
        'transactions': repo.getTransactions().map((t) => t.toJson()).toList(),
        'attendance': repo.getAttendance().map((a) => a.toJson()).toList(),
        'goals': repo.getGoals().map((g) => g.toJson()).toList(),
        'custom_fields': repo.getCustomFields().map((c) => c.toJson()).toList(),
        'attendance_settings': repo.getAttendanceSettings()?.toJson(),
        'display_sessions': repo.getDisplaySessions().map((d) => d.toJson()).toList(),
      };

      setState(() {
        _progressValue = 0.4;
        _processMessage = 'Compressing member logs...';
      });

      final jsonStr = jsonEncode(backupData);
      final sizeBytes = utf8.encode(jsonStr).length;

      setState(() {
        _progressValue = 0.7;
        _processMessage = 'Uploading to $_backupLocation...';
      });

      if (SupabaseService.isInitialized) {
        final backupName = 'Backup ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}';
        await SupabaseService.client.from('gym_backups').insert({
          'gym_id': gymId,
          'backup_name': backupName,
          'backup_data': backupData,
          'size_bytes': sizeBytes,
          'created_by': userId,
          'provider': _backupLocation,
        });
      } else {
        throw Exception('Supabase is not initialized');
      }

      setState(() {
        _progressValue = 1.0;
        _processMessage = 'Finalizing cloud sync...';
      });

      await Future.delayed(const Duration(milliseconds: 300));
      await _fetchBackups();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Database backup completed successfully!'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Backup failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _startRestore(Map<String, dynamic> backupSummary) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Restore'),
        content: Text('Are you sure you want to restore the database to the state of ${backupSummary['backup_name']}? This will overwrite existing records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Restoring Database'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                'Restoring files and reloading lists, please do not close the app...',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );

    try {
      // 1. Fetch full backup data payload
      final response = await SupabaseService.client
          .from('gym_backups')
          .select('backup_data')
          .eq('id', backupSummary['id'])
          .single();

      final backupData = response['backup_data'] as Map<String, dynamic>;
      final client = SupabaseService.client;

      // 2. Perform restoration logic sequentially (to respect foreign keys)
      if (backupData.containsKey('attendance_settings') && backupData['attendance_settings'] != null) {
        await client.from('attendance_settings').upsert(backupData['attendance_settings']);
      }
      if (backupData.containsKey('memberships') && backupData['memberships'] != null) {
        await client.from('membership_plans').upsert(List<Map<String, dynamic>>.from(backupData['memberships']));
      }
      if (backupData.containsKey('workouts') && backupData['workouts'] != null) {
        await client.from('workout_plans').upsert(List<Map<String, dynamic>>.from(backupData['workouts']));
      }
      if (backupData.containsKey('diets') && backupData['diets'] != null) {
        await client.from('diet_plans').upsert(List<Map<String, dynamic>>.from(backupData['diets']));
      }
      if (backupData.containsKey('staff') && backupData['staff'] != null) {
        await client.from('staff').upsert(List<Map<String, dynamic>>.from(backupData['staff']));
      }
      if (backupData.containsKey('members') && backupData['members'] != null) {
        await client.from('members').upsert(List<Map<String, dynamic>>.from(backupData['members']));
      }
      if (backupData.containsKey('goals') && backupData['goals'] != null) {
        await client.from('goals').upsert(List<Map<String, dynamic>>.from(backupData['goals']));
      }
      if (backupData.containsKey('custom_fields') && backupData['custom_fields'] != null) {
        await client.from('custom_fields').upsert(List<Map<String, dynamic>>.from(backupData['custom_fields']));
      }
      if (backupData.containsKey('display_sessions') && backupData['display_sessions'] != null) {
        await client.from('attendance_displays').upsert(List<Map<String, dynamic>>.from(backupData['display_sessions']));
      }
      if (backupData.containsKey('transactions') && backupData['transactions'] != null) {
        await client.from('transactions').upsert(List<Map<String, dynamic>>.from(backupData['transactions']));
      }
      if (backupData.containsKey('attendance') && backupData['attendance'] != null) {
        await client.from('attendance_logs').upsert(List<Map<String, dynamic>>.from(backupData['attendance']));
      }

      // 3. Trigger full repository refresh
      final repo = Provider.of<GymRepository>(context, listen: false);
      await repo.syncAllFromSupabase();

      if (mounted) {
        Navigator.pop(context); // Close restoring dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Restored successfully from ${backupSummary['backup_name']}!'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close restoring dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Restore failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Backup & Restore'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary details
              CustomCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.cloud_upload_outlined, color: Colors.teal, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Last Backup Details', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              const SizedBox(height: 2),
                              Text('Size: $_lastBackupSize • Location: $_backupLocation', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Last Sync:', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                        Text(_lastBackupDate, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Backup settings switch & location selector
              Text('SYNC SETTINGS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              CustomCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: AppTheme.primary,
                      title: Text('Auto Backup Daily', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      subtitle: Text('Backup automatically at 02:00 AM', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                      value: _autoBackup,
                      onChanged: (val) {
                        setState(() => _autoBackup = val);
                        _saveSyncSetting('auto_backup', val);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text('Storage Provider', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      subtitle: Text(_backupLocation, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: const Text('Select Storage Provider'),
                            children: ['Supabase Cloud', 'Google Drive', 'iCloud', 'Dropbox', 'Local Storage'].map((loc) {
                              return SimpleDialogOption(
                                onPressed: () {
                                  setState(() => _backupLocation = loc);
                                  _saveSyncSetting('location', loc);
                                  Navigator.pop(context);
                                },
                                child: Text(loc),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Backup Now action
              if (_isProcessing)
                CustomCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: _progressValue, color: AppTheme.primary),
                      const SizedBox(height: 10),
                      Text(
                        _processMessage,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _startBackup,
                    icon: const Icon(Icons.backup),
                    label: Text('Backup Database Now', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ),
              const SizedBox(height: 24),

              // Previous backups list
              Text('PAST RESTORE POINTS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              if (_loadingBackups)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                )
              else if (_pastBackups.isEmpty)
                CustomCard(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No past restore points found.',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _pastBackups.length,
                  itemBuilder: (context, index) {
                    final item = _pastBackups[index];
                    final dateStr = DateTime.tryParse(item['created_at'] ?? '') ?? DateTime.now();
                    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(dateStr);
                    final size = item['size_bytes'] ?? 0;
                    final sizeStr = (size / (1024 * 1024)).toStringAsFixed(2) + ' MB';
                    final provider = item['provider'] ?? 'Supabase Cloud';

                    return CustomCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceGray,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.history_toggle_off, color: AppTheme.textSecondary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['backup_name'] ?? formattedDate, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                                Text('Size: $sizeStr • Provider: $provider', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              minimumSize: const Size(0, 32),
                              side: const BorderSide(color: AppTheme.primary),
                            ),
                            onPressed: () => _startRestore(item),
                            child: Text('Restore', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
