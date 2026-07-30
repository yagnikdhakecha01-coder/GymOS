import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import 'expiring_memberships_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            icon: const Icon(Icons.tune_outlined, color: AppTheme.textPrimary),
            onPressed: () {},
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
                tabs: const [
                  Tab(text: 'All 6'),
                  Tab(text: 'Membership'),
                  Tab(text: 'Requests'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
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

  Widget _buildAllAlertsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Membership Alerts'),
        const SizedBox(height: 8),
        _buildAlertCard(
          Icons.hourglass_empty,
          Colors.red,
          const Color(0xFFFFECEF),
          '2 Memberships',
          'ending today',
          'Take action immediately',
          avatars: [
            'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=100'
          ],
          badgeText: '+1',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen()),
            );
          },
        ),
        _buildAlertCard(
          Icons.calendar_today_rounded,
          Colors.orange,
          const Color(0xFFFFF6ED),
          '18 Memberships',
          'expiring in 15 days',
          'Follow-up recommended',
          avatars: [
            'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=100'
          ],
          badgeText: '+15',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen()),
            );
          },
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Staff Requests'),
        const SizedBox(height: 8),
        _buildAlertCard(
          Icons.description_outlined,
          Colors.blue,
          const Color(0xFFEFF6FF),
          '3 Staff Leave Requests',
          'awaiting approval',
          '',
          avatars: [
            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&q=80&w=100'
          ],
        ),
        _buildAlertCard(
          Icons.beach_access_outlined,
          Colors.purple,
          const Color(0xFFFAF5FF),
          '5 Holiday Requests',
          'from staff',
          '',
          avatars: [
            'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&q=80&w=100'
          ],
          badgeText: '+2',
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Other Alerts'),
        const SizedBox(height: 8),
        _buildAlertCard(
          Icons.payment_outlined,
          Colors.redAccent,
          const Color(0xFFFFECEF),
          '7 Payments',
          'still pending',
          '',
        ),
        _buildAlertCard(
          Icons.fitness_center_outlined,
          Colors.green,
          const Color(0xFFE8F5E9),
          '4 PT Trials',
          'scheduled today',
          '',
        ),
      ],
    );
  }

  Widget _buildMembershipAlertsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAlertCard(
          Icons.hourglass_empty,
          Colors.red,
          const Color(0xFFFFECEF),
          '2 Memberships',
          'ending today',
          'Take action immediately',
          avatars: [
            'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=100'
          ],
          badgeText: '+1',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen()),
            );
          },
        ),
        _buildAlertCard(
          Icons.calendar_today_rounded,
          Colors.orange,
          const Color(0xFFFFF6ED),
          '18 Memberships',
          'expiring in 15 days',
          'Follow-up recommended',
          avatars: [
            'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=100'
          ],
          badgeText: '+15',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExpiringMembershipsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRequestsAlertsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAlertCard(
          Icons.description_outlined,
          Colors.blue,
          const Color(0xFFEFF6FF),
          '3 Staff Leave Requests',
          'awaiting approval',
          '',
          avatars: [
            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&q=80&w=100'
          ],
        ),
        _buildAlertCard(
          Icons.beach_access_outlined,
          Colors.purple,
          const Color(0xFFFAF5FF),
          '5 Holiday Requests',
          'from staff',
          '',
          avatars: [
            'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&q=80&w=100',
            'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&q=80&w=100'
          ],
          badgeText: '+2',
        ),
      ],
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
                if (avatars != null) ...[
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
                            backgroundImage: NetworkImage(url),
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
