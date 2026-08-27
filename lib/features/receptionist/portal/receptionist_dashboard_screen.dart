import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/gym_logo_cache_service.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../attendance/owner_scanner_screen.dart';
import '../../attendance/manual_attendance_screen.dart';
import '../../gym_settings/online_database_screen.dart';
import '../../../core/repository/gym_repository.dart';
import '../../../core/widgets/add_member_selection_sheet.dart';
import '../receptionist_viewmodel.dart';
import 'widgets/receptionist_restricted_widget.dart';
import '../../../core/theme/responsive.dart';
import 'receptionist_activity_log_screen.dart';
import '../../dashboard/gym_switcher_bottom_sheet.dart';
import '../../../core/widgets/sidebar_drawer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/success_dialog.dart';
import '../../../core/models/finance.dart';
import '../../finance/finance_viewmodel.dart';
import '../../more/notifications_screen.dart';
import '../../finance/pending_payments_screen.dart';
import '../../members/member_profile_screen.dart';
import '../../members/members_viewmodel.dart';
import '../../../core/models/member.dart';
import '../../dashboard/expiring_memberships_screen.dart';
import '../../dashboard/alerts_screen.dart';

class ReceptionistDashboardScreen extends StatefulWidget {
  const ReceptionistDashboardScreen({super.key});

  @override
  State<ReceptionistDashboardScreen> createState() => _ReceptionistDashboardScreenState();
}

