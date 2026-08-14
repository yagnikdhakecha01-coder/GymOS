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
import '../../more/notifications_screen.dart';

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
        'key': 'renew_membership',
        'label': 'Renew Membership',
        'icon': Icons.autorenew_rounded,
        'color': Colors.orange,
        'action': () {
          _showSearchMemberDialog(context, vm, 'Renew Membership');
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
        'key': 'take_payment',
        'label': 'Take Payment',
        'icon': Icons.payments_outlined,
        'color': Colors.blue,
        'action': () {
          _showSearchMemberDialog(context, vm, 'Take Payment');
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

  void _showSearchMemberDialog(BuildContext context, ReceptionistViewModel vm, String taskType) {
    // Search member sheet to select member for Payment, Renewal, or Reminder
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Select Member to $taskType',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
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
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder(
                      future: SupabaseService.client
                          .from('members')
                          .select()
                          .eq('gym_id', vm.staffRecord!.gymId)
                          .or('name.ilike.%$query%,phone.ilike.%$query%')
                          .limit(20),
                      builder: (context, AsyncSnapshot<List> snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final list = snapshot.data ?? [];
                        if (list.isEmpty) {
                          return const Center(child: Text('No members found.'));
                        }
                        return ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final member = list[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: NetworkImage(member['avatar'] ?? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200'),
                              ),
                              title: Text(member['name']),
                              subtitle: Text(member['phone']),
                              onTap: () {
                                Navigator.pop(context);
                                if (taskType == 'Renew Membership') {
                                  vm.logActivity('Membership Renewed', 'members', targetMember: member['name']);
                                } else if (taskType == 'Take Payment') {
                                  vm.logActivity('Payment Collected', 'finance', targetMember: member['name']);
                                } else if (taskType == 'Send Reminder') {
                                  vm.logActivity('Reminder Sent', 'members', targetMember: member['name']);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Successfully processed $taskType for ${member['name']}')),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddTransactionBottomSheet(BuildContext context, ReceptionistViewModel vm, String type) {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    
    final List<String> categories = type == 'Revenue' 
        ? ['Membership', 'Protein Sale', 'Personal Training', 'Locker Rent', 'Merchandise', 'Other']
        : ['Utilities', 'Salary', 'Rent', 'Other'];
        
    String selectedCategory = categories.first;

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
                          'Add $type',
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
                        backgroundColor: type == 'Revenue' ? Colors.green : AppTheme.danger,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final amt = double.tryParse(amountController.text) ?? 0.0;
                        final title = titleController.text.trim();
                        if (title.isNotEmpty && amt > 0) {
                          try {
                            await SupabaseService.client.from('finance_transactions').insert({
                              'gym_id': vm.staffRecord!.gymId,
                              'amount': amt,
                              'type': type,
                              'category': selectedCategory,
                              'payment_method': 'Cash',
                              'transaction_date': DateTime.now().toIso8601String(),
                              'expense_date': DateTime.now().toIso8601String().substring(0, 10),
                              'revenue_date': DateTime.now().toIso8601String().substring(0, 10),
                              'entry_date': DateTime.now().toIso8601String().substring(0, 10),
                              'created_by': SupabaseService.client.auth.currentUser?.id,
                              'created_by_info': 'Receptionist - ${vm.staffRecord!.name}',
                              'notes': title,
                            });
                            
                            vm.logActivity('$type Added: $title ($selectedCategory)', 'finance');
                            Navigator.pop(context);
                            vm.fetchDashboardStats();
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error adding transaction: $e')),
                            );
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a valid title and amount')),
                          );
                        }
                      },
                      child: Text(
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
