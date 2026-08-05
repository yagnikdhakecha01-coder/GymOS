import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/repository/gym_repository.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/services/supabase_service.dart';

class StaffAttendanceScreen extends StatefulWidget {
  const StaffAttendanceScreen({super.key});

  @override
  State<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

enum AttendanceState {
  notCheckedIn,
  scanningCheckIn,
  checkInSuccess,
  checkedIn,
  scanningCheckOut,
  checkOutSuccess,
  todaySummary,
  history,
  scanFailure,
}

class _StaffAttendanceScreenState extends State<StaffAttendanceScreen> {
  AttendanceState _currentState = AttendanceState.notCheckedIn;
  bool _isTorchOn = false;
  bool _isScanCompleted = false;
  bool _scanCompletedSync = false;
  final MobileScannerController _scannerController = MobileScannerController();

  String _successTime = '';
  String _successDate = '';
  String _successWorkingHours = '';
  String _shiftHours = '9:00 AM - 7:00 PM';
  String? _errorText;
  Map<String, dynamic>? _todayDetails;
  int _lateMinutes = 0;
  int _earlyExitMinutes = 0;
  String _failureMessage = '';

  GymRepository? _gymRepo;

  @override
  void initState() {
    super.initState();
    _initAttendance();
    _gymRepo = Provider.of<GymRepository>(context, listen: false);
    _gymRepo?.addListener(_onRepoUpdated);
  }

  Future<void> _initAttendance() async {
    await _loadStaffShift();     // Load local cache first (fast, fallback)
    await _checkCurrentStatus(); // Then override with authoritative RPC data
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _gymRepo?.removeListener(_onRepoUpdated);
    super.dispose();
  }

  void _onRepoUpdated() {
    if (mounted) {
      if (_currentState == AttendanceState.scanningCheckIn ||
          _currentState == AttendanceState.scanningCheckOut ||
          _currentState == AttendanceState.checkInSuccess ||
          _currentState == AttendanceState.checkOutSuccess ||
          _currentState == AttendanceState.scanFailure) {
        return;
      }
      _checkCurrentStatus();
    }
  }

  Future<void> _loadStaffShift() async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final repo = Provider.of<GymRepository>(context, listen: false);
      final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];

      // 1. Direct Supabase DB Query for shift assignment
      if (gymId != null && profileUserId != null) {
        try {
          final staffRes = await SupabaseService.client
              .from('staff')
              .select('id, shift')
              .eq('gym_id', gymId)
              .or('user_id.eq.$profileUserId,id.eq.$profileUserId')
              .limit(1)
              .maybeSingle();

          if (staffRes != null) {
            final staffId = staffRes['id'];
            final assignRes = await SupabaseService.client
                .from('staff_shift_assignments')
                .select('assignment_type')
                .eq('staff_id', staffId)
                .eq('status', 'Active')
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle();

            String assignedShift = 'Single Shift';
            if (assignRes != null && assignRes['assignment_type'] != null) {
              assignedShift = assignRes['assignment_type'];
            } else if (staffRes['shift'] != null) {
              assignedShift = staffRes['shift'];
            }

            if (mounted) {
              setState(() {
                _shiftHours = (assignedShift == 'Two Shifts' || assignedShift == 'Both Shifts') 
                    ? 'Both Shifts' 
                    : assignedShift;
              });
              return;
            }
          }
        } catch (_) {}
      }