class _ReceptionistDashboardScreenState extends State<ReceptionistDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final vm = Provider.of<ReceptionistViewModel>(context);
    final repo = Provider.of<GymRepository>(context);
    final staff = vm.staffRecord;
    final gymName = authVm.gymInfo?['name'] ?? 'GYMOS';

    return Scaffold(
      key: _scaffoldKey,
      drawer: const SidebarDrawer(),
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await vm.fetchDashboardStats();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppTheme.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header Section
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary, size: 26),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            gymName,
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
                                    'Receptionist • ${staff?.name ?? "Receptionist"}',
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
                        ],
                      ),
                    ),
                    // Refresh Database Sync Button
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary, size: 20),
                        tooltip: 'Sync & Refresh Database',
                        onPressed: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Syncing latest database records...'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                          final gymRepo = Provider.of<GymRepository>(context, listen: false);
                          final financeVm = Provider.of<FinanceViewModel>(context, listen: false);
                          final gymId = gymRepo.storage.getGymInfo()?['id'] ?? vm.staffRecord?.gymId;

                          await gymRepo.fetchTransactionsFromSupabase();
                          if (gymId != null && gymId.isNotEmpty) {
                            await financeVm.fetchFinanceSummary(gymId, DateTime.now());
                          }
                          await vm.fetchDashboardStats();

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Database synced & updated across all screens!'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    // Notification Button
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textPrimary, size: 22),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                              );
                            },
                          ),
                        ),
                        if (authVm.unreadNotificationsCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppTheme.danger,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Center(
                                child: Text(
                                  authVm.unreadNotificationsCount > 9 ? '9+' : '${authVm.unreadNotificationsCount}',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Gym Logo Avatar Header
                    Builder(
                      builder: (context) {
                        final gymLogo = authVm.gymInfo?['logo'] ?? authVm.gymInfo?['logo_url'] ?? '';
                        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id']?.toString();
                        final cachedBase64 = GymLogoCacheService.getCachedLogoBase64(authVm.storage, gymId, gymLogo);

                        if (cachedBase64 != null && cachedBase64.isNotEmpty) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.memory(
                              base64Decode(cachedBase64),
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
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
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => _buildDefaultGymLogo(),
                            ),
                          );
                        }
                        return _buildDefaultGymLogo();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (repo.hasStaleQueueItems(const Duration(seconds: 10))) ...[
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

                // Date display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        DateFormat('EEEE dd MMMM yyyy').format(DateTime.now()),
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Today's Overview (Grid Layout for Cards)
                Text(
                  "Today's Overview",
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 12),
                ResponsiveGrid(
                  crossAxisCountMobile: 3,
                  crossAxisCountTablet: 3,
                  spacing: 10,
                  runSpacing: 10,
                  childAspectRatio: context.selectValue(mobile: 0.85, smallMobile: 0.72, tablet: 1.25),
                  children: [
                    _buildStatCard(
                      icon: Icons.people_outline_rounded,
                      color: AppTheme.primary,
                      title: "Attendance",
                      value: "${vm.todayAttendanceCount} / ${vm.todayTotalExpected}",
                      subtitle: "${vm.todayTotalExpected > 0 ? ((vm.todayAttendanceCount / vm.todayTotalExpected) * 100).round() : 0}% present",
                    ),
                    _buildStatCard(
                      icon: Icons.person_add_alt_1_outlined,
                      color: Colors.green,
                      title: "New Members",
                      value: "${vm.newMembersCount}",
                      subtitle: "registered today",
                    ),
                    _buildStatCard(
                      icon: Icons.rotate_right_rounded,
                      color: Colors.orange,
                      title: "Pending Renewals",
                      value: "${vm.pendingRenewalsCount}",
                      subtitle: "expiring soon",
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2.5 Alerts (Action Required) Section
                _buildAlertsSection(context, vm),

                // 3. Quick Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Quick Actions",
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildQuickActionsGrid(context, vm),
                const SizedBox(height: 20),

                // 4. Today's Income & Expense (Green / Red Cards)
                Text(
                  "Today's Income & Expense",
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildFinanceQuickCard(
                        title: 'Income',
                        amount: '₹${NumberFormat('#,##,###').format(vm.todayIncome)}',
                        btnLabel: '+ Add Income',
                        btnColor: Colors.green,
                        onTap: () {
                          if (vm.hasPermission('add_income')) {
                            _showAddTransactionBottomSheet(context, vm, 'Revenue');
                          } else {
                            _showRestrictedSnackbar(context, 'Add Income');
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildFinanceQuickCard(
                        title: 'Expense',
                        amount: '₹${NumberFormat('#,##,###').format(vm.todayExpense)}',
                        btnLabel: '+ Add Expense',
                        btnColor: Colors.red,
                        onTap: () {
                          if (vm.hasPermission('add_expense')) {
                            _showAddTransactionBottomSheet(context, vm, 'Expense');
                          } else {
                            _showRestrictedSnackbar(context, 'Add Expense');
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 5. Recent Activities
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Recent Activities",
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ReceptionistActivityLogScreen(gymId: vm.staffRecord!.gymId)),
                        );
                      },
                      child: Text(
                        "View All",
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildRecentActivitiesList(vm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning 👋';
    if (hour < 17) return 'Good Afternoon 👋';
    return 'Good Evening 👋';
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 8, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceQuickCard({
    required String title,
    required String amount,
    required String btnLabel,
    required Color btnColor,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: btnColor.withOpacity(0.08),
                foregroundColor: btnColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                btnLabel,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context, ReceptionistViewModel vm) {
    // Generate permitted quick actions
    final List<Map<String, dynamic>> allActions = [
      {
        'key': 'add_member',
        'label': 'Add Member',
        'icon': Icons.person_add_outlined,
        'color': AppTheme.primary,
        'action': () {
          AddMemberSelectionSheet.show(context);
        }
      },
      {
        'key': 'take_payment',
        'label': 'Take Payment',
        'icon': Icons.payments_outlined,
        'color': Colors.blue,
        'action': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PendingPaymentsScreen()),
          );
        }
      },
      {
        'key': 'add_income',
        'label': 'Add Income',
        'icon': Icons.add_chart_rounded,
        'color': Colors.teal,
        'action': () {
          _showAddTransactionBottomSheet(context, vm, 'Revenue');
        }
      },
      {
        'key': 'add_expense',
        'label': 'Add Expense',
        'icon': Icons.money_off_rounded,
        'color': Colors.redAccent,
        'action': () {
          _showAddTransactionBottomSheet(context, vm, 'Expense');
        }
      },
      {
        'key': 'renew_membership',
        'label': 'Renew Membership',
        'icon': Icons.autorenew_rounded,
        'color': Colors.orange,
        'action': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 3)),
          );
        }
      },
      {
        'key': 'scan_attendance',
        'label': 'Scan Attendance',
        'icon': Icons.qr_code_scanner_rounded,
        'color': Colors.green,
        'action': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OwnerQRScannerScreen(isCheckIn: true)),
          );
        }
      },
      {
        'key': 'scan_attendance',
        'label': 'Manual Attendance',
        'icon': Icons.edit_calendar_rounded,
        'color': AppTheme.primary,
        'action': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ManualAttendanceScreen()),
          );
        }
      },
      {
        'key': 'send_reminder',
        'label': 'Send Reminder',
        'icon': Icons.notifications_active_outlined,
        'color': Colors.amber,
        'action': () {
          _showSearchMemberDialog(context, vm, 'Send Reminder');
        }
      },
      {
        'key': 'broadcast',
        'label': 'Broadcast',
        'icon': Icons.campaign_outlined,
        'color': Colors.purpleAccent,
        'action': () {
          _showBroadcastDialog(context, vm);
        }
      },
    ];

    // Filter quick actions based on live permissions
    final activeActions = allActions.where((act) => vm.hasPermission(act['key'] as String)).toList();

    if (activeActions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Center(
          child: Text(
            'All Quick Actions are disabled by owner.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    return ResponsiveGrid(
      crossAxisCountMobile: 4,
      crossAxisCountTablet: 8,
      spacing: 8,
      runSpacing: 8,
      childAspectRatio: context.selectValue(mobile: 1.05, smallMobile: 0.92, tablet: 1.25),
      children: List.generate(activeActions.length, (idx) {
        final act = activeActions[idx];
        final color = act['color'] as Color;
        return GestureDetector(
          onTap: act['action'] as VoidCallback,
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
                  child: Icon(act['icon'] as IconData, color: color, size: 18),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    act['label'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
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
      }),
    );
  }

  Widget _buildRecentActivitiesList(ReceptionistViewModel vm) {
    if (vm.recentActivities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Center(
          child: Text(
            'No recent activities logged.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: vm.recentActivities.length > 5 ? 5 : vm.recentActivities.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
        itemBuilder: (context, idx) {
          final log = vm.recentActivities[idx];
          final timestamp = DateTime.parse(log['created_at'] as String);
          final timeStr = DateFormat('hh:mm a').format(timestamp.toLocal());
          
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: AppTheme.primary.withOpacity(0.1),
              child: Icon(_getActivityIcon(log['module']), size: 14, color: AppTheme.primary),
            ),
            title: Text(
              log['action'] ?? '',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            subtitle: Text(
              'By ${log['staff_name']} (${log['staff_role']}) ${log['target_member'] != '' ? '• ${log['target_member']}' : ''}',
              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
            ),
            trailing: Text(
              timeStr,
              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
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

  void _showRestrictedSnackbar(BuildContext context, String actionName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$actionName is restricted by the gym owner.'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Widget _buildAlertsSection(BuildContext context, ReceptionistViewModel vm) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final allMembers = membersVm.allMembers;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final List<Member> expired30Days = [];
    final List<Member> endingToday = [];
    final List<Member> expiring7Days = [];
    final List<Member> expiring15Days = [];

    for (final m in allMembers) {
      final expStr = m.extraFields['expiryDate'] as String?;
      final status = m.status.toLowerCase();

      if (expStr != null && expStr.isNotEmpty) {
        try {
          final expDate = DateTime.parse(expStr);
          final daysDiff = expDate.difference(todayStart).inDays;

          if (daysDiff < 0 && daysDiff >= -30) {
            expired30Days.add(m);
          } else if (daysDiff == 0 || (expDate.isAfter(todayStart) && expDate.isBefore(todayEnd))) {
            endingToday.add(m);
          } else if (daysDiff > 0 && daysDiff <= 7) {
            expiring7Days.add(m);
          } else if (daysDiff > 7 && daysDiff <= 15) {
            expiring15Days.add(m);
          }
        } catch (_) {
          if (status == 'expired' || status == 'inactive') {
            expired30Days.add(m);
          }
        }
      } else if (status == 'expired' || status == 'inactive') {
        expired30Days.add(m);
      }
    }

    final pendingDues = allMembers.where((m) => m.pendingAmount > 0).toList();
    final double totalPendingAmt = pendingDues.fold(0.0, (sum, m) => sum + m.pendingAmount);

    final canRenew = vm.hasPermission('renew_membership') || vm.hasPermission('view_members');
    final canTakePayment = vm.hasPermission('take_payment');

    final bool hasAnyAlert = expired30Days.isNotEmpty || endingToday.isNotEmpty || expiring7Days.isNotEmpty || expiring15Days.isNotEmpty || pendingDues.isNotEmpty;

    if (!hasAnyAlert || (!canRenew && !canTakePayment)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined, color: AppTheme.danger, size: 18),
                const SizedBox(width: 6),
                Text(
                  "Alerts (Action Required)",
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
              ],
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlertsScreen()),
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
        if (canRenew && expired30Days.isNotEmpty)
          _buildAlertCardItem(
            icon: Icons.dangerous_outlined,
            iconColor: Colors.red,
            bgColor: const Color(0xFFFFECEF),
            title: "${expired30Days.length} Memberships Expired (last 30 days)",
            subtitle: "Renewal follow-up recommended immediately",
            avatars: expired30Days.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 3)),
              );
            },
          ),
        if (canRenew && endingToday.isNotEmpty)
          _buildAlertCardItem(
            icon: Icons.hourglass_empty,
            iconColor: Colors.red,
            bgColor: const Color(0xFFFFECEF),
            title: "${endingToday.length} Memberships Ending Today",
            subtitle: "Take action immediately to collect renewal",
            avatars: endingToday.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 2)),
              );
            },
          ),
        if (canRenew && expiring7Days.isNotEmpty)
          _buildAlertCardItem(
            icon: Icons.calendar_month_outlined,
            iconColor: Colors.orange,
            bgColor: const Color(0xFFFFF6ED),
            title: "${expiring7Days.length} Memberships Expiring in 7 Days",
            subtitle: "Follow-up recommended before expiry",
            avatars: expiring7Days.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 1)),
              );
            },
          ),
        if (canRenew && expiring15Days.isNotEmpty)
          _buildAlertCardItem(
            icon: Icons.calendar_today_rounded,
            iconColor: Colors.orange,
            bgColor: const Color(0xFFFFF6ED),
            title: "${expiring15Days.length} Memberships Expiring in 15 Days",
            subtitle: "Follow-up recommended",
            avatars: expiring15Days.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 0)),
              );
            },
          ),
        if (canTakePayment && pendingDues.isNotEmpty)
          _buildAlertCardItem(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: Colors.blueAccent,
            bgColor: const Color(0xFFEFF6FF),
            title: "${pendingDues.length} Members with Pending Dues (₹${NumberFormat('#,##,###').format(totalPendingAmt)})",
            subtitle: "Collect pending fees & record payment entries",
            avatars: pendingDues.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PendingPaymentsScreen()),
              );
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildAlertCardItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    List<String>? avatars,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: iconColor, width: 4),
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
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                if (avatars != null && avatars.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: avatars.map((url) => Align(
                      widthFactor: 0.6,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundImage: NetworkImage(
                            url.isNotEmpty 
                                ? url 
                                : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=100',
                          ),
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(Icons.arrow_forward_ios_rounded, color: iconColor, size: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSendReminderSheet(BuildContext context, Member member, ReceptionistViewModel vm) {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymName = authVm.gymInfo?['name'] ?? 'Gym';

    String expDateStr = 'Soon';
    final exp = member.extraFields['expiryDate'] as String?;
    if (exp != null && exp.isNotEmpty) {
      try {
        expDateStr = DateFormat('dd MMM yyyy').format(DateTime.parse(exp));
      } catch (_) {
        expDateStr = exp;
      }
    }

    String defaultMsg = 'Dear ${member.name},\n\nThis is a friendly reminder that your gym membership at $gymName is expiring on $expDateStr.';
    if (member.pendingAmount > 0) {
      defaultMsg += '\nPending Balance: ₹${NumberFormat('#,##,###').format(member.pendingAmount.abs())}.';
    }
    defaultMsg += '\nPlease renew your membership to continue your workouts uninterrupted!\n\nThank you,\n$gymName Management';

    final msgController = TextEditingController(text: defaultMsg);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: NetworkImage(
                      member.avatar.isNotEmpty
                          ? member.avatar
                          : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send Renewal Reminder',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'To: ${member.name} (${member.phone})',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Reminder Message Preview:',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: msgController,
                maxLines: 5,
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                  fillColor: AppTheme.background,
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20),
                label: Text(
                  'Send via WhatsApp',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  vm.logActivity('Reminder Sent: ${member.name}', 'members', targetMember: member.name);

                  String rawPhone = member.phone.replaceAll(RegExp(r'[^\d]'), '');
                  if (rawPhone.length == 10) {
                    rawPhone = '91$rawPhone';
                  }

                  final message = msgController.text.trim();
                  final url = Uri.parse("https://wa.me/$rawPhone?text=${Uri.encodeComponent(message)}");

                  try {
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not launch WhatsApp. Please check if WhatsApp is installed.')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error launching WhatsApp: $e')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSearchMemberDialog(BuildContext context, ReceptionistViewModel vm, String taskType) {
    final membersVm = Provider.of<MembersViewModel>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            final now = DateTime.now();

            // Filter members from MembersViewModel
            List<Member> processedMembers = membersVm.allMembers.where((m) {
              final matchesQuery = m.name.toLowerCase().contains(query.toLowerCase()) || m.phone.contains(query);
              if (!matchesQuery) return false;

              if (taskType == 'Renew Membership') {
                final status = m.status.toLowerCase();
                bool isExpiredOrExpiring = status == 'expired' || status == 'inactive' || status == 'pending activation';
                final exp = m.extraFields['expiryDate'] as String?;
                if (!isExpiredOrExpiring && exp != null && exp.isNotEmpty) {
                  try {
                    final expDate = DateTime.parse(exp);
                    final diff = expDate.difference(now).inDays;
                    if (diff <= 30) {
                      isExpiredOrExpiring = true;
                    }
                  } catch (_) {}
                }
                return isExpiredOrExpiring;
              } else if (taskType == 'Send Reminder') {
                final status = m.status.toLowerCase();
                final bool isExpiredOrPending = status == 'expired' || status == 'inactive' || m.pendingAmount > 0;
                final exp = m.extraFields['expiryDate'] as String?;
                bool expiringSoon = false;
                if (exp != null && exp.isNotEmpty) {
                  try {
                    final expDate = DateTime.parse(exp);
                    final diff = expDate.difference(now).inDays;
                    if (diff <= 15) expiringSoon = true;
                  } catch (_) {}
                }
                return isExpiredOrPending || expiringSoon;
              }

              return true;
            }).toList();

            if (taskType == 'Renew Membership' || taskType == 'Send Reminder') {
              // Sort: Most recently expired / soonest expiring members AT THE TOP
              processedMembers.sort((a, b) {
                DateTime dateA = DateTime(1970);
                DateTime dateB = DateTime(1970);

                final expA = a.extraFields['expiryDate'] as String?;
                final expB = b.extraFields['expiryDate'] as String?;
                if (expA != null && expA.isNotEmpty) {
                  try { dateA = DateTime.parse(expA); } catch (_) {}
                }
                if (expB != null && expB.isNotEmpty) {
                  try { dateB = DateTime.parse(expB); } catch (_) {}
                }

                // Descending by date so recent expired / soonest expiring members are on top
                return dateB.compareTo(dateA);
              });
            }

            return Container(
              padding: const EdgeInsets.all(16),
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    taskType == 'Renew Membership'
                        ? 'Select Expired / Expiring Member to Renew'
                        : 'Select Member to $taskType',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (val) {
                      setStateSheet(() {
                        query = val;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: processedMembers.isEmpty
                        ? Center(
                            child: Text(
                              taskType == 'Renew Membership'
                                  ? 'No expired or expiring members found.'
                                  : 'No members found.',
                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: processedMembers.length,
                            itemBuilder: (context, index) {
                              final member = processedMembers[index];
                              
                              String expSub = 'No expiry date';
                              final exp = member.extraFields['expiryDate'] as String?;
                              if (exp != null && exp.isNotEmpty) {
                                try {
                                  expSub = 'Expires: ${DateFormat('dd MMM yyyy').format(DateTime.parse(exp))}';
                                } catch (_) {
                                  expSub = 'Expires: $exp';
                                }
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.background,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: NetworkImage(
                                      member.avatar.isNotEmpty
                                          ? member.avatar
                                          : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200',
                                    ),
                                  ),
                                  title: Text(
                                    member.name,
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  ),
                                  subtitle: Text(
                                    '${member.phone} • $expSub',
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (member.status == 'Active' ? Colors.green : Colors.red).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      member.status,
                                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: member.status == 'Active' ? Colors.green : Colors.red),
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (taskType == 'Send Reminder') {
                                      _showSendReminderSheet(context, member, vm);
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => MemberProfileScreen(member: member)),
                                      );
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddTransactionBottomSheet(BuildContext context, ReceptionistViewModel vm, String type) {
    final isIncome = type == 'Income' || type == 'Revenue';
    final displayType = isIncome ? 'Income' : 'Expense';
    final dbType = isIncome ? 'Revenue' : 'Expense';

    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final categories = isIncome
        ? ['Membership', 'Personal Training', 'Protein Sale', 'Locker Rent', 'Merchandise', 'Other']
        : ['Salary', 'Rent', 'Utilities', 'Maintenance', 'Equipment', 'Other'];
    String selectedCategory = categories.first;
    DateTime selectedTxDate = DateTime.now();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add $displayType',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // DATE SELECTION FIELD (INCOME DATE / EXPENSE DATE)
                    Text(
                      isIncome ? 'INCOME DATE' : 'EXPENSE DATE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedTxDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setModalState(() {
                            selectedTxDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('dd MMMM yyyy').format(selectedTxDate),
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                            ),
                            const Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'TITLE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Monthly Fee, Gym Rent, Electric bill',
                        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: GoogleFonts.inter(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'AMOUNT (₹)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Enter amount in ₹',
                        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'CATEGORY',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCategory,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                          items: categories.map((String cat) {
                            return DropdownMenuItem<String>(
                              value: cat,
                              child: Text(
                                cat,
                                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedCategory = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isIncome ? Colors.green : AppTheme.danger,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final amt = double.tryParse(amountController.text) ?? 0.0;
                              final title = titleController.text.trim();
                              if (title.isEmpty || amt <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter a valid title and amount greater than 0.')),
                                );
                                return;
                              }

                              setModalState(() {
                                isSaving = true;
                              });

                              final gymRepo = Provider.of<GymRepository>(context, listen: false);
                              final financeVm = Provider.of<FinanceViewModel>(context, listen: false);

                              final selectedDateStr = DateFormat('yyyy-MM-dd').format(selectedTxDate);
                              final txDateIso = DateTime(
                                selectedTxDate.year,
                                selectedTxDate.month,
                                selectedTxDate.day,
                                DateTime.now().hour,
                                DateTime.now().minute,
                                DateTime.now().second,
                              ).toIso8601String();
                              final gymId = vm.staffRecord?.gymId ?? '';

                              final tx = FinanceTransaction(
                                id: '',
                                gymId: gymId,
                                title: title,
                                amount: amt,
                                type: dbType,
                                category: selectedCategory,
                                paymentMethod: 'Cash',
                                date: DateFormat('dd MMM yyyy').format(selectedTxDate),
                                transactionDate: txDateIso,
                                expenseDate: selectedDateStr,
                                revenueDate: selectedDateStr,
                                entryDate: selectedDateStr,
                                notes: title,
                                createdByInfo: 'Receptionist - ${vm.staffRecord?.name ?? ''}',
                              );

                              // 1. Single unified transaction save (updates local cache, performs single upsert to DB, no duplicates!)
                              await gymRepo.saveTransaction(tx);

                              // 2. Log activity, refresh all viewmodels, close modal & show success dialog
                              vm.logActivity('$displayType Added: $title ($selectedCategory - ₹${NumberFormat('#,##,###').format(amt)})', 'finance');
                              
                              if (context.mounted) {
                                Navigator.pop(context);
                                vm.fetchDashboardStats();
                                await gymRepo.fetchTransactionsFromSupabase();
                                if (gymId.isNotEmpty) {
                                  await financeVm.fetchFinanceSummary(gymId, selectedTxDate);
                                }

                                SuccessDialog.show(
                                  context,
                                  title: '$displayType Saved Successfully!',
                                  message: '₹${NumberFormat('#,##,###').format(amt)} recorded for $title ($selectedCategory) on ${DateFormat('dd MMM yyyy').format(selectedTxDate)}.',
                                );
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Save $type',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showBroadcastDialog(BuildContext context, ReceptionistViewModel vm) {
    final msgController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Broadcast Announcement', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: msgController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Enter announcement message...'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final msg = msgController.text.trim();
                if (msg.isNotEmpty) {
                  vm.logActivity('Broadcast Sent: $msg', 'more');
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Announcement broadcasted successfully.')),
                  );
                }
              },
              child: const Text('Send'),
            )
          ],
        );
      },
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
}
