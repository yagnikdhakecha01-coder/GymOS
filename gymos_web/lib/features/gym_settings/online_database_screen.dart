import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/services/supabase_service.dart';

class OnlineDatabaseScreen extends StatefulWidget {
  const OnlineDatabaseScreen({super.key});

  @override
  State<OnlineDatabaseScreen> createState() => _OnlineDatabaseScreenState();
}

class _OnlineDatabaseScreenState extends State<OnlineDatabaseScreen> {
  bool _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    final repo = Provider.of<GymRepository>(context);
    final attQueue = repo.attendanceQueue;
    final crudQueue = repo.crudQueue;

    // Combine queues
    final List<Map<String, dynamic>> combinedQueue = [];
    for (var item in attQueue) {
      combinedQueue.add({
        'id': item['attendance_uuid'],
        'type': 'Attendance Check',
        'action': item['attendance_type'] ?? 'Check In/Out',
        'details': 'Name: ${item['user_name']}\nType: ${item['user_type']}\nTime: ${item['check_in'] ?? ''}',
        'status': item['sync_status'] ?? 'pending',
        'retry_count': item['retry_count'] ?? 0,
        'error': item['error_message'],
        'created_at': item['created_at'],
      });
    }

    for (var item in crudQueue) {
      final table = item['table'] as String;
      final payload = item['payload'] as Map<String, dynamic>;
      
      String label = 'Data Action';
      String details = '';
      
      if (table == 'members') {
        label = 'Member Profile';
        details = 'Name: ${payload['name'] ?? 'Member'}\nPhone: ${payload['phone'] ?? ''}\nAction: ${item['action']?.toUpperCase()}';
      } else if (table == 'staff') {
        label = 'Staff Profile';
        details = 'Name: ${payload['name'] ?? 'Staff'}\nRole: ${payload['role'] ?? ''}\nAction: ${item['action']?.toUpperCase()}';
      } else if (table == 'finance_transactions') {
        label = 'Finance Ledger';
        details = 'Amount: ₹${payload['amount'] ?? 0}\nType: ${payload['type'] ?? ''}\nCategory: ${payload['category'] ?? ''}';
      } else if (table == 'salary_advance_ledger') {
        label = 'Salary Advance';
        details = 'Amount: ₹${payload['advance_amount'] ?? 0}\nReason: ${payload['reason'] ?? ''}';
      } else if (table == 'leave_requests') {
        label = 'Leave Request';
        details = 'Type: ${payload['leave_type'] ?? ''}\nStart: ${payload['start_date'] ?? ''}\nReason: ${payload['reason'] ?? ''}';
      } else if (table == 'rpc_pay_salary_draft') {
        label = 'Pay Salary';
        details = 'Draft ID: ${payload['p_draft_id'] ?? ''}\nPayment: ${payload['p_payment_mode'] ?? ''}';
      } else if (table == 'attendance_settings') {
        label = 'Attendance Settings';
        details = 'Action: UPDATE';
      } else if (table == 'rpc_save_gym_operating_hours') {
        label = 'Save Shift Settings';
        details = 'Mode: ${payload['p_mode'] ?? ''}';
      } else {
        label = table.toUpperCase();
        details = 'Action: ${item['action']?.toUpperCase()}';
      }

      combinedQueue.add({
        'id': item['uuid'],
        'type': label,
        'action': item['action'] ?? 'CRUD',
        'details': details,
        'status': item['sync_status'] ?? 'pending',
        'retry_count': item['retry_count'] ?? 0,
        'error': item['error_message'],
        'created_at': item['created_at'],
      });
    }

    final manualQueue = repo.manualAttendanceQueue;
    for (var entry in manualQueue) {
      combinedQueue.add({
        'id': entry.operationUuid,
        'type': 'Manual Attendance',
        'action': 'INSERT',
        'details': 'Name: ${entry.userName}\nType: ${entry.userType}\nDate: ${entry.date}\nReason: ${entry.reason}',
        'status': entry.syncStatus,
        'retry_count': entry.retryCount,
        'error': entry.errorMessage,
        'created_at': entry.createdAt.toIso8601String(),
      });
    }

    // Sort queue by created_at descending
    combinedQueue.sort((a, b) {
      final tA = a['created_at'] != null ? DateTime.tryParse(a['created_at'].toString()) ?? DateTime.now() : DateTime.now();
      final tB = b['created_at'] != null ? DateTime.tryParse(b['created_at'].toString()) ?? DateTime.now() : DateTime.now();
      return tB.compareTo(tA);
    });

