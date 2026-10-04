import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/gym_logo_cache_service.dart';
import '../../core/widgets/sparkline.dart';
import '../../core/widgets/sparkline_chart.dart';
import '../../core/widgets/app_cached_avatar.dart';
import '../../core/widgets/app_cached_gym_logo.dart';
import '../authentication/auth_viewmodel.dart';
import '../authentication/role_selection_screen.dart';
import '../subscription/owner_subscription_screen.dart';
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
import '../members/add_old_member_screen.dart';
import '../members/trial_members_screen.dart';
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
import '../../core/widgets/sidebar_drawer.dart';
import '../../core/navigation/app_router.dart';
import '../staff/add_staff_screen.dart';
import '../more/holidays_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  GymRepository? _repository;
  bool _showAllActivities = false;
  bool _isBannerDismissed = false;

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
        authVm.fetchSubscriptionStatus();
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

    if (authVm.gymInfo?['status'] == 'suspended') {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_flipped,
                    color: Color(0xFFEF4444),
                    size: 64,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Gym Suspended',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your gym access has been suspended by the GymOS Administrator due to non-payment or terms of service violation.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF94A3B8),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.email_outlined, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'support@gymos.tech',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await authVm.logout();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                          (route) => false,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text(
                      'Logout & Switch Account',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final repo = Provider.of<GymRepository>(context);
    final membersVm = Provider.of<MembersViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);
    final financeVm = Provider.of<FinanceViewModel>(context);
    final attendanceVm = Provider.of<AttendanceViewModel>(context);

    final gymName = authVm.gymInfo?['name'] ?? 'GYMOS';
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

    final subInfo = authVm.subscriptionInfo;
    final status = (subInfo?['status'] as String? ?? '').toLowerCase();
    
    int? trialDaysRemaining;
    if (status == 'trial') {
      final trialEndStr = subInfo?['trial_end'] as String?;
      if (trialEndStr != null) {
        final trialEnd = DateTime.tryParse(trialEndStr);
        if (trialEnd != null) {
          final now = DateTime.now();
          final diff = trialEnd.difference(now).inDays;
          if (diff >= 0 && diff <= 7) {
            trialDaysRemaining = diff;
          }
        }
      }
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: const SidebarDrawer(),
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (trialDaysRemaining != null)
                _buildTrialExpirationBanner(context, trialDaysRemaining),
              // 1. Mockup Header Row
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary, size: 26),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
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
                  // Gym Logo Avatar Header
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
                        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id']?.toString();
                        final gymName = authVm.gymInfo?['name']?.toString() ?? 'Gym';

                        return AppCachedGymLogo(
                          gymId: gymId,
                          logoUrl: gymLogo,
                          gymName: gymName,
                          size: 36,
                          borderRadius: BorderRadius.circular(18),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (repo.hasFailedQueueItems) ...[
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
                            'Data sync failed (${repo.failedQueueCount} item${repo.failedQueueCount > 1 ? 's' : ''}). Tap to review & retry.',
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
              Builder(
                builder: (context) {
                  final expiringTrials = repo.getTrialMembers().where((t) => t.isExpiringTodayOrExpired).toList();
                  final expiringTrialCount = expiringTrials.length;
                  final trialAvatars = expiringTrials.map((t) => t.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList();

                  if (_dbExpiringToday == 0 && _dbExpiring15Days == 0 && _dbExpired1Month == 0 && _dbPendingLeaves == 0 && _dbPendingHolidays == 0 && _dbPendingAdvances == 0 && expiringTrialCount == 0) {
                    return Container(
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
                    );
                  }

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
                      if (expiringTrialCount > 0)
                        _buildAlertItem(
                          Icons.timer_outlined,
                          Colors.deepOrange,
                          const Color(0xFFFFF2ED),
                          '$expiringTrialCount Trial Memberships',
                          'expiring today or expired. Convert to full member',
                          avatars: trialAvatars,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const TrialMembersScreen(initialFilter: 'Expiring / Expired')),
                            );
                          },
                        ),
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
              const SizedBox(height: 20),

              // 5. Quick Actions Panel
              Text('Quick Actions', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              ResponsiveGrid(
                crossAxisCountMobile: 4,
                crossAxisCountTablet: 8,
                spacing: 8,
                runSpacing: 8,
                childAspectRatio: context.selectValue(mobile: 1.05, smallMobile: 0.92, tablet: 1.25),
                children: [
                  _buildQuickActionBtn(
                    Icons.person_add_alt_1_outlined,
                    const Color(0xFF6C4EFF),
                    'Add Member',
                    onTap: () {
                      AddMemberSelectionSheet.show(context);
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.people_outline_rounded,
                    const Color(0xFF0EA5E9),
                    'Add Staff',
                    onTap: () {
                      Navigator.push(
                        context,
                        AppRouter.slideRoute(const AddStaffScreen(), slideUp: true),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.payments_outlined,
                    const Color(0xFF10B981),
                    'Take Payment',
                    fontSize: 8.0,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PendingPaymentsScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.calendar_today_rounded,
                    const Color(0xFFF59E0B),
                    'Attendance',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AttendanceScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.fitness_center_rounded,
                    const Color(0xFF3B82F6),
                    'Workout Plan',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WorkoutPlansScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.apple_rounded,
                    const Color(0xFFEC4899),
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
                    const Color(0xFF8B5CF6),
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
                    const Color(0xFF06B6D4),
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
                    const Color(0xFF14B8A6),
                    'Pay Salary',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PendingSalaryListScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.event_busy_outlined,
                    const Color(0xFFEF4444),
                    'Holidays',
                    onTap: () {
                      Navigator.push(
                        context,
                        AppRouter.slideRoute(const HolidaysScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.assignment_ind_outlined,
                    const Color(0xFFF97316),
                    'Trial Members',
                    fontSize: 8.0,
                    onTap: () {
                      Navigator.push(
                        context,
                        AppRouter.slideRoute(const TrialMembersScreen()),
                      );
                    },
                  ),
                  _buildQuickActionBtn(
                    Icons.history_rounded,
                    const Color(0xFFF59E0B),
                    'Old Member',
                    fontSize: 8.5,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AddOldMemberScreen()),
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
                            backgroundColor: const Color(0xFF6366F1),
                            backgroundImage: (url.isNotEmpty && !AppCachedAvatar.isDummyUrl(url))
                                ? NetworkImage(url)
                                : null,
                            child: (url.isEmpty || AppCachedAvatar.isDummyUrl(url))
                                ? const Icon(Icons.person, size: 10, color: Colors.white)
                                : null,
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

  Widget _buildQuickActionBtn(IconData icon, Color color, String label, {VoidCallback? onTap, double? fontSize}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.12)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: fontSize ?? 9.5, 
                  fontWeight: FontWeight.bold, 
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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

  Widget _buildTrialExpirationBanner(BuildContext context, int daysLeft) {
    if (_isBannerDismissed) return const SizedBox.shrink();

    final text = daysLeft == 0 
        ? "Your trial ends today. If you want to continue using Gym OS, please purchase a plan."
        : "Your trial ends in $daysLeft days. If you want to continue using Gym OS after $daysLeft days, please purchase a plan.";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF6C4EFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C4EFF).withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const OwnerSubscriptionScreen(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  onPressed: () {
                    setState(() {
                      _isBannerDismissed = true;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
