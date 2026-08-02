import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/services/supabase_service.dart';
import '../../core/widgets/sparkline.dart';
import '../../core/widgets/sparkline_chart.dart';
import '../authentication/auth_viewmodel.dart';
import '../members/members_viewmodel.dart';
import '../../core/models/member.dart';
import '../staff/staff_viewmodel.dart';
import '../finance/finance_viewmodel.dart';
import '../attendance/attendance_viewmodel.dart';
import 'alerts_screen.dart';
import '../gym_settings/online_database_screen.dart';
import 'expiring_memberships_screen.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/owner_scanner_screen.dart';
import '../members/add_member_wizard_screen.dart';
import '../../core/widgets/add_member_selection_sheet.dart';
import '../staff/staff_screen.dart';
import '../finance/pending_payments_screen.dart';
import '../finance/finance_screen.dart';
import '../workout/workout_plans_screen.dart';
import '../diet/diet_plans_screen.dart';
import '../members/member_profile_screen.dart';
import 'reports_screen.dart';
import 'broadcast_screen.dart';
import '../more/notifications_screen.dart';
import '../gym_settings/gym_info_screen.dart';
import 'gym_switcher_bottom_sheet.dart';
import '../staff/pending_salary_list_screen.dart';
import '../staff/staff_profile_screen.dart';
import 'widgets/owner_staff_card.dart';
import '../receptionist/portal/receptionist_activity_log_screen.dart';
import '../../core/theme/responsive.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  GymRepository? _repository;
  bool _showAllActivities = false;

  int? _getDaysLeft(Member member) {
    final exp = member.extraFields['expiryDate'] as String?;
    if (exp == null || exp.isEmpty) return null;
    try {
      final parsed = DateTime.parse(exp);
      final today = DateTime.now();
      final todayDateOnly = DateTime(today.year, today.month, today.day);
      final expiryDateOnly = DateTime(parsed.year, parsed.month, parsed.day);
      return expiryDateOnly.difference(todayDateOnly).inDays;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repository = Provider.of<GymRepository>(context, listen: false);
      _repository?.addListener(_onRepositoryChanged);
      // Fetch initial stats
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId != null) {
        final formattedDate = DateFormat('yyyy-MM-dd').format(_repository!.selectedDashboardDate);
        _repository?.fetchDashboardStatsFromSupabase(gymId, formattedDate);
      }
    });
  }

  void _onRepositoryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _repository?.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final repo = Provider.of<GymRepository>(context);
    final membersVm = Provider.of<MembersViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);
    final financeVm = Provider.of<FinanceViewModel>(context);
    final attendanceVm = Provider.of<AttendanceViewModel>(context);

    final gymName = authVm.gymInfo?['name'] ?? 'FitZone Gym';
    final ownerName = authVm.gymInfo?['owner'] ?? 'Rahul Sharma';

    final activeMembersCount = repo.activeMembersCount;
    final totalMembersCount = repo.totalMembersCount;
    final revenueVal = repo.monthlyRevenue;
    final revenueStr = '₹${NumberFormat('#,##,###').format(revenueVal)}';

    // Attendance
    final checkInRecords = repo.todayAttendanceCount;
    final attendanceStr = '$checkInRecords / $activeMembersCount';
    final attendancePercent = repo.attendancePercentage;

    // Alerts
    final allMembers = membersVm.allMembers;

    final endingTodayMembers = <Member>[];
    final expiring15Members = <Member>[];
    final expired1MonthMembers = <Member>[];

    for (final m in allMembers) {
      final daysLeft = _getDaysLeft(m);
      if (daysLeft == null) continue;
      if (daysLeft == 0) {
        endingTodayMembers.add(m);
      } else if (daysLeft >= 1 && daysLeft <= 15) {
        expiring15Members.add(m);
      } else if (daysLeft >= -30 && daysLeft < 0) {
        expired1MonthMembers.add(m);
      }
    }

    final _dbExpiringToday = endingTodayMembers.length;
    final _dbExpiring15Days = expiring15Members.length;
    final _dbExpired1Month = expired1MonthMembers.length;

    final _dbPendingLeaves = repo.pendingLeavesCount;
    final _dbPendingHolidays = repo.pendingHolidaysCount;
    final _dbPendingAdvances = repo.pendingAdvancesCount;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Mockup Header Row
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary, size: 26),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good Morning 👋',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          authVm.currentProfile?.fullName ?? ownerName,
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 1),
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
                                  'Owner • $gymName',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 16,
                                  color: AppTheme.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Builder(
                          builder: (context) {
                            Color badgeColor;
                            String statusText;
                            IconData icon;

                            if (!SupabaseService.isConfigured) {
                              badgeColor = Colors.orange;
                              statusText = 'DB Setup Required';
                              icon = Icons.warning_amber_rounded;
                            } else if (!SupabaseService.isInitialized || SupabaseService.hasError) {
                              badgeColor = Colors.red;
                              statusText = 'DB Offline';
                              icon = Icons.error_outline_rounded;
                            } else {
                              badgeColor = Colors.green;
                              statusText = 'DB Connected';
                              icon = Icons.check_circle_outline_rounded;
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: badgeColor.withOpacity(0.3), width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 10, color: badgeColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: badgeColor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // QR Scanner Button
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OwnerQRScannerScreen(isCheckIn: true)),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.textPrimary, size: 26),
                    ),
                  ),
                  // Notification Bell with count
                  GestureDetector(
                    onTap: () {
                      authVm.clearUnreadNotifications();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      child: Stack(
                        children: [
                          const Icon(Icons.notifications_none_rounded, color: AppTheme.textPrimary, size: 26),
                          if (authVm.unreadNotificationsCount > 0)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(color: Color(0xFF6C3AED), shape: BoxShape.circle),
                                child: Text(
                                  authVm.unreadNotificationsCount.toString(),
                                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                            )
                        ],
                      ),
                    ),
                  ),
                  // User avatar
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GymInfoScreen()),
                      );
                    },
                    child: Builder(
                      builder: (context) {
                        final gymLogo = authVm.gymInfo?['logo'] ?? authVm.gymInfo?['logo_url'] ?? '';
                        final gymId = authVm.gymInfo?['id'];
                        final cachedBase64 = gymId != null ? authVm.getCachedImage('gym_logo_$gymId') : null;

                        if (cachedBase64 != null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.memory(
                              base64Decode(cachedBase64),
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildDefaultGymLogo(),
                            ),
                          );
                        } else if (gymLogo.isNotEmpty && (gymLogo.startsWith('http') || gymLogo.startsWith('https'))) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.network(
                              gymLogo,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildDefaultGymLogo(),
                            ),
                          );
                        } else if (gymLogo.isNotEmpty) {
                          return Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                gymLogo.length > 2 ? gymLogo.substring(0, 2).toUpperCase() : gymLogo,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                            ),
                          );
                        }
                        return _buildDefaultGymLogo();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (repo.attendanceQueue.isNotEmpty || repo.crudQueue.isNotEmpty) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OnlineDatabaseScreen()),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.danger.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sync_problem_rounded, color: AppTheme.danger, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You have offline data pending sync. Tap to sync.',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.danger, size: 14),
                      ],
                    ),
                  ),
                ),
              ],

              // 2. Today's Overview Title & Datepicker
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Today's Overview",
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  GestureDetector(
                    onTap: () async {
                      if (repo != null) {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: repo.selectedDashboardDate,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          repo.setSelectedDashboardDate(date);
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            repo != null ? DateFormat('dd MMM, yyyy').format(repo.selectedDashboardDate) : '',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.textSecondary),
                        ],
                      ),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),

              // 2x2 Overview Cards Grid
              ResponsiveGrid(
                crossAxisCountMobile: 2,
                crossAxisCountTablet: 4,
                spacing: 12,
                runSpacing: 12,
                childAspectRatio: context.selectValue(mobile: 1.35, smallMobile: 1.15, tablet: 1.5),
                children: [
                  // Total Revenue stat
                  _buildStatTrendCard(
                    title: 'This Month Revenue',
                    value: revenueStr,
                    trend: revenueVal > 0 ? '↑ 12.5%' : '',
                    trendLabel: revenueVal > 0 ? 'vs yesterday' : 'no data',
                    trendColor: AppTheme.success,
                    sparklineData: revenueVal > 0 ? [40, 45, 52, 49, 65, 72, 85, 98, 110, 125] : [0],
                    sparklineColor: AppTheme.primary,
                    icon: Icons.currency_rupee_rounded,
                    iconColor: AppTheme.primary,
                  ),
                  // Today's Attendance progress
                  _buildProgressStatCard(
                    title: "Today's Attendance",
                    value: attendanceStr,
                    percentage: attendancePercent,
                    trend: checkInRecords > 0 ? '↑ 8.2%' : '',
                    trendLabel: checkInRecords > 0 ? 'vs yesterday' : 'no data',
                    trendColor: AppTheme.success,
                    icon: Icons.people_outline_rounded,
                    iconColor: Colors.green,
                  ),
                  // Active Members stat
                  _buildStatTrendCard(
                    title: 'Active Members',
                    value: activeMembersCount.toString(),
                    trend: activeMembersCount > 0 ? '↑ 18' : '',
                    trendLabel: activeMembersCount > 0 ? 'this month' : 'no data',
                    trendColor: AppTheme.success,
                    sparklineData: activeMembersCount > 0 ? [480, 490, 485, 500, 510, 505, 520, 525, 532] : [0],
                    sparklineColor: Colors.blue,
                    icon: Icons.people_rounded,
                    iconColor: Colors.blue,
                  ),
                  // Pending Payments stat
                  _buildStatTrendCard(
                    title: 'Pending Payments',
                    value: '₹${NumberFormat('#,##,###').format(financeVm.totalPendingPayments)}',
                    trend: financeVm.totalPendingPayments > 0 ? '↑ 8.2%' : '',
                    trendLabel: financeVm.totalPendingPayments > 0 ? 'vs yesterday' : 'no data',
                    trendColor: AppTheme.danger,
                    sparklineData: financeVm.totalPendingPayments > 0 ? [20, 22, 25, 23, 30, 35, 42, 45] : [0],
                    sparklineColor: Colors.orange,
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 24),


              // 4. Alerts Section (Action Required)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Alerts (Action Required)', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AlertsScreen()),
                      );
                    },
                    child: Text('View All', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_dbExpiringToday == 0 && _dbExpiring15Days == 0 && _dbExpired1Month == 0 && _dbPendingLeaves == 0 && _dbPendingHolidays == 0 && _dbPendingAdvances == 0)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Center(
                    child: Text(
                      'No active alerts',
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else ...[
                Builder(
                  builder: (context) {
                    final endingTodayAvatars = _getAvatars(repo.dashboardAlertsData['memberships_ending_today']?['avatars']);
                    final expiring15Avatars = [
                      ..._getAvatars(repo.dashboardAlertsData['memberships_expiring_1_day']?['avatars']),
                      ..._getAvatars(repo.dashboardAlertsData['memberships_expiring_3_days']?['avatars']),
                      ..._getAvatars(repo.dashboardAlertsData['memberships_expiring_7_days']?['avatars']),
                      ..._getAvatars(repo.dashboardAlertsData['memberships_expiring_15_days']?['avatars']),
                    ];
                    final expired1MonthAvatars = expired1MonthMembers.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList();
                    final leaveAvatars = _getAvatars(repo.dashboardAlertsData['staff_leave_requests']?['avatars']);
                    final holidayAvatars = _getAvatars(repo.dashboardAlertsData['holiday_requests']?['avatars']);
                    final advanceAvatars = _getAvatars(repo.dashboardAlertsData['staff_advance_requests']?['avatars']);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_dbExpired1Month > 0)
                          _buildAlertItem(
                            Icons.dangerous_outlined,
                            Colors.red,
                            const Color(0xFFFFECEF),
                            '$_dbExpired1Month Memberships',
                            'expired. Renewal follow-up recommended',
                            avatars: expired1MonthAvatars,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 3)),
                              );
                            },
                          ),
                        if (_dbExpiringToday > 0)
                          _buildAlertItem(
                            Icons.hourglass_empty,
                            Colors.red,
                            const Color(0xFFFFECEF),
                            '$_dbExpiringToday Memberships',
                            'ending today. Take action immediately',
                            avatars: endingTodayAvatars,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 2)),
                              );
                            },
                          ),
                        if (_dbExpiring15Days > 0)
                          _buildAlertItem(
                            Icons.calendar_today_rounded,
                            Colors.orange,
                            const Color(0xFFFFF6ED),
                            '$_dbExpiring15Days Memberships',
                            'expiring in 15 days. Follow-up recommended',
                            avatars: expiring15Avatars,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 0)),
                              );
                            },
                          ),
                        if (_dbPendingLeaves > 0)
                          _buildAlertItem(
                            Icons.description_outlined,
                            Colors.blue,
                            const Color(0xFFEFF6FF),
                            '$_dbPendingLeaves Staff Leave Requests',
                            'awaiting approval',
                            avatars: leaveAvatars,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AlertsScreen()),
                              );
                            },
                          ),
                        if (_dbPendingHolidays > 0)
                          _buildAlertItem(
                            Icons.beach_access_outlined,
                            Colors.purple,
                            const Color(0xFFFAF5FF),
                            '$_dbPendingHolidays Holiday Requests',
                            'from staff',
                            avatars: holidayAvatars,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AlertsScreen()),
                              );
                            },
                          ),
                        if (_dbPendingAdvances > 0)
                          _buildAlertItem(
                            Icons.account_balance_wallet_outlined,
                            Colors.deepPurple,
                            const Color(0xFFF5F3FF),
                            '$_dbPendingAdvances Staff Advance Requests',
                            'awaiting approval',
                            avatars: advanceAvatars,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AlertsScreen()),
                              );
                            },
                          ),
                      ],
                    );
                  }
                ),
              ],
              const SizedBox(height: 20),

              // 5. Quick Actions Panel
              Text('Quick Actions', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              ResponsiveGrid(
                crossAxisCountMobile: 4,
                crossAxisCountTablet: 8,
                spacing: 8,
                runSpacing: 8,
                childAspectRatio: context.selectValue(mobile: 0.9, smallMobile: 0.78, tablet: 1.1),
                children: [
                  _buildQuickActionBtn(
                    Icons.person_add_alt_1_outlined,
                    'Add Member',
                    onTap: () {
                      AddMemberSelectionSheet.show(context);
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.people_outline,
                    'Add Staff',
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const AddStaffSheet(),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.payment,
                    'Take Payment',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PendingPaymentsScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.calendar_today_rounded,
                    'Attendance',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AttendanceScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.fitness_center,
                    'Workout Plan',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WorkoutPlansScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.apple,
                    'Diet Plan',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DietPlansScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.analytics_outlined,
                    'Reports',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReportsScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.send_rounded,
                    'Broadcast',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BroadcastScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.currency_rupee_rounded,
                    'Pay Salary',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PendingSalaryListScreen()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 5. Recent Activities Feed
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Activities', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  InkWell(
                    onTap: () {
                      final authVm = Provider.of<AuthViewModel>(context, listen: false);
                      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ReceptionistActivityLogScreen(gymId: gymId)),
                      );
                    },
                    child: Text(
                      'View All',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (repo.getRecentActivities().isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Center(
                    child: Text(
                      'No recent activities',
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                CustomCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: List.generate(
                      repo.getRecentActivities().take(5).length,
                      (index) {
                        final act = repo.getRecentActivities()[index];
                        IconData iconData = Icons.info_outline;
                        Color bgColor = const Color(0xFFF3F4F6);
                        Color iconColor = const Color(0xFF4B5563);
                        bool isGreen = false;
 
                        if (act.activityType == 'Payment') {
                          iconData = Icons.currency_rupee_rounded;
                          bgColor = const Color(0xFFDCFCE7);
                          iconColor = const Color(0xFF15803D);
                          isGreen = true;
                        } else if (act.activityType == 'Advance') {
                          iconData = Icons.wallet_rounded;
                          bgColor = const Color(0xFFFEF3C7);
                          iconColor = const Color(0xFFD97706);
                        } else if (act.activityType == 'Leave') {
                          iconData = Icons.event_note_rounded;
                          bgColor = const Color(0xFFF3E8FF);
                          iconColor = const Color(0xFF7E22CE);
                        } else if (act.activityType == 'Membership') {
                          iconData = Icons.card_membership_rounded;
                          bgColor = const Color(0xFFDBEAFE);
                          iconColor = const Color(0xFF1D4ED8);
                        } else if (act.activityType == 'Expense') {
                          iconData = Icons.trending_down_rounded;
                          bgColor = const Color(0xFFFEE2E2);
                          iconColor = const Color(0xFFDC2626);
                        } else if (act.activityType == 'StaffAction') {
                          iconData = Icons.badge_outlined;
                          bgColor = const Color(0xFFFEF3C7);
                          iconColor = const Color(0xFFD97706);
                        }
 
                        // Format timestamp
                        final localTime = act.createdAt.toLocal();
                        final isToday = localTime.year == DateTime.now().year &&
                            localTime.month == DateTime.now().month &&
                            localTime.day == DateTime.now().day;
                        final timeStr = isToday
                            ? DateFormat('hh:mm a').format(localTime)
                            : DateFormat('dd MMM').format(localTime);
 
                        return Column(
                          children: [
                            _buildActivityItem(
                              name: act.title,
                              action: '',
                              meta: act.description,
                              time: timeStr,
                              icon: iconData,
                              iconBgColor: bgColor,
                              iconColor: iconColor,
                              isTimeGreen: isGreen,
                              onTap: () {
                                if (act.activityType == 'Payment' || act.activityType == 'Expense') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const FinanceScreen()),
                                  );
                                } else if (act.activityType == 'Leave') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const StaffScreen()),
                                  );
                                }
                              },
                            ),
                            if (index < repo.getRecentActivities().take(5).length - 1)
                              const Divider(height: 1, indent: 16, endIndent: 16),
                          ],
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatTrendCard({
    required String title,
    required String value,
    required String trend,
    required String trendLabel,
    required Color trendColor,
    required List<double> sparklineData,
    required Color sparklineColor,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 13),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              MiniSparkline(data: sparklineData, color: sparklineColor, height: 22, width: 52),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Text(trend, style: GoogleFonts.inter(fontSize: 10, color: trendColor, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(trendLabel, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStatCard({
    required String title,
    required String value,
    required double percentage,
    required String trend,
    required String trendLabel,
    required Color trendColor,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 13),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(value, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: percentage / 100,
                    minHeight: 4,
                    backgroundColor: iconColor.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('${percentage.toStringAsFixed(1)}%', style: GoogleFonts.inter(fontSize: 10, color: iconColor, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Text(trend, style: GoogleFonts.inter(fontSize: 10, color: trendColor, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(trendLabel, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _getAvatars(dynamic avatarsData) {
    if (avatarsData == null) return [];
    if (avatarsData is List) {
      return avatarsData.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  Widget _buildAlertItem(IconData icon, Color color, Color bgColor, String boldText, String text, {List<String>? avatars, String? badgeText, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        boldText,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        text,
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                if (avatars != null && avatars.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...avatars.map((url) => Align(
                        widthFactor: 0.6,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: CircleAvatar(
                            radius: 8,
                            backgroundImage: NetworkImage(
                              url.isNotEmpty 
                                  ? url 
                                  : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=100'
                            ),
                          ),
                        ),
                      )),
                      if (badgeText != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Text(
                            badgeText,
                            style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn(IconData icon, String label, {VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6), width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.primary, size: 20),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityItem({
    required String name,
    required String action,
    required String meta,
    required String time,
    String? avatarUrl,
    IconData? icon,
    Color? iconBgColor,
    Color? iconColor,
    bool isTimeGreen = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (avatarUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(avatarUrl, width: 28, height: 28, fit: BoxFit.cover),
              )
            else if (icon != null)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconBgColor ?? AppTheme.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor ?? AppTheme.primary, size: 16),
              )
            else
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.primaryLight,
                child: Text(name[0].toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
                      children: [
                        TextSpan(text: '$name ', style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: action),
                      ],
                    ),
                  ),
                  Text(meta, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Text(
              time,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: isTimeGreen ? const Color(0xFF15803D) : AppTheme.textMuted,
                fontWeight: isTimeGreen ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1.5),
      ),
      child: const Icon(
        Icons.person_rounded,
        color: AppTheme.primary,
        size: 20,
      ),
    );
  }

  Widget _buildDefaultGymLogo() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1.5),
      ),
      child: const Icon(
        Icons.fitness_center_rounded,
        color: AppTheme.primary,
        size: 18,
      ),
    );
  }

  Widget _buildAttendanceMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
