import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/services/announcements_service.dart';
import '../../more/notifications_screen.dart';
import '../../../../core/navigation/app_router.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../authentication/role_selection_screen.dart';
import '../../dashboard/gym_switcher_bottom_sheet.dart';
import '../../../core/repository/gym_repository.dart';
import '../staff_viewmodel.dart';
import '../../../core/models/staff.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/widgets/sidebar_drawer.dart';

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Announcement> _announcements = [];
  bool _isLoadingAnnouncements = true;

  Staff? _currentStaff;
  int _presentDays = 0;
  int _absentDays = 0;
  String _workingHours = '0h 0m';
  double _advanceSalary = 0.0;
  List<Map<String, dynamic>> _dotAttendance = [];
  int _notificationsCount = 0;
  bool _isLoadingDashboard = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUnlinkedStatus();
      _loadDashboardData();
    });
  }

  Future<void> _checkUnlinkedStatus() async {
    if (!mounted) return;
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      if (authVm.isLoggedIn) {
        await authVm.loadCurrentProfile();
        if (authVm.userAssociations.isEmpty) {
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (dialogCtx) {
                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text('Account Unlinked', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  content: Text('Gym Owner unlinked your account.', style: GoogleFonts.inter()),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogCtx);
                        await authVm.logout();
                        if (mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            AppRouter.scaleRoute(const RoleSelectionScreen()),
                            (route) => false,
                          );
                        }
                      },
                      child: Text('OK', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    ),
                  ],
                );
              },
            );
          }
        }
      }
    } catch (e) {
      print('Error checking staff unlinked status: $e');
    }
  }

  Future<void> _loadAnnouncements() async {
    try {
      final repo = Provider.of<GymRepository>(context, listen: false);
      final gymId = repo.storage.getGymInfo()?['id'];
      final data = await AnnouncementsService.getAnnouncements(gymId: gymId);
      final filtered = data.where((e) {
        final aud = e.audience.toLowerCase();
        final st = e.status.toLowerCase();
        return (st == 'sent' || st.isEmpty) && 
               (aud.contains('staff') || aud.contains('member') || aud.contains('everyone') || aud == 'all');
      }).toList();
      if (mounted) {
        setState(() {
          _announcements = filtered;
          _isLoadingAnnouncements = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAnnouncements = false);
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final repo = Provider.of<GymRepository>(context, listen: false);
      final staffVm = Provider.of<StaffViewModel>(context, listen: false);

      final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;
      if (profileUserId != null) {
        // Find current staff
        final list = repo.getStaff();
        final staff = list.firstWhere(
          (s) => s.userId == profileUserId,
          orElse: () => Staff(
            id: '',
            name: authVm.currentProfile?.fullName ?? 'Staff',
            email: authVm.currentProfile?.email ?? '',
            phone: '',
            role: 'Trainer',
            department: 'Training',
            status: 'Active',
            joinDate: '',
            shift: '',
            experience: '',
            rating: 5.0,
            sessionsCount: 0,
            membersTrained: 0,
            salary: 0.0,
            salaryDue: 0.0,
            avatar: authVm.currentProfile?.photoUrl ?? '',
          ),
        );

        // Fetch salary advances
        double advanceSum = 0.0;
        if (staff.id.isNotEmpty) {
          final advances = await staffVm.fetchSalaryAdvances(staff.id);
          advanceSum = advances
              .where((a) => a['status'] == 'Approved')
              .fold(0.0, (sum, a) => sum + ((a['advance_amount'] as num?)?.toDouble() ?? 0.0));
        }

        // Get attendance records
        final allAttendance = repo.getAttendance();
        final staffAttendance = allAttendance
            .where((r) => (r.userId == profileUserId || r.userId == staff.id) && r.userType == 'Staff')
            .toList();

        // Calculate Present & Absent days
        final presentCount = staffAttendance.where((r) => 
          r.status == 'Present' || r.status == 'Late' || r.status == 'Early Exit' || r.status == 'Overtime'
        ).length;
        
        final absentCount = staffAttendance.where((r) => r.status == 'Absent').length;

        // Calculate total working minutes
        final totalMins = staffAttendance.fold(0, (sum, r) => sum + r.workingMinutes);
        final hours = totalMins ~/ 60;
        final mins = totalMins % 60;

        // Get dots for the current week (Sunday to Saturday)
        final List<Map<String, dynamic>> dots = [];
        final weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
        final now = DateTime.now();
        final sunday = now.weekday == 7 ? now : now.subtract(Duration(days: now.weekday));
        
        for (int i = 0; i < 7; i++) {
          final targetDate = sunday.add(Duration(days: i));
          final formattedTarget = DateFormat('dd-MM-yyyy').format(targetDate);
          final matchingLogs = staffAttendance.where((r) => r.date == formattedTarget).toList();
          final log = matchingLogs.isNotEmpty ? matchingLogs.first : null;
          
          String dotStatus = 'absent';
          if (log != null) {
            if (log.status == 'Present' || log.status == 'Late' || log.status == 'Early Exit' || log.status == 'Overtime') {
              dotStatus = 'present';
            } else if (log.status == 'Half Day' || log.status == 'Half Leave') {
              dotStatus = 'half day';
            } else if (log.status == 'Holiday') {
              dotStatus = 'holiday';
            } else if (log.status == 'Absent') {
              dotStatus = 'absent';
            } else {
              dotStatus = 'holiday'; // Other leave types
            }
          } else {
            if (targetDate.weekday == DateTime.sunday) {
              dotStatus = 'holiday';
            } else {
              final todayDateOnly = DateTime(now.year, now.month, now.day);
              final targetDateOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);
              if (targetDateOnly.isAfter(todayDateOnly) || targetDateOnly.isAtSameMomentAs(todayDateOnly)) {
                dotStatus = 'pending';
              } else {
                dotStatus = 'absent';
              }
            }
          }

          dots.add({
            'day': weekdays[i],
            'date': targetDate.day.toString(),
            'status': dotStatus,
          });
        }

        // Fetch notifications count
        int notifCount = 0;
        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
        if (gymId != null) {
          final notifRes = await SupabaseService.client
              .from('notifications')
              .select('id')
              .eq('gym_id', gymId);
          notifCount = (notifRes as List).length;
        }

        if (mounted) {
          setState(() {
            _currentStaff = staff;
            _presentDays = presentCount;
            _absentDays = absentCount;
            _workingHours = '${hours}h ${mins}m';
            _advanceSalary = advanceSum;
            _dotAttendance = dots;
            _notificationsCount = notifCount;
            _isLoadingDashboard = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingDashboard = false);
      }
    } catch (e) {
      print('Error loading staff dashboard data: $e');
      if (mounted) setState(() => _isLoadingDashboard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final gymName = authVm.gymInfo?['name'] ?? 'FitZone Gym';
    final avatarUrl = _currentStaff?.avatar ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=150';
    final displayName = _currentStaff?.name ?? 'Staff';

    return Scaffold(
      key: _scaffoldKey,
      drawer: const SidebarDrawer(),
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _isLoadingDashboard
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadAnnouncements();
                  await _loadDashboardData();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Custom Staff Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary, size: 26),
                                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Staff Dashboard',
                                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  GestureDetector(
                                    onTap: () {
                                      GymSwitcherBottomSheet.show(context);
                                    },
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Staff • $gymName',
                                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.arrow_drop_down_rounded,
                                            size: 16,
                                            color: AppTheme.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Stack(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.notifications_outlined, color: AppTheme.textPrimary),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                                      ).then((_) => _loadDashboardData());
                                    },
                                  ),
                                  if (_notificationsCount > 0)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                        child: Text(
                                          '$_notificationsCount',
                                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  avatarUrl,
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 32,
                                    height: 32,
                                    color: AppTheme.primaryLight,
                                    child: const Icon(Icons.person, color: AppTheme.primary, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 2. Hello Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primary, Color(0xFF6366F1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, $displayName 👋',
                              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Good Morning!',
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. Today's Summary Section Header
                      Text(
                        'Today\'s Summary',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 12),

                      // 2x2 Stat Grid
                      ResponsiveGrid(
                        crossAxisCountMobile: 2,
                        crossAxisCountTablet: 4,
                        spacing: 12,
                        runSpacing: 12,
                        childAspectRatio: context.selectValue(mobile: 1.35, smallMobile: 1.12, tablet: 1.55),
                        children: [
                          _buildSummaryCard('Present Days', '$_presentDays', Icons.calendar_today_rounded, Colors.green),
                          _buildSummaryCard('Absent Days', '$_absentDays', Icons.cancel_outlined, Colors.red),
                          _buildSummaryCard('Working Hours', _workingHours, Icons.hourglass_empty_rounded, Colors.blue),
                          _buildSummaryCard('Advance Salary', '₹${NumberFormat('#,##,###').format(_advanceSalary)}', Icons.payments_outlined, Colors.orange),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 4. This Month Attendance Dots Grid Card
                      Text(
                        'This Month Attendance',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 12),
                      CustomCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: _dotAttendance.map((dot) {
                                return _AttendanceDot(
                                  day: dot['day'].toString(),
                                  date: dot['date'].toString(),
                                  status: dot['status'].toString(),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            // Legend
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildLegendItem('Present', Colors.green),
                                const SizedBox(width: 16),
                                _buildLegendItem('Absent', Colors.red),
                                const SizedBox(width: 16),
                                _buildLegendItem('Holiday', Colors.grey),
                                const SizedBox(width: 16),
                                _buildLegendItem('Half Day', Colors.orange),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 5. Announcements Card
                      Text(
                        'Announcements',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 12),

                      _isLoadingAnnouncements
                          ? const Center(child: CircularProgressIndicator())
                          : _announcements.isEmpty
                              ? CustomCard(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: Text(
                                      'No recent announcements.',
                                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                                    ),
                                  ),
                                )
                              : Column(
                                  children: _announcements.map((ann) {
                                    return CustomCard(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: AppTheme.primary.withOpacity(0.1),
                                            child: const Icon(Icons.campaign_rounded, color: AppTheme.primary, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ann.title,
                                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  ann.message,
                                                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                                                ),
                                                if (ann.image.isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.network(ann.image, height: 100, width: double.infinity, fit: BoxFit.cover),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return CustomCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _AttendanceDot extends StatelessWidget {
  final String day;
  final String date;
  final String status;

  const _AttendanceDot({
    required this.day,
    required this.date,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    final stat = status.toLowerCase();
    if (stat == 'present') {
      dotColor = Colors.green;
    } else if (stat == 'absent') {
      dotColor = Colors.red;
    } else if (stat == 'half day' || stat == 'half leave') {
      dotColor = Colors.orange; // Yellow/Orange for Half Day
    } else {
      dotColor = Colors.grey.shade400; // Holiday/Leave
    }

    return Column(
      children: [
        Text(day, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              date,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
