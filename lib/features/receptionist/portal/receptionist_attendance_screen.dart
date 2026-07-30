import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../attendance/owner_scanner_screen.dart';
import '../../../core/services/supabase_service.dart';
import '../receptionist_viewmodel.dart';
import 'widgets/receptionist_restricted_widget.dart';

class ReceptionistAttendanceScreen extends StatefulWidget {
  const ReceptionistAttendanceScreen({super.key});

  @override
  State<ReceptionistAttendanceScreen> createState() => _ReceptionistAttendanceScreenState();
}

class _ReceptionistAttendanceScreenState extends State<ReceptionistAttendanceScreen> {
  List<Map<String, dynamic>> _todayLogs = [];
  bool _isLoadingLogs = false;

  @override
  void initState() {
    super.initState();
    _fetchTodayLogs();
  }

  Future<void> _fetchTodayLogs() async {
    final vm = Provider.of<ReceptionistViewModel>(context, listen: false);
    if (vm.staffRecord == null) return;
    
    setState(() => _isLoadingLogs = true);
    try {
      final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());
      final res = await SupabaseService.client
          .from('attendance_logs')
          .select('*, profiles(full_name)')
          .eq('gym_id', vm.staffRecord!.gymId)
          .eq('date', todayStr)
          .order('check_in', ascending: false);

      if (mounted) {
        setState(() {
          _todayLogs = List<Map<String, dynamic>>.from(res);
          _isLoadingLogs = false;
        });
      }
    } catch (e) {
      print('Error fetching receptionist today logs: $e');
      if (mounted) {
        setState(() => _isLoadingLogs = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<ReceptionistViewModel>(context);
    final canScan = vm.hasPermission('scan_attendance');

    if (!canScan) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: RestrictedAccessWidget(moduleName: 'Scan Attendance'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Scan Attendance',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
            onPressed: _fetchTodayLogs,
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scanner Activation Card
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OwnerQRScannerScreen(isCheckIn: true)),
                      ).then((_) {
                        vm.logActivity('Attendance Scanner Opened', 'attendance');
                        _fetchTodayLogs();
                        vm.fetchDashboardStats();
                      });
                    },
                    child: Container(
                      height: 180,
                      width: 180,
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 64,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tap to Scan QR',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Position member QR code in the viewport to scan automatically',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                  )
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Today's Checked-In Members title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                "Today's Scanned Logs (${_todayLogs.length})",
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
            ),

            // Logs list
            Expanded(
              child: _isLoadingLogs
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _todayLogs.isEmpty
                      ? Center(
                          child: Text(
                            'No members checked in today yet.',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _todayLogs.length,
                          itemBuilder: (context, index) {
                            final log = _todayLogs[index];
                            final profile = log['profiles'] as Map?;
                            final name = profile?['full_name'] ?? 'Member';
                            final time = log['check_in'] != null
                                ? DateFormat('hh:mm a').format(DateTime.parse(log['check_in'] as String).toLocal())
                                : '—';
                            final status = log['status'] ?? 'Present';
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.primary.withOpacity(0.08),
                                    radius: 18,
                                    child: const Icon(Icons.person_outline_rounded, size: 18, color: AppTheme.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                        ),
                                        Text(
                                          'Checked in at $time',
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      status,
                                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green),
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
