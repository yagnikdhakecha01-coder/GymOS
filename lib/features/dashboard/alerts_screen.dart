import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/services/supabase_service.dart';
import '../../core/repository/gym_repository.dart';
import 'expiring_memberships_screen.dart';
import '../members/members_viewmodel.dart';
import '../../core/models/member.dart';
import '../staff/portal/staff_request_approval_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMsg;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAlerts();
    
    // Periodically fetch from DB every 20 seconds for updates in the UI
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      _fetchAlertsQuietly();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// Reads alerts data from GymRepository (which may have locally decremented counts)
  Map<String, dynamic> get _alertsData {
    try {
      final repo = Provider.of<GymRepository>(context, listen: false);
      final data = Map<String, dynamic>.from(repo.dashboardAlertsData);

      // Override staff leave & advance counts from local pending items
      // This ensures approved items are excluded instantly even before sync
      final pendingLeaves = repo.leaveRequests.where((l) => l['status'] == 'Pending').length;
      final pendingAdvances = repo.salaryAdvances.where((a) => a['status'] == 'Pending').length;

      if (data['staff_leave_requests'] != null) {
        final rpcCount = (data['staff_leave_requests']['count'] as num?)?.toInt() ?? 0;
        data['staff_leave_requests'] = Map<String, dynamic>.from(data['staff_leave_requests']);
        data['staff_leave_requests']['count'] = repo.leaveRequests.isNotEmpty ? (rpcCount < pendingLeaves ? rpcCount : pendingLeaves) : rpcCount;
      }
      if (data['staff_advance_requests'] != null) {
        final rpcCount = (data['staff_advance_requests']['count'] as num?)?.toInt() ?? 0;
        data['staff_advance_requests'] = Map<String, dynamic>.from(data['staff_advance_requests']);
        data['staff_advance_requests']['count'] = repo.salaryAdvances.isNotEmpty ? (rpcCount < pendingAdvances ? rpcCount : pendingAdvances) : rpcCount;
      }

      return data;
    } catch (_) {
      return {};
    }
  }

  Future<void> _fetchAlerts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      
      if (gymId != null) {
        final repo = Provider.of<GymRepository>(context, listen: false);
        final response = await SupabaseService.client.rpc(
          'get_dashboard_alerts_v1',
          params: {'p_gym_id': gymId},
        );
        if (mounted) {
          // Store in repository so local decrements are respected
          repo.updateDashboardAlertsData(Map<String, dynamic>.from(response as Map));
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMsg = 'No active gym found.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchAlertsQuietly() async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      
      if (gymId != null && SupabaseService.isInitialized) {
        final repo = Provider.of<GymRepository>(context, listen: false);
        final response = await SupabaseService.client.rpc(
          'get_dashboard_alerts_v1',
          params: {'p_gym_id': gymId},
        );
        if (mounted) {
          repo.updateDashboardAlertsData(Map<String, dynamic>.from(response as Map));
          setState(() {});
        }
      }
    } catch (_) {
      // Fail silently in background quiet refresh
    }
  }

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

  List<String> _getAvatars(dynamic raw) {
    if (raw == null || raw is! List) return [];
    return raw
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty && e.startsWith('http'))
        .take(3)
        .toList();
  }

  String? _getBadgeText(int count, List<String> avatars) {
    if (count > avatars.length) {
      return '+${count - avatars.length}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    // Listen to GymRepository for real-time local count updates (e.g., after leave approval)
    Provider.of<GymRepository>(context);
    final allMembers = membersVm.allMembers;

    final endingTodayMembers = <Member>[];
    final expiring1Members = <Member>[];
    final expiring3Members = <Member>[];
    final expiring7Members = <Member>[];
    final expiring15Members = <Member>[];
    final expired1MonthMembers = <Member>[];

    for (final m in allMembers) {
      final daysLeft = _getDaysLeft(m);
      if (daysLeft == null) continue;
      if (daysLeft == 0) {
        endingTodayMembers.add(m);
      } else if (daysLeft == 1) {
        expiring1Members.add(m);
      } else if (daysLeft >= 2 && daysLeft <= 3) {
        expiring3Members.add(m);
      } else if (daysLeft >= 4 && daysLeft <= 7) {
        expiring7Members.add(m);
      } else if (daysLeft >= 8 && daysLeft <= 15) {
        expiring15Members.add(m);
      } else if (daysLeft >= -30 && daysLeft < 0) {
        expired1MonthMembers.add(m);
      }
    }

    final endingToday = endingTodayMembers.length;
    final expiring1 = expiring1Members.length;
    final expiring3 = expiring3Members.length;
    final expiring7 = expiring7Members.length;
    final expiring15 = expiring15Members.length;
    final expired1Month = expired1MonthMembers.length;

    final endingAvatars = endingTodayMembers.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList();
    final expiring1Avatars = expiring1Members.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList();
    final expiring3Avatars = expiring3Members.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList();
    final expiring7Avatars = expiring7Members.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList();
    final expiring15Avatars = expiring15Members.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList();
    final expired1MonthAvatars = expired1MonthMembers.map((m) => m.avatar).where((a) => a.isNotEmpty && a.startsWith('http')).take(3).toList();

    final staffLeaves = _alertsData['staff_leave_requests']?['count'] ?? 0;
    final holidayRequests = _alertsData['holiday_requests']?['count'] ?? 0;
    final staffAdvances = _alertsData['staff_advance_requests']?['count'] ?? 0;

    final staffLeavesAvatars = _getAvatars(_alertsData['staff_leave_requests']?['avatars']);
    final holidayAvatars = _getAvatars(_alertsData['holiday_requests']?['avatars']);
    final staffAdvancesAvatars = _getAvatars(_alertsData['staff_advance_requests']?['avatars']);

    final totalCount = endingToday + expiring1 + expiring3 + expiring7 + expiring15 + expired1Month + staffLeaves + holidayRequests + staffAdvances;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Alerts',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textPrimary),
            onPressed: _fetchAlerts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Tabs Container
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(4),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.normal),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: 'All $totalCount'),
                  Tab(text: 'Membership'),
                  Tab(text: 'Requests'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _errorMsg != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 44, color: AppTheme.danger),
                              const SizedBox(height: 12),
                              Text(
                                'Error loading alerts',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _errorMsg!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _fetchAlerts,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAllAlertsTab(
                            endingToday: endingToday,
                            expiring1: expiring1,
                            expiring3: expiring3,
                            expiring7: expiring7,
                            expiring15: expiring15,
                            expired1Month: expired1Month,
                            endingAvatars: endingAvatars,
                            expiring1Avatars: expiring1Avatars,
                            expiring3Avatars: expiring3Avatars,
                            expiring7Avatars: expiring7Avatars,
                            expiring15Avatars: expiring15Avatars,
                            expired1MonthAvatars: expired1MonthAvatars,
                            staffLeaves: staffLeaves,
                            holidayRequests: holidayRequests,
                            staffAdvances: staffAdvances,
                            staffLeavesAvatars: staffLeavesAvatars,
                            holidayAvatars: holidayAvatars,
                            staffAdvancesAvatars: staffAdvancesAvatars,
                          ),
                          _buildMembershipAlertsTab(
                            endingToday: endingToday,
                            expiring1: expiring1,
                            expiring3: expiring3,
                            expiring7: expiring7,
                            expiring15: expiring15,
                            expired1Month: expired1Month,
                            endingAvatars: endingAvatars,
                            expiring1Avatars: expiring1Avatars,
                            expiring3Avatars: expiring3Avatars,
                            expiring7Avatars: expiring7Avatars,
                            expiring15Avatars: expiring15Avatars,
                            expired1MonthAvatars: expired1MonthAvatars,
                          ),
                          _buildRequestsAlertsTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 48, color: AppTheme.success.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            'All Caught Up!',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'No active alerts at this moment.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildAllAlertsTab({
    required int endingToday,
    required int expiring1,
    required int expiring3,
    required int expiring7,
    required int expiring15,
    required int expired1Month,
    required List<String> endingAvatars,
    required List<String> expiring1Avatars,
    required List<String> expiring3Avatars,
    required List<String> expiring7Avatars,
    required List<String> expiring15Avatars,
    required List<String> expired1MonthAvatars,
    required int staffLeaves,
    required int holidayRequests,
    required int staffAdvances,
    required List<String> staffLeavesAvatars,
    required List<String> holidayAvatars,
    required List<String> staffAdvancesAvatars,
  }) {
    final totalCount = endingToday + expiring1 + expiring3 + expiring7 + expiring15 + expired1Month + staffLeaves + holidayRequests + staffAdvances;

    if (totalCount == 0) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _fetchAlerts,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (endingToday > 0 || expiring1 > 0 || expiring3 > 0 || expiring7 > 0 || expiring15 > 0 || expired1Month > 0) ...[
            _buildSectionHeader('Membership Alerts'),
            const SizedBox(height: 8),
            if (endingToday > 0)
              _buildAlertCard(
                Icons.hourglass_empty,
                Colors.red,
                const Color(0xFFFFECEF),
                '$endingToday ${endingToday == 1 ? "Membership" : "Memberships"}',
                'ending today',
                'Take action immediately',
                avatars: endingAvatars,
                badgeText: _getBadgeText(endingToday, endingAvatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 2)),
                  );
                },
              ),
            if (expiring1 > 0)
              _buildAlertCard(
                Icons.hourglass_bottom_rounded,
                Colors.redAccent,
                const Color(0xFFFFECEF),
                '$expiring1 ${expiring1 == 1 ? "Membership" : "Memberships"}',
                'expiring tomorrow',
                'Urgent follow-up needed',
                avatars: expiring1Avatars,
                badgeText: _getBadgeText(expiring1, expiring1Avatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 1)),
                  );
                },
              ),
            if (expiring3 > 0)
              _buildAlertCard(
                Icons.access_time_rounded,
                Colors.orange,
                const Color(0xFFFFF6ED),
                '$expiring3 ${expiring3 == 1 ? "Membership" : "Memberships"}',
                'expiring in 3 days',
                'Send payment reminder',
                avatars: expiring3Avatars,
                badgeText: _getBadgeText(expiring3, expiring3Avatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 1)),
                  );
                },
              ),
            if (expiring7 > 0)
              _buildAlertCard(
                Icons.calendar_today_rounded,
                Colors.amber,
                const Color(0xFFFFFBEB),
                '$expiring7 ${expiring7 == 1 ? "Membership" : "Memberships"}',
                'expiring in 7 days',
                'Send friendly alert',
                avatars: expiring7Avatars,
                badgeText: _getBadgeText(expiring7, expiring7Avatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 1)),
                  );
                },
              ),
            if (expiring15 > 0)
              _buildAlertCard(
                Icons.calendar_month_rounded,
                Colors.orange,
                const Color(0xFFFFF6ED),
                '$expiring15 ${expiring15 == 1 ? "Membership" : "Memberships"}',
                'expiring in 15 days',
                'Follow-up recommended',
                avatars: expiring15Avatars,
                badgeText: _getBadgeText(expiring15, expiring15Avatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 0)),
                  );
                },
              ),
            if (expired1Month > 0)
              _buildAlertCard(
                Icons.dangerous_outlined,
                Colors.red,
                const Color(0xFFFFECEF),
                '$expired1Month ${expired1Month == 1 ? "Membership" : "Memberships"}',
                'expired',
                'Renewal follow-up recommended',
                avatars: expired1MonthAvatars,
                badgeText: _getBadgeText(expired1Month, expired1MonthAvatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 3)),
                  );
                },
              ),
            const SizedBox(height: 16),
          ],
          if (staffLeaves > 0 || holidayRequests > 0 || staffAdvances > 0) ...[
            _buildSectionHeader('Staff Requests'),
            const SizedBox(height: 8),
            if (staffLeaves > 0)
              _buildAlertCard(
                Icons.description_outlined,
                Colors.blue,
                const Color(0xFFEFF6FF),
                '$staffLeaves ${staffLeaves == 1 ? "Staff Leave Request" : "Staff Leave Requests"}',
                'awaiting approval',
                '',
                avatars: staffLeavesAvatars,
                badgeText: _getBadgeText(staffLeaves, staffLeavesAvatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffRequestApprovalScreen(initialTabIndex: 0)),
                  );
                },
              ),
            if (holidayRequests > 0)
              _buildAlertCard(
                Icons.beach_access_outlined,
                Colors.purple,
                const Color(0xFFFAF5FF),
                '$holidayRequests ${holidayRequests == 1 ? "Holiday Request" : "Holiday Requests"}',
                'from staff',
                '',
                avatars: holidayAvatars,
                badgeText: _getBadgeText(holidayRequests, holidayAvatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffRequestApprovalScreen(initialTabIndex: 0)),
                  );
                },
              ),
            if (staffAdvances > 0)
              _buildAlertCard(
                Icons.account_balance_wallet_outlined,
                Colors.deepPurple,
                const Color(0xFFF5F3FF),
                '$staffAdvances ${staffAdvances == 1 ? "Staff Advance Request" : "Staff Advance Requests"}',
                'awaiting approval',
                '',
                avatars: staffAdvancesAvatars,
                badgeText: _getBadgeText(staffAdvances, staffAdvancesAvatars),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffRequestApprovalScreen(initialTabIndex: 1)),
                  );
                },
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildMembershipAlertsTab({
    required int endingToday,
    required int expiring1,
    required int expiring3,
    required int expiring7,
    required int expiring15,
    required int expired1Month,
    required List<String> endingAvatars,
    required List<String> expiring1Avatars,
    required List<String> expiring3Avatars,
    required List<String> expiring7Avatars,
    required List<String> expiring15Avatars,
    required List<String> expired1MonthAvatars,
  }) {
    if (endingToday == 0 && expiring1 == 0 && expiring3 == 0 && expiring7 == 0 && expiring15 == 0 && expired1Month == 0) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _fetchAlerts,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (endingToday > 0)
            _buildAlertCard(
              Icons.hourglass_empty,
              Colors.red,
              const Color(0xFFFFECEF),
              '$endingToday ${endingToday == 1 ? "Membership" : "Memberships"}',
              'ending today',
              'Take action immediately',
              avatars: endingAvatars,
              badgeText: _getBadgeText(endingToday, endingAvatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 2)),
                );
              },
            ),
          if (expiring1 > 0)
            _buildAlertCard(
              Icons.hourglass_bottom_rounded,
              Colors.redAccent,
              const Color(0xFFFFECEF),
              '$expiring1 ${expiring1 == 1 ? "Membership" : "Memberships"}',
              'expiring tomorrow',
              'Urgent follow-up needed',
              avatars: expiring1Avatars,
              badgeText: _getBadgeText(expiring1, expiring1Avatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 1)),
                );
              },
            ),
          if (expiring3 > 0)
            _buildAlertCard(
              Icons.access_time_rounded,
              Colors.orange,
              const Color(0xFFFFF6ED),
              '$expiring3 ${expiring3 == 1 ? "Membership" : "Memberships"}',
              'expiring in 3 days',
              'Send payment reminder',
              avatars: expiring3Avatars,
              badgeText: _getBadgeText(expiring3, expiring3Avatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 1)),
                );
              },
            ),
          if (expiring7 > 0)
            _buildAlertCard(
              Icons.calendar_today_rounded,
              Colors.amber,
              const Color(0xFFFFFBEB),
              '$expiring7 ${expiring7 == 1 ? "Membership" : "Memberships"}',
              'expiring in 7 days',
              'Send friendly alert',
              avatars: expiring7Avatars,
              badgeText: _getBadgeText(expiring7, expiring7Avatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 1)),
                );
              },
            ),
          if (expiring15 > 0)
            _buildAlertCard(
              Icons.calendar_month_rounded,
              Colors.orange,
              const Color(0xFFFFF6ED),
              '$expiring15 ${expiring15 == 1 ? "Membership" : "Memberships"}',
              'expiring in 15 days',
              'Follow-up recommended',
              avatars: expiring15Avatars,
              badgeText: _getBadgeText(expiring15, expiring15Avatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 0)),
                );
              },
            ),
          if (expired1Month > 0)
            _buildAlertCard(
              Icons.dangerous_outlined,
              Colors.red,
              const Color(0xFFFFECEF),
              '$expired1Month ${expired1Month == 1 ? "Membership" : "Memberships"}',
              'expired',
              'Renewal follow-up recommended',
              avatars: expired1MonthAvatars,
              badgeText: _getBadgeText(expired1Month, expired1MonthAvatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen(initialTabIndex: 3)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRequestsAlertsTab() {
    final staffLeaves = _alertsData['staff_leave_requests']?['count'] ?? 0;
    final holidayRequests = _alertsData['holiday_requests']?['count'] ?? 0;
    final staffAdvances = _alertsData['staff_advance_requests']?['count'] ?? 0;

    final staffLeavesAvatars = _getAvatars(_alertsData['staff_leave_requests']?['avatars']);
    final holidayAvatars = _getAvatars(_alertsData['holiday_requests']?['avatars']);
    final staffAdvancesAvatars = _getAvatars(_alertsData['staff_advance_requests']?['avatars']);

    if (staffLeaves == 0 && holidayRequests == 0 && staffAdvances == 0) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _fetchAlerts,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (staffLeaves > 0)
            _buildAlertCard(
              Icons.description_outlined,
              Colors.blue,
              const Color(0xFFEFF6FF),
              '$staffLeaves ${staffLeaves == 1 ? "Staff Leave Request" : "Staff Leave Requests"}',
              'awaiting approval',
              '',
              avatars: staffLeavesAvatars,
              badgeText: _getBadgeText(staffLeaves, staffLeavesAvatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StaffRequestApprovalScreen(initialTabIndex: 0)),
                );
              },
            ),
          if (holidayRequests > 0)
            _buildAlertCard(
              Icons.beach_access_outlined,
              Colors.purple,
              const Color(0xFFFAF5FF),
              '$holidayRequests ${holidayRequests == 1 ? "Holiday Request" : "Holiday Requests"}',
              'from staff',
              '',
              avatars: holidayAvatars,
              badgeText: _getBadgeText(holidayRequests, holidayAvatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StaffRequestApprovalScreen(initialTabIndex: 0)),
                );
              },
            ),
          if (staffAdvances > 0)
            _buildAlertCard(
              Icons.account_balance_wallet_outlined,
              Colors.deepPurple,
              const Color(0xFFF5F3FF),
              '$staffAdvances ${staffAdvances == 1 ? "Staff Advance Request" : "Staff Advance Requests"}',
              'awaiting approval',
              '',
              avatars: staffAdvancesAvatars,
              badgeText: _getBadgeText(staffAdvances, staffAdvancesAvatars),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StaffRequestApprovalScreen(initialTabIndex: 1)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
      ),
    );
  }

  Widget _buildAlertCard(
    IconData icon,
    Color color,
    Color bgColor,
    String boldText,
    String text,
    String subtext, {
    List<String>? avatars,
    String? badgeText,
    VoidCallback? onTap,
  }) {
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
            padding: const EdgeInsets.all(14),
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
                      Row(
                        children: [
                          Text(
                            boldText,
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              text,
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (subtext.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtext,
                          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
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
}