      // Fallback: repo staff cache
      if (profileUserId != null) {
        final matchingStaff = repo.getStaff().where((s) => s.userId == profileUserId).toList();
        final staff = matchingStaff.isNotEmpty ? matchingStaff.first : null;
        if (staff != null && mounted) {
          setState(() {
            _shiftHours = (staff.shift == 'Two Shifts' || staff.shift == 'Both Shifts')
                ? 'Both Shifts'
                : staff.shift;
          });
        }
      }
    } catch (e) {
      print('[StaffAttendance] _loadStaffShift error: $e');
    }
  }

  Future<void> _checkCurrentStatus() async {
    if (_currentState == AttendanceState.scanningCheckIn ||
        _currentState == AttendanceState.scanningCheckOut ||
        _currentState == AttendanceState.checkInSuccess ||
        _currentState == AttendanceState.checkOutSuccess ||
        _currentState == AttendanceState.scanFailure) {
      return;
    }
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final repo = Provider.of<GymRepository>(context, listen: false);
      final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (profileUserId != null && gymId != null) {
        await repo.fetchTodayAttendanceDetails(profileUserId, gymId);
        final details = repo.todayAttendanceDetails;
        print('[StaffAttendance] RPC returned details: $details');
        print('[StaffAttendance] assigned_shift = ${details?['assigned_shift']}');
        if (details != null && mounted) {
          if (_currentState == AttendanceState.scanningCheckIn ||
              _currentState == AttendanceState.scanningCheckOut ||
              _currentState == AttendanceState.checkInSuccess ||
              _currentState == AttendanceState.checkOutSuccess ||
              _currentState == AttendanceState.scanFailure) {
            return;
          }
          setState(() {
            _todayDetails = details;
            _shiftHours = details['assigned_shift'] ?? 'Single Shift';
            _successWorkingHours = details['working_hours_today'] ?? '0h 00m';
            
            final bool isCheckedIn = details['is_checked_in'] == true || details['can_check_out'] == true;
            final bool isFullyCompleted = details['is_attendance_completed'] == true;

            if (isCheckedIn) {
              _currentState = AttendanceState.checkedIn;
              _successTime = details['second_shift_check_in'] ?? details['first_shift_check_in'] ?? '';
            } else if (isFullyCompleted) {
              _currentState = AttendanceState.todaySummary;
              _successTime = details['first_shift_check_in'] ?? '';
            } else {
              _currentState = AttendanceState.notCheckedIn;
            }
          });
        }
      }
    } catch (e) {
      print('[StaffAttendance] _checkCurrentStatus error: $e');
    }
  }

  Future<void> _onQRDetected(String code) async {
    final gymRepo = Provider.of<GymRepository>(context, listen: false);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final profileUserId = authVm.currentUser?.id ?? authVm.currentProfile?.id ?? '';
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final isCheckIn = (_currentState == AttendanceState.scanningCheckIn);

    final result = await gymRepo.processScanAttendanceInSupabase(
      token: code.trim(),
      userId: profileUserId,
      gymId: gymId,
      userType: 'Staff',
      method: 'Static QR',
      ssid: '',
      bssid: '',
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final isAlreadyMarked = result['already_marked'] == true;
      final actionStr = (result['action'] as String?)?.toLowerCase() ?? '';
      
      if (isAlreadyMarked && (actionStr == 'completed' || (result['message'] as String?)?.contains('already') == true)) {
        setState(() {
          _errorText = null;
          _failureMessage = result['message'] ?? 'Attendance already completed for today.';
          _currentState = AttendanceState.scanFailure;
          _isScanCompleted = false;
          _scanCompletedSync = false;
        });
        await gymRepo.fetchAttendanceLogsFromSupabase();
        return;
      }

      final isCheckInAction = actionStr.contains('check in') || actionStr.contains('check_in') || isCheckIn;
      final checkInTime = result['check_in'] ?? result['checkInTime'] ?? DateFormat('hh:mm a').format(DateTime.now());
      final checkOutTime = result['check_out'] ?? result['checkOutTime'] ?? DateFormat('hh:mm a').format(DateTime.now());
      final workingMins = (result['working_minutes'] ?? result['workingMins'] as num?)?.toInt() ?? 0;
      final hours = workingMins ~/ 60;
      final mins = workingMins % 60;
      
      final lateMins = (result['late_minutes'] ?? result['lateMinutes'] as num?)?.toInt() ?? 0;
      final earlyMins = (result['early_exit_minutes'] ?? result['earlyExitMinutes'] as num?)?.toInt() ?? 0;

      setState(() {
        _successTime = isCheckInAction ? checkInTime : checkOutTime;
        _successDate = DateFormat('dd MMM yyyy').format(DateTime.now());
        _successWorkingHours = '${hours}h ${mins}m';
        _lateMinutes = lateMins;
        _earlyExitMinutes = earlyMins;
        _currentState = isCheckInAction ? AttendanceState.checkInSuccess : AttendanceState.checkOutSuccess;
        _todayDetails = gymRepo.todayAttendanceDetails;
        _isScanCompleted = false;
        _scanCompletedSync = false;
        _errorText = null;
      });

      await gymRepo.fetchAttendanceLogsFromSupabase();
    } else {
      String reason = result['reason'] ?? result['message'] ?? 'Scanning failed.';
      setState(() {
        _errorText = null;
        _failureMessage = reason;
        _currentState = AttendanceState.scanFailure;
        _isScanCompleted = false;
        _scanCompletedSync = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentState) {
      case AttendanceState.notCheckedIn:
        return _buildNotCheckedInScreen();
      case AttendanceState.scanningCheckIn:
        return _buildScannerScreen(isCheckIn: true);
      case AttendanceState.checkInSuccess:
        return _buildSuccessScreen(isCheckIn: true);
      case AttendanceState.checkedIn:
        return _buildCheckedInScreen();
      case AttendanceState.scanningCheckOut:
        return _buildScannerScreen(isCheckIn: false);
      case AttendanceState.checkOutSuccess:
        return _buildSuccessScreen(isCheckIn: false);
      case AttendanceState.todaySummary:
        return _buildTodaySummaryScreen();
      case AttendanceState.history:
        return _buildHistoryScreen();
      case AttendanceState.scanFailure:
        return _buildFailureScreen();
    }
  }

  Widget _buildErrorBanner() {
    if (_errorText == null) return const SizedBox.shrink();
    final err = _errorText!;
    if (err.contains('PostgrestException') || err.contains('42703') || err.contains('22007') || err.contains('code:')) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFEE2E2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorText!,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorText = null),
            child: const Icon(Icons.close_rounded, color: Colors.red, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildNotCheckedInScreen() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Attendance',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildErrorBanner(),
              if (_todayDetails?['is_on_leave'] == true || _todayDetails?['first_shift_status'] == 'Leave') ...[
                CustomCard(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        backgroundColor: Color(0xFFFEF3C7),
                        child: Icon(Icons.beach_access_rounded, color: Colors.orange, size: 32),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'On Leave Today',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _todayDetails?['leave_reason'] ?? 'Your leave request has been approved for today.',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                CustomCard(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Column(
                    children: [
                      Text(
                        "Today's Status",
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0xFFFFF1F2),
                        child: Icon(Icons.calendar_today_rounded, color: Colors.red, size: 24),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Not Checked In',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Icon(Icons.schedule_rounded, color: AppTheme.textMuted, size: 18),
                                const SizedBox(height: 6),
                                Text(
                                  'Today\'s Shift',
                                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                                ),
                                Text(
                                  _shiftHours,
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 40, color: const Color(0xFFE5E7EB)),
                          Expanded(
                            child: Column(
                              children: [
                                const Icon(Icons.hourglass_empty_rounded, color: AppTheme.textMuted, size: 18),
                                const SizedBox(height: 6),
                                Text(
                                  'Working Hours',
                                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                                ),
                                Text(
                                  '0h 00m',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              _buildShiftStatusSection(_todayDetails),
              if (_todayDetails?['is_on_leave'] != true && (_todayDetails == null || _todayDetails?['can_check_in'] == true)) ...[
              CustomButton(
                text: 'Check In',
                color: AppTheme.primary,
                onPressed: () async {
                  var status = await Permission.camera.status;
                  if (!status.isGranted) {
                    status = await Permission.camera.request();
                  }
                  if (status.isGranted) {
                    if (mounted) {
                      setState(() {
                        _errorText = null;
                        _isScanCompleted = false;
                        _scanCompletedSync = false;
                        _currentState = AttendanceState.scanningCheckIn;
                      });
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Camera permission is required to scan QR code.')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
            _buildWeeklySummarySection(),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildWeeklySummarySection() {
    return FutureBuilder<dynamic>(
      future: (() async {
        if (!SupabaseService.isInitialized) return null;
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        final repo = Provider.of<GymRepository>(context, listen: false);
        final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;
        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
        if (gymId == null) return null;

        // Try RPC first
        try {
          if (profileUserId != null) {
            final res = await SupabaseService.client.rpc('get_staff_weekly_summary_v1', params: {
              'p_user_id': profileUserId,
              'p_gym_id': gymId,
            });
            if (res != null && res is Map) return res;
          }
        } catch (_) {}

        // Direct Supabase DB Query for Weekly Summary
        try {
          final now = DateTime.now();
          final monday = now.subtract(Duration(days: now.weekday - 1));
          final mondayStr = DateFormat('yyyy-MM-dd').format(monday);

          final List allLogs = await SupabaseService.client
              .from('attendance_logs')
              .select()
              .eq('gym_id', gymId)
              .gte('check_in', '${mondayStr}T00:00:00');

          final matchingLogs = allLogs.cast<Map<String, dynamic>>().where((l) {
            final uId = l['user_id']?.toString();
            final sId = l['staff_id']?.toString();
            return uId == profileUserId || sId == profileUserId || uId == SupabaseService.client.auth.currentUser?.id;
          }).toList();

          double present = 0.0;
          double absent = 0.0;
          double lateCount = 0.0;
          final isTwoShifts = _shiftHours == 'Both Shifts' || _shiftHours == 'Two Shifts';

          for (var log in matchingLogs) {
            final status = (log['status'] ?? '').toString();
            final lateMins = log['late_minutes'] as int? ?? 0;
            final weight = isTwoShifts ? 0.5 : 1.0;

            if (status == 'Half Leave') {
              present += 0.5;
              absent += 0.5;
            } else if (status == 'Absent' || status == 'Leave' || status == 'On Leave') {
              absent += weight;
            } else if (status == 'Late' || lateMins > 0) {
              present += weight;
              lateCount += weight;
            } else {
              present += weight;
            }
          }

          if (matchingLogs.isEmpty && repo.todayAttendanceDetails?['first_shift_check_in'] != null) {
            present = 1.0;
          }

          final totalCount = matchingLogs.isNotEmpty ? matchingLogs.length : (present > 0 ? present : 1.0);
          return {
            'present': present,
            'absent': absent,
            'late': lateCount,
            'total': totalCount,
          };
        } catch (e) {
          return {'present': 1, 'absent': 0, 'late': 0, 'total': 1};
        }
      })(),
      builder: (context, snapshot) {
        String presentStr = '0';
        String absentStr = '0';
        String lateStr = '0';
        String totalStr = '0';

        if (snapshot.hasData && snapshot.data != null && snapshot.data is Map) {
          final data = snapshot.data as Map;
          final pVal = data['present'];
          presentStr = (pVal is double) ? pVal.toString() : (pVal?.toString() ?? '0');
          
          final aVal = data['absent'];
          absentStr = aVal?.toString() ?? '0';
          
          final lVal = data['late'];
          lateStr = lVal?.toString() ?? '0';
          
          final tVal = data['total'];
          totalStr = tVal?.toString() ?? '0';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Summary (This Week)',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                GestureDetector(
                  onTap: () => setState(() => _currentState = AttendanceState.history),
                  child: Text(
                    'View History',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            CustomCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildWeekStat('Present', presentStr, Colors.green),
                  _buildWeekStat('Absent', absentStr, Colors.red),
                  _buildWeekStat('Late', lateStr, Colors.orange),
                  _buildWeekStat('Total', totalStr, AppTheme.primary),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeekStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildScannerScreen({required bool isCheckIn}) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: (capture) async {
                if (_scanCompletedSync) return;
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String? codeValue = barcodes.first.rawValue;
                  if (codeValue != null && codeValue.isNotEmpty) {
                    _scanCompletedSync = true;
                    setState(() {
                      _isScanCompleted = true;
                    });
                    await _onQRDetected(codeValue);
                  }
                }
              },
              errorBuilder: (context, error, child) {
                return Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Camera not available or permission denied.',
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.4),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _currentState = isCheckIn ? AttendanceState.notCheckedIn : AttendanceState.checkedIn;
                          });
                          _checkCurrentStatus();
                        },
                      ),
                      Text(
                        'Scan QR Code',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: Icon(
                          _isTorchOn ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          _scannerController.toggleTorch();
                          setState(() => _isTorchOn = !_isTorchOn);
                        },
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Center(
                  child: Text(
                    isCheckIn ? 'Scan the Gym QR Code\nto Check In' : 'Scan the Gym QR Code\nto Check Out',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.primary, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        _buildViewfinderCorner(Alignment.topLeft),
                        _buildViewfinderCorner(Alignment.topRight),
                        _buildViewfinderCorner(Alignment.bottomLeft),
                        _buildViewfinderCorner(Alignment.bottomRight),
                        const Center(
                          child: Divider(color: Colors.red, thickness: 1.5, height: 1),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                Center(
                  child: Text(
                    'Position the QR code within the frame to scan',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinderCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            top: alignment == Alignment.topLeft || alignment == Alignment.topRight
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
            right: alignment == Alignment.topRight || alignment == Alignment.bottomRight
                ? const BorderSide(color: Colors.white, width: 3)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen({required bool isCheckIn}) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.green, size: 54),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  isCheckIn ? 'Checked In Successfully!' : 'Checked Out Successfully!',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ),
              const SizedBox(height: 32),
              CustomCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      _successTime,
                      style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _successDate,
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CustomCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Working Hours', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                        Text(
                          isCheckIn ? '0h 00m' : _successWorkingHours,
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                    if (isCheckIn && _lateMinutes > 0) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Late Entry', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                          Text(
                            '$_lateMinutes mins late',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                          ),
                        ],
                      ),
                    ],
                    if (!isCheckIn && _earlyExitMinutes > 0) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Early Exit', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                          Text(
                            '$_earlyExitMinutes mins early',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              CustomButton(
                text: 'OK, Got It',
                color: AppTheme.primary,
                onPressed: () {
                  setState(() {
                    _currentState = isCheckIn ? AttendanceState.checkedIn : AttendanceState.todaySummary;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckedInScreen() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Attendance',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildErrorBanner(),
            CustomCard(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Text(
                    "Today's Status",
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFFDCFCE7),
                    child: Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Checked In • ',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      Text(
                        _successTime,
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Icon(Icons.schedule_rounded, color: AppTheme.textMuted, size: 18),
                            const SizedBox(height: 6),
                            Text(
                              'Today\'s Shift',
                              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                            ),
                            Text(
                              _shiftHours,
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: const Color(0xFFE5E7EB)),
                      Expanded(
                        child: Column(
                          children: [
                            const Icon(Icons.hourglass_empty_rounded, color: AppTheme.textMuted, size: 18),
                            const SizedBox(height: 6),
                            Text(
                              'Working Hours',
                              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                            ),
                            Text(
                              'Active',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _buildShiftStatusSection(_todayDetails),
            if (_todayDetails?['can_check_out'] == true) ...[
              CustomButton(
                text: 'Check Out',
                color: AppTheme.primary,
                onPressed: () async {
                  var status = await Permission.camera.status;
                  if (!status.isGranted) {
                    status = await Permission.camera.request();
                  }
                  if (status.isGranted) {
                    if (mounted) {
                      setState(() {
                        _errorText = null;
                        _isScanCompleted = false;
                        _scanCompletedSync = false;
                        _currentState = AttendanceState.scanningCheckOut;
                      });
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Camera permission is required to scan QR code.')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please scan the QR code again when you leave the gym.',
                      style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.primary, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildWeeklySummarySection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodaySummaryScreen() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => setState(() => _currentState = AttendanceState.notCheckedIn),
        ),
        title: Text(
          'Today\'s Attendance',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSummaryRow('Check In', _successTime),
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  _buildSummaryRow('Check Out', 'Completed'),
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  _buildSummaryRow('Total Working Hours', _successWorkingHours, isBoldValue: true),
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  _buildSummaryStatusRow('Status', 'Completed'),
                ],
              ),
            ),
            _buildShiftStatusSection(_todayDetails),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCFCE7)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sentiment_satisfied_alt_rounded, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Great job! 👋',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
            ),
            const Spacer(),
            CustomButton(
              text: 'View History',
              color: AppTheme.primary,
              onPressed: () {
                setState(() => _currentState = AttendanceState.history);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBoldValue = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isBoldValue ? FontWeight.bold : FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStatusRow(String label, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryScreen() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => setState(() => _currentState = AttendanceState.notCheckedIn),
        ),
        title: Text(
          'Attendance History',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: _buildHistoryList(),
    );
  }

  Widget _buildHistoryList() {
    final authVm = Provider.of<AuthViewModel>(context);
    final repo = Provider.of<GymRepository>(context);
    final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;

    final staffLogs = repo.getAttendance()
        .where((r) => r.userId == profileUserId && r.userType == 'Staff')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CustomCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Center(
            child: Text(
              'My Attendance History',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (staffLogs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'No attendance history records found.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
          )
        else
          ...staffLogs.reversed.map((log) {
            final isAbsent = log.status == 'Absent';
            final checkInStr = log.checkInTime;
            final checkOutStr = log.checkOutTime ?? 'Pending';
            final workingHoursStr = '${log.workingMinutes ~/ 60}h ${log.workingMinutes % 60}m';

            return CustomCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.date,
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAbsent ? 'Absent' : '$checkInStr - $checkOutStr   •   $workingHoursStr',
                          style: GoogleFonts.inter(fontSize: 10.5, color: isAbsent ? Colors.red : AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isAbsent ? const Color(0xFFFFF1F2) : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      log.status,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isAbsent ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildShiftStatusSection(Map<String, dynamic>? initialDetails) {
    return FutureBuilder<dynamic>(
      future: (() async {
        if (!SupabaseService.isInitialized) return initialDetails;
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;
        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
        if (profileUserId == null || gymId == null) return initialDetails;
        try {
          final res = await SupabaseService.client.rpc('get_staff_today_attendance_details_v2', params: {
            'p_user_id': profileUserId,
            'p_gym_id': gymId,
          });
          if (res != null && res is Map) {
            return Map<String, dynamic>.from(res);
          }
        } catch (e) {
          print('RPC get_staff_today_attendance_details_v2 error in section: $e');
        }
        return initialDetails;
      })(),
      builder: (context, snapshot) {
        final Map<String, dynamic>? details = (snapshot.hasData && snapshot.data != null && snapshot.data is Map)
            ? Map<String, dynamic>.from(snapshot.data as Map)
            : initialDetails;

        if (details == null) return const SizedBox.shrink();
        
        final bool isTwoShifts = details['assigned_shift'] == 'Two Shifts' || details['assigned_shift'] == 'Both Shifts';
        
        Widget buildShiftItem(String name, String? checkIn, String? checkOut, String status) {
          Color statusColor = Colors.grey;
          if (status == 'Present' || status == 'Checked In') statusColor = Colors.green;
          if (status == 'Late') statusColor = Colors.orange;
          if (status == 'Absent') statusColor = Colors.red;
          if (status == 'Checked Out') statusColor = Colors.blue;

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF3F4F6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Check In', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                          const SizedBox(height: 2),
                          Text(
                            checkIn ?? 'Not yet',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: checkIn != null ? Colors.green : AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 28, color: const Color(0xFFE5E7EB)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Check Out', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                          const SizedBox(height: 2),
                          Text(
                            checkOut ?? 'Not yet',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: checkOut != null ? Colors.blue : AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'Shift Status',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            buildShiftItem(
              details['first_shift_name'] ?? 'Shift 1',
              details['first_shift_check_in'],
              details['first_shift_check_out'],
              details['first_shift_status'] ?? 'Not Checked In',
            ),
            if (isTwoShifts)
              buildShiftItem(
                details['second_shift_name'] ?? 'Shift 2',
                details['second_shift_check_in'],
                details['second_shift_check_out'],
                details['second_shift_status'] ?? 'Not Checked In',
              ),
          ],
        );
      },
    );
  }

  Widget _buildFailureScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cancel_rounded, color: Colors.red, size: 54),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Verification Failed',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ),
              const SizedBox(height: 24),
              CustomCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 36),
                    const SizedBox(height: 12),
                    Text(
                      _failureMessage.isNotEmpty ? _failureMessage : 'Attendance verification could not be processed.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              CustomButton(
                text: 'OK, Try Again',
                color: AppTheme.primary,
                onPressed: () {
                  setState(() {
                    final bool wasCheckedInBefore = _todayDetails?['can_check_out'] == true;
                    _currentState = wasCheckedInBefore ? AttendanceState.checkedIn : AttendanceState.notCheckedIn;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
