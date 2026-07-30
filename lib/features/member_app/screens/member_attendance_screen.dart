import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../../core/repository/gym_repository.dart';
import '../member_app_viewmodel.dart';

class MemberAttendanceScreen extends StatefulWidget {
  const MemberAttendanceScreen({super.key});

  @override
  State<MemberAttendanceScreen> createState() => _MemberAttendanceScreenState();
}

class _MemberAttendanceScreenState extends State<MemberAttendanceScreen> {
  DateTime _currentMonth = DateTime.now();

  void _changeMonth(int offset) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + offset, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            title: Text('Attendance', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 16),

                // ═══════ TODAY'S STATUS CARD ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Today', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
                              const SizedBox(height: 2),
                              Text(DateFormat('EEEE d MMMM yyyy').format(DateTime.now()), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                              if (vm.checkedInToday) ...[
                                const SizedBox(height: 4),
                                Text(vm.checkInTime, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: vm.checkedInToday ? AppTheme.successLight : AppTheme.surfaceGray,
                          ),
                          child: Icon(
                            vm.checkedInToday ? Icons.check_rounded : Icons.close_rounded,
                            color: vm.checkedInToday ? AppTheme.success : AppTheme.textMuted,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ═══════ CALENDAR ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Column(
                      children: [
                        // Month header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.textMuted),
                                onPressed: () => _changeMonth(-1),
                              ),
                              Text(DateFormat('MMMM yyyy').format(_currentMonth), style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                              IconButton(
                                icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                                onPressed: () => _changeMonth(1),
                              ),
                            ],
                          ),
                        ),
                        // Day headers
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                                .map((d) => SizedBox(
                                      width: 36,
                                      child: Center(
                                        child: Text(d, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Calendar grid
                        _buildCalendarGrid(vm),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ═══════ THIS MONTH SUMMARY ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Text('This Month', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const Spacer(),
                        Text('Attendance', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
                          child: Text('${vm.presentDays}/${vm.totalGymDays} Days', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ═══════ CHECK IN HISTORY BUTTON ═══════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Check In History', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendarGrid(MemberAppViewModel vm) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    
    final firstDayWeekday = firstDayOfMonth.weekday;
    final startOffset = firstDayWeekday == 7 ? 0 : firstDayWeekday; 
    
    final totalDays = lastDayOfMonth.day;
    final today = now.day;
    final isCurrentMonth = _currentMonth.year == now.year && _currentMonth.month == now.month;

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final repo = Provider.of<GymRepository>(context, listen: false);

    // We filter logs for _currentMonth
    final logsThisMonth = repo.getAttendance().where((r) {
      if (r.userId != authVm.currentUser?.id && r.userId != authVm.currentProfile?.id) return false;
      try {
        DateTime parsedDate = DateFormat('dd-MM-yyyy').parse(r.date);
        return parsedDate.year == _currentMonth.year && parsedDate.month == _currentMonth.month;
      } catch (_) {
        return false;
      }
    }).toList();

    List<Widget> rows = [];
    List<Widget> currentRow = [];

    // Empty cells for offset
    for (int i = 0; i < startOffset; i++) {
      currentRow.add(const SizedBox(width: 36, height: 36));
    }

    for (int day = 1; day <= totalDays; day++) {
      final dateStr = DateFormat('dd-MM-yyyy').format(DateTime(_currentMonth.year, _currentMonth.month, day));
      final logsForDay = logsThisMonth.where((l) => l.date == dateStr).toList();
      
      Color bgColor = Colors.transparent;
      Color textColor = AppTheme.textPrimary;
      final isToday = isCurrentMonth && day == today;
      
      if (logsForDay.isNotEmpty) {
        final status = logsForDay.first.status;
        if (isToday) {
          // Today (Solid background, white text)
          if (status == 'Present' || status == 'Late' || status == 'Early Exit' || status == 'Overtime') {
            bgColor = AppTheme.success;
            textColor = Colors.white;
          } else if (status == 'Half Day' || status == 'Half Leave') {
            bgColor = Colors.orange;
            textColor = Colors.white;
          } else if (status == 'Absent') {
            bgColor = AppTheme.danger;
            textColor = Colors.white;
          } else if (status == 'Leave' || status == 'On Leave') {
            bgColor = Colors.purple;
            textColor = Colors.white;
          } else if (status == 'Holiday') {
            bgColor = AppTheme.textMuted;
            textColor = Colors.white;
          }
        } else {
          // Past days (Light background, colored text)
          if (status == 'Present' || status == 'Late' || status == 'Early Exit' || status == 'Overtime') {
            bgColor = AppTheme.successLight;
            textColor = AppTheme.success;
          } else if (status == 'Half Day' || status == 'Half Leave') {
            bgColor = const Color(0xFFFEF3C7);
            textColor = Colors.orange;
          } else if (status == 'Absent') {
            bgColor = AppTheme.dangerLight;
            textColor = AppTheme.danger;
          } else if (status == 'Leave' || status == 'On Leave') {
            bgColor = const Color(0xFFF3E8FF);
            textColor = Colors.purple;
          } else if (status == 'Holiday') {
            bgColor = AppTheme.surfaceGray;
            textColor = AppTheme.textMuted;
          }
        }
      }

      if (isToday && bgColor == Colors.transparent) {
        bgColor = AppTheme.info;
        textColor = Colors.white;
      }

      currentRow.add(
        SizedBox(
          width: 36, height: 36,
          child: Center(
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bgColor,
              ),
              child: Center(
                child: Text(
                  '$day',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: (isToday || bgColor != Colors.transparent) ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      if ((startOffset + day) % 7 == 0 || day == totalDays) {
        // Fill remaining cells in last row
        while (currentRow.length < 7) {
          currentRow.add(const SizedBox(width: 36, height: 36));
        }
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: List.from(currentRow)),
          ),
        );
        currentRow = [];
      }
    }

    return Column(children: rows);
  }
}