    final pendingCount = combinedQueue.where((item) => item['status'] == 'pending' || item['status'] == 'syncing').length;
    final failedCount = combinedQueue.where((item) => item['status'] == 'failed').length;

    // Sync Health logic
    String syncHealthText = '🟢 Fully Synced';
    Color syncHealthColor = Colors.green;
    if (failedCount > 0) {
      syncHealthText = '🔴 Attention Required';
      syncHealthColor = AppTheme.danger;
    } else if (pendingCount > 0) {
      syncHealthText = '🟡 Syncing';
      syncHealthColor = Colors.amber;
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Online Database Status',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: [
          if (failedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  backgroundColor: AppTheme.danger.withOpacity(0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                label: Text(
                  'Clear Failed',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  await repo.clearFailedQueueOperations();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cleared all failed operations.'),
                        backgroundColor: Colors.black87,
                      ),
                    );
                  }
                },
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
          // Header health card
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: syncHealthColor.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: syncHealthColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: syncHealthColor.withOpacity(0.12),
                        radius: 20,
                        child: Icon(
                          failedCount > 0
                              ? Icons.warning_amber_rounded
                              : (pendingCount > 0 ? Icons.sync_rounded : Icons.check_circle_outline_rounded),
                          color: syncHealthColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sync Health',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              syncHealthText,
                              style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: SupabaseService.isInitialized ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          SupabaseService.isInitialized ? 'ONLINE' : 'OFFLINE',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: SupabaseService.isInitialized ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        title: 'Pending Sync',
                        count: pendingCount,
                        color: Colors.amber,
                        icon: Icons.hourglass_empty_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        title: 'Failed Operations',
                        count: failedCount,
                        color: AppTheme.danger,
                        icon: Icons.error_outline_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Queue Items list
          Expanded(
            child: combinedQueue.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_done_rounded, size: 48, color: Colors.green.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'All data is successfully synced!',
                          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No pending offline operations.',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: combinedQueue.length,
                    itemBuilder: (context, index) {
                      final item = combinedQueue[index];
                      return _buildQueueTile(item);
                    },
                  ),
          ),
        ],
      ),
    ),
  ),
  floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        onPressed: _isSyncing ? null : () => _handleManualSync(repo),
        icon: _isSyncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.sync_rounded, color: Colors.white),
        label: Text(
          _isSyncing ? 'Syncing...' : 'Sync Now',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            radius: 18,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  count.toString(),
                  style: GoogleFonts.inter(fontSize: 20, color: AppTheme.textPrimary, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueTile(Map<String, dynamic> item) {
    final status = item['status'] as String;
    final isFailed = status == 'failed';
    final isSyncing = status == 'syncing';

    Color statusColor = Colors.amber;
    String statusText = 'Pending';
    if (isFailed) {
      statusColor = AppTheme.danger;
      statusText = 'Failed';
    } else if (isSyncing) {
      statusColor = Colors.blue;
      statusText = 'Syncing...';
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isFailed ? AppTheme.danger.withOpacity(0.3) : AppTheme.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.08),
          radius: 20,
          child: Icon(
            isFailed
                ? Icons.error_outline_rounded
                : (isSyncing ? Icons.sync_rounded : Icons.hourglass_empty_rounded),
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          item['type'] ?? 'Data Queue',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Retries: ${item['retry_count']}',
                style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        trailing: isFailed
            ? IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                tooltip: 'Dismiss Operation',
                onPressed: () async {
                  final repo = Provider.of<GymRepository>(context, listen: false);
                  await repo.removeQueueItem(item['id']);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Operation removed from queue.'),
                        backgroundColor: Colors.black87,
                      ),
                    );
                  }
                },
              )
            : null,
        children: [
          Divider(color: AppTheme.border, height: 1),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: AppTheme.surfaceGray.withOpacity(0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payload Details:',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  item['details'] ?? '',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary, height: 1.4),
                ),
                if (isFailed && item['error'] != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Error Message:',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.danger),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.danger.withOpacity(0.12)),
                    ),
                    child: Text(
                      item['error'].toString(),
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.danger, height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleManualSync(GymRepository repo) async {
    setState(() {
      _isSyncing = true;
    });

    final reachable = await repo.isSupabaseReachable();
    if (!reachable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot sync. Connection to Supabase is still down.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      setState(() {
        _isSyncing = false;
      });
      return;
    }

    await repo.triggerBackgroundSync(forceRetry: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline sync completed successfully!'),
          backgroundColor: AppTheme.success,
        ),
      );
    }

    setState(() {
      _isSyncing = false;
    });
  }
}
