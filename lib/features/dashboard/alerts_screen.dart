import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/services/supabase_service.dart';
import 'expiring_memberships_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic> _alertsData = {};
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAlerts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        final response = await SupabaseService.client.rpc(
          'get_dashboard_alerts_v1',
          params: {'p_gym_id': gymId},
        );
        if (mounted) {
          setState(() {
            _alertsData = Map<String, dynamic>.from(response as Map);
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
    final endingToday = _alertsData['memberships_ending_today']?['count'] ?? 0;
    final expiring15 = _alertsData['memberships_expiring_15_days']?['count'] ?? 0;
    final staffLeaves = _alertsData['staff_leave_requests']?['count'] ?? 0;
    final holidayRequests = _alertsData['holiday_requests']?['count'] ?? 0;
    final paymentsPending = _alertsData['payments_pending']?['count'] ?? 0;
    final ptTrials = _alertsData['pt_trials']?['count'] ?? 0;

    final totalCount = endingToday + expiring15 + staffLeaves + holidayRequests + paymentsPending + ptTrials;

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
                          _buildAllAlertsTab(),
                          _buildMembershipAlertsTab(),
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

  Widget _buildAllAlertsTab() {
    final endingToday = _alertsData['memberships_ending_today']?['count'] ?? 0;
    final expiring15 = _alertsData['memberships_expiring_15_days']?['count'] ?? 0;
    final staffLeaves = _alertsData['staff_leave_requests']?['count'] ?? 0;
    final holidayRequests = _alertsData['holiday_requests']?['count'] ?? 0;
    final paymentsPending = _alertsData['payments_pending']?['count'] ?? 0;
    final ptTrials = _alertsData['pt_trials']?['count'] ?? 0;

    final endingAvatars = _getAvatars(_alertsData['memberships_ending_today']?['avatars']);
    final expiring15Avatars = _getAvatars(_alertsData['memberships_expiring_15_days']?['avatars']);
    final staffLeavesAvatars = _getAvatars(_alertsData['staff_leave_requests']?['avatars']);
    final holidayAvatars = _getAvatars(_alertsData['holiday_requests']?['avatars']);
    final paymentsAvatars = _getAvatars(_alertsData['payments_pending']?['avatars']);
    final ptAvatars = _getAvatars(_alertsData['pt_trials']?['avatars']);

    final totalCount = endingToday + expiring15 + staffLeaves + holidayRequests + paymentsPending + ptTrials;

    if (totalCount == 0) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _fetchAlerts,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (endingToday > 0 || expiring15 > 0) ...[
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
                    MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen()),
                  );
                },
              ),
            if (expiring15 > 0)
              _buildAlertCard(
                Icons.calendar_today_rounded,
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
                    MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen()),
                  );
                },
              ),
            const SizedBox(height: 16),
          ],
          if (staffLeaves > 0 || holidayRequests > 0) ...[
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
              ),
            const SizedBox(height: 16),
          ],
          if (paymentsPending > 0 || ptTrials > 0) ...[
            _buildSectionHeader('Other Alerts'),
            const SizedBox(height: 8),
            if (paymentsPending > 0)
              _buildAlertCard(
                Icons.payment_outlined,
                Colors.redAccent,
                const Color(0xFFFFECEF),
                '$paymentsPending ${paymentsPending == 1 ? "Payment" : "Payments"}',
                'still pending',
                '',
                avatars: paymentsAvatars,
                badgeText: _getBadgeText(paymentsPending, paymentsAvatars),
              ),
            if (ptTrials > 0)
              _buildAlertCard(
                Icons.fitness_center_outlined,
                Colors.green,
                const Color(0xFFE8F5E9),
                '$ptTrials ${ptTrials == 1 ? "PT Trial" : "PT Trials"}',
                'scheduled today',
                '',
                avatars: ptAvatars,
                badgeText: _getBadgeText(ptTrials, ptAvatars),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembershipAlertsTab() {
    final endingToday = _alertsData['memberships_ending_today']?['count'] ?? 0;
    final expiring15 = _alertsData['memberships_expiring_15_days']?['count'] ?? 0;

    final endingAvatars = _getAvatars(_alertsData['memberships_ending_today']?['avatars']);
    final expiring15Avatars = _getAvatars(_alertsData['memberships_expiring_15_days']?['avatars']);

    if (endingToday == 0 && expiring15 == 0) {
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
                  MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen()),
                );
              },
            ),
          if (expiring15 > 0)
            _buildAlertCard(
              Icons.calendar_today_rounded,
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
                  MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen()),
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

    final staffLeavesAvatars = _getAvatars(_alertsData['staff_leave_requests']?['avatars']);
    final holidayAvatars = _getAvatars(_alertsData['holiday_requests']?['avatars']);

    if (staffLeaves == 0 && holidayRequests == 0) {
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
