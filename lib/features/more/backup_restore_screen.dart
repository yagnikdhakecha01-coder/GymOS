import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _autoBackup = true;
  String _backupLocation = 'Google Drive';
  String _lastBackupDate = '15 Jul 2026, 08:30 AM';
  String _lastBackupSize = '2.4 MB';
  bool _isProcessing = false;
  double _progressValue = 0.0;
  String _processMessage = '';

  final List<Map<String, String>> _pastBackups = [
    {'date': '15 Jul 2026, 08:30 AM', 'size': '2.4 MB', 'location': 'Google Drive'},
    {'date': '08 Jul 2026, 08:32 AM', 'size': '2.3 MB', 'location': 'Google Drive'},
    {'date': '01 Jul 2026, 08:30 AM', 'size': '2.2 MB', 'location': 'Local Storage'},
  ];

  Future<void> _startBackup() async {
    setState(() {
      _isProcessing = true;
      _progressValue = 0.0;
      _processMessage = 'Preparing backup database...';
    });

    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      setState(() {
        _progressValue = i / 10.0;
        if (i < 4) {
          _processMessage = 'Compressing member logs...';
        } else if (i < 8) {
          _processMessage = 'Uploading to $_backupLocation...';
        } else {
          _processMessage = 'Finalizing cloud sync...';
        }
      });
    }

    setState(() {
      _isProcessing = false;
      _lastBackupDate = 'Today, ${TimeOfDay.now().format(context)}';
      _lastBackupSize = '2.5 MB';
      _pastBackups.insert(0, {
        'date': _lastBackupDate,
        'size': _lastBackupSize,
        'location': _backupLocation,
      });
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Database backup completed successfully!'), backgroundColor: AppTheme.success),
      );
    }
  }

  Future<void> _startRestore(Map<String, String> backup) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future.delayed(const Duration(seconds: 2), () {
              if (context.mounted) {
                Navigator.pop(context); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Restored successfully from ${backup['date']}!'), backgroundColor: AppTheme.success),
                );
              }
            });
            return AlertDialog(
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
      },
    );
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
                            color: Colors.teal.withValues(alpha: 0.1),
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
                      onChanged: (val) => setState(() => _autoBackup = val),
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
                            children: ['Google Drive', 'iCloud', 'Dropbox', 'Local Storage'].map((loc) {
                              return SimpleDialogOption(
                                onPressed: () {
                                  setState(() => _backupLocation = loc);
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
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pastBackups.length,
                itemBuilder: (context, index) {
                  final item = _pastBackups[index];
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
                              Text(item['date']!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                              Text('Size: ${item['size']} • Provider: ${item['location']}', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
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
