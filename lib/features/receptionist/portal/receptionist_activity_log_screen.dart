import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';
import '../receptionist_viewmodel.dart';

class ReceptionistActivityLogScreen extends StatefulWidget {
  final String gymId;
  const ReceptionistActivityLogScreen({super.key, required this.gymId});

  @override
  State<ReceptionistActivityLogScreen> createState() => _ReceptionistActivityLogScreenState();
}

class _ReceptionistActivityLogScreenState extends State<ReceptionistActivityLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final res = await SupabaseService.client
          .from('activity_logs')
          .select()
          .eq('gym_id', widget.gymId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching receptionist activity logs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Activity Log',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
            onPressed: _fetchLogs,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _logs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_edu_rounded, size: 48, color: AppTheme.textSecondary.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'No logged activities.',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final date = DateTime.parse(log['created_at'] as String);
                    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(date.toLocal());
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_getActivityIcon(log['module']), size: 14, color: AppTheme.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  log['action'] ?? '',
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'By: ${log['staff_name']} (${log['staff_role']})',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formattedDate,
                                style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                          if (log['target_member'] != '') ...[
                            const SizedBox(height: 6),
                            Text(
                              'Target Member: ${log['target_member']}',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  IconData _getActivityIcon(String? module) {
    switch (module?.toLowerCase()) {
      case 'members':
        return Icons.person_outline_rounded;
      case 'attendance':
        return Icons.qr_code_scanner_rounded;
      case 'finance':
        return Icons.payments_outlined;
      default:
        return Icons.info_outline;
    }
  }
}
