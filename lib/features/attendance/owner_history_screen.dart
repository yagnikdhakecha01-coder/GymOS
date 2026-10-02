import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/services/staff_shift_attendance_engine.dart';
import 'attendance_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../../core/widgets/app_cached_avatar.dart';

class OwnerAttendanceHistoryScreen extends StatefulWidget {
  final String userTypeFilter; // 'Staff', 'Member', or 'All'

  const OwnerAttendanceHistoryScreen({
    super.key,
    this.userTypeFilter = 'All',
  });

  @override
  State<OwnerAttendanceHistoryScreen> createState() => _OwnerAttendanceHistoryScreenState();
}

class _OwnerAttendanceHistoryScreenState extends State<OwnerAttendanceHistoryScreen> {
  int _selectedTab = 0; // 0 = Day, 1 = Week, 2 = Month
  DateTime _selectedDate = DateTime.now();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<AttendanceViewModel>(context, listen: false).refresh();
        Provider.of<StaffViewModel>(context, listen: false).fetchStaff();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime parseDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      }
    } catch (_) {}
    return DateTime.now();
  }

  bool isSameDay(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  bool isSameWeek(DateTime d1, DateTime d2) {
    final startOfW1 = d1.subtract(Duration(days: d1.weekday - 1));
    final startOfW2 = d2.subtract(Duration(days: d2.weekday - 1));
    return startOfW1.year == startOfW2.year &&
        startOfW1.month == startOfW2.month &&
        startOfW1.day == startOfW2.day;
  }

  bool isSameMonth(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month;
  }

  void _navigateDate(int direction) {
    setState(() {
      if (_selectedTab == 0) {
        // Day navigation
        _selectedDate = _selectedDate.add(Duration(days: direction));
      } else if (_selectedTab == 1) {
        // Week navigation
        _selectedDate = _selectedDate.add(Duration(days: direction * 7));
      } else if (_selectedTab == 2) {
        // Month navigation
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + direction, 1);
      }
    });
  }

  String _getDateRangeString() {
    if (_selectedTab == 0) {
      return DateFormat('dd MMMM yyyy').format(_selectedDate);
    } else if (_selectedTab == 1) {
      final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      return "${DateFormat('dd MMM').format(startOfWeek)} - ${DateFormat('dd MMM yyyy').format(endOfWeek)}";
    } else {
      return DateFormat('MMMM yyyy').format(_selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attendanceVm = Provider.of<AttendanceViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);

    // 1. Gather all logs from DB
    final allLogs = attendanceVm.attendanceHistory;

    // 2. Filter by period
    final periodLogs = allLogs.where((log) {
      final logDate = parseDate(log.date);
      if (_selectedTab == 0) {
        return isSameDay(logDate, _selectedDate);
      } else if (_selectedTab == 1) {
        return isSameWeek(logDate, _selectedDate);
      } else {
        return isSameMonth(logDate, _selectedDate);
      }
    }).toList();

    // 3. Filter by User Type and Construct display list
    final displayItems = <Map<String, dynamic>>[];
    int totalCount = 0;
    int presentCount = 0;
    int absentCount = 0;

    if (widget.userTypeFilter == 'Staff') {
      final activeStaff = staffVm.allStaff.where((s) => s.status == 'Active').toList();
      totalCount = activeStaff.length;

      if (_selectedTab == 0) {
        // Daily View for Staff: Show all active staff, marked or unmarked (Absent)
        for (var staff in activeStaff) {
          final staffLogs = periodLogs.where((log) => 
            log.userType == 'Staff' && 
            (log.userId == staff.userId || log.staffId == staff.id)
          ).toList();

          final String? checkInStr = staffLogs.isNotEmpty && staffLogs.first.checkInTime.isNotEmpty
              ? staffLogs.first.checkInTime
              : null;
          final DateTime? checkInTime = checkInStr != null
              ? StaffShiftAttendanceEngine.parseTimeToDateTime(checkInStr, targetDate: _selectedDate)
              : null;

          final eval = StaffShiftAttendanceEngine.evaluateAttendanceStatus(
            shiftStartStr: staff.shift1Start,
            shiftEndStr: staff.shift1End,
            checkInDateTime: checkInTime,
            nowDateTime: isSameDay(_selectedDate, DateTime.now()) ? DateTime.now() : _selectedDate,
          );

          final String computedStatus = staffLogs.isNotEmpty
              ? (eval['is_late'] == true ? 'Late' : (staffLogs.first.status.isNotEmpty ? staffLogs.first.status : 'Present'))
              : (eval['is_absent'] == true ? 'Absent' : 'Pending');

          if (staffLogs.isNotEmpty) {
            presentCount++;
            for (var log in staffLogs) {
              displayItems.add({
                'name': staff.name,
                'checkIn': log.checkInTime.isNotEmpty ? log.checkInTime : '--',
                'checkOut': log.checkOutTime != null && log.checkOutTime!.isNotEmpty ? log.checkOutTime : '--',
                'hours': log.workingHours != null ? '${log.workingHours!.toStringAsFixed(1)}h' : '--',
                'status': computedStatus,
                'avatar': staff.avatar,
              });
            }
          } else {
            if (computedStatus == 'Absent') absentCount++;
            displayItems.add({
              'name': staff.name,
              'checkIn': '--',
              'checkOut': '--',
              'hours': '--',
              'status': computedStatus,
              'avatar': staff.avatar,
            });
          }
        }
      } else {
        // Weekly/Monthly view for Staff: Show actual logs
        final staffPeriodLogs = periodLogs.where((log) => log.userType == 'Staff').toList();
        presentCount = staffPeriodLogs.length; // present days count
        for (var log in staffPeriodLogs) {
          final staff = staffVm.allStaff.where((s) => s.userId == log.userId || s.id == log.staffId).firstOrNull;
          displayItems.add({
            'name': log.userName,
            'checkIn': log.checkInTime.isNotEmpty ? log.checkInTime : '--',
            'checkOut': log.checkOutTime != null && log.checkOutTime!.isNotEmpty ? log.checkOutTime : '--',
            'hours': log.workingHours != null ? '${log.workingHours!.toStringAsFixed(1)}h' : '--',
            'status': log.status,
            'avatar': staff?.avatar ?? '',
          });
        }
      }
    } else if (widget.userTypeFilter == 'Member') {
      final memberPeriodLogs = periodLogs.where((log) => log.userType == 'Member').toList();
      totalCount = memberPeriodLogs.length;
      presentCount = memberPeriodLogs.length;

      for (var log in memberPeriodLogs) {
        displayItems.add({
          'name': log.userName,
          'checkIn': log.checkInTime.isNotEmpty ? log.checkInTime : '--',
          'checkOut': log.checkOutTime != null && log.checkOutTime!.isNotEmpty ? log.checkOutTime : '--',
          'hours': log.workingHours != null ? '${log.workingHours!.toStringAsFixed(1)}h' : '--',
          'status': log.status,
          'avatar': '',
        });
      }
    } else {
      // 'All' mode (Full Attendance History)
      totalCount = periodLogs.length;
      presentCount = periodLogs.where((log) => log.status != 'Absent').length;
      absentCount = periodLogs.where((log) => log.status == 'Absent').length;

      for (var log in periodLogs) {
        displayItems.add({
          'name': log.userName,
          'checkIn': log.checkInTime.isNotEmpty ? log.checkInTime : '--',
          'checkOut': log.checkOutTime != null && log.checkOutTime!.isNotEmpty ? log.checkOutTime : '--',
          'hours': log.workingHours != null ? '${log.workingHours!.toStringAsFixed(1)}h' : '--',
          'status': log.status,
          'avatar': '',
        });
      }
    }

    // 4. Search Filter
    final searchLower = _searchQuery.trim().toLowerCase();
    final filtered = displayItems.where((l) {
      return l['name'].toString().toLowerCase().contains(searchLower);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.userTypeFilter == 'Staff' 
              ? 'Staff Attendance' 
              : widget.userTypeFilter == 'Member' 
                  ? 'Member Attendance' 
                  : 'Attendance History',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              children: [
                // ── Tab Pills ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _tabPill('Day', 0),
                      _tabPill('Week', 1),
                      _tabPill('Month', 2),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Date Navigation ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.textSecondary),
                      onPressed: () => _navigateDate(-1),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getDateRangeString(),
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                      onPressed: () => _navigateDate(1),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Summary Stats Row ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _miniStat(
                      widget.userTypeFilter == 'Staff' 
                          ? 'Total Staff' 
                          : widget.userTypeFilter == 'Member' 
                              ? 'Total Members' 
                              : 'Total Logs', 
                      '$totalCount', 
                      AppTheme.textPrimary
                    ),
                    _miniStat('Present', '$presentCount', const Color(0xFF16A34A)),
                    if (widget.userTypeFilter != 'Member')
                      _miniStat('Absent', '$absentCount', const Color(0xFFEF4444)),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Search Bar ──
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF0F0F2)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: GoogleFonts.inter(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: widget.userTypeFilter == 'Staff' 
                                ? 'Search staff...' 
                                : widget.userTypeFilter == 'Member' 
                                    ? 'Search members...' 
                                    : 'Search users...',
                            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── Attendance List ──
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No attendance records found.',
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _AttendanceCard(data: item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedTab = index;
          _selectedDate = DateTime.now(); // reset date to today when changing range type
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

// ── Attendance Card ──
class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AttendanceCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String;
    final isAbsent = status == 'Absent';

    Color badgeBg;
    Color badgeText;
    if (status == 'Present' || status == 'On Time') {
      badgeBg = const Color(0xFFDCFCE7);
      badgeText = const Color(0xFF16A34A);
    } else if (status == 'Late' || status == 'Early Exit' || status == 'Half Day') {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFD97706);
    } else {
      badgeBg = const Color(0xFFFEE2E2);
      badgeText = const Color(0xFFEF4444);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          AppCachedAvatar(
            imageUrl: data['avatar'] as String?,
            name: data['name'] as String? ?? 'User',
            size: 40,
          ),
          const SizedBox(width: 12),

          // Name & Times
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['name'],
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  isAbsent ? 'Not checked in' : '${data['checkIn']} - ${data['checkOut']}',
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),

          // Hours
          if (!isAbsent) ...[
            Text(
              data['hours'],
              style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 10),
          ],

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status,
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: badgeText),
            ),
          ),
        ],
      ),
    );
  }
}
