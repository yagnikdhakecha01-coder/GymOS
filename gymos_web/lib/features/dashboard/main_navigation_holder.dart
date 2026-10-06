import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/auth_viewmodel.dart';
import 'dashboard_screen.dart';
import '../members/members_screen.dart';
import '../staff/staff_screen.dart';
import '../finance/finance_screen.dart';
import '../more/more_screen.dart';
import '../subscription/owner_subscription_screen.dart';
import 'support_tickets_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/local_storage.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/widgets/desktop_web_sidebar.dart';
import '../auth/web_qr_login_screen.dart';

class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({Key? key}) : super(key: key);

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _statusCheckTimer;
  bool _isCheckingStatus = false;

  // Support Tickets State
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedPriority = 'medium';
  List<Map<String, dynamic>> _tickets = [];
  bool _loadingTickets = false;
  int _activeTab = 0; // 0 = Raise Ticket, 1 = Ticket History

  final List<Widget> _screens = [
    const DashboardScreen(),
    const MembersScreen(),
    const FinanceScreen(),
    const StaffScreen(),
    const MoreScreen(),
  ];

  Timer? _webSessionWatcherTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkGymStatus();
      try {
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        final repo = Provider.of<GymRepository>(context, listen: false);
        final gymId = authVm.activeAssociation?.gymId ?? 
                      authVm.gymInfo?['id'] ?? 
                      authVm.storage.getGymInfo()?['id'];
        if (gymId != null && gymId.toString().isNotEmpty) {
          await repo.performInitialSync(gymId.toString());
        }
      } catch (_) {}
    });
    _startStatusCheckTimer();
    _startWebSessionWatcher();
    _fetchTickets();
  }

  void _startWebSessionWatcher() {
    _webSessionWatcherTimer?.cancel();
    _webSessionWatcherTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!mounted) return;
      final storage = LocalStorageService.instance;
      final token = storage?.getString('gymos_web_session_token');
      if (token == null || token.isEmpty) return;

      try {
        final res = await SupabaseService.client
            .from('web_login_sessions')
            .select('status')
            .or('token.eq.$token,session_token.eq.$token')
            .maybeSingle();

        if (res != null) {
          final status = res['status']?.toString();
          if (status == 'logged_out' || status == 'revoked' || status == 'rejected') {
            timer.cancel();
            if (storage != null) {
              await storage.setLoggedIn(false);
              await storage.setBool('gymos_web_permanent_session', false);
              await storage.remove('gymos_web_session_token');
            }
            if (mounted) {
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WebQrLoginScreen()),
                (route) => false,
              );
            }
          }
        }
      } catch (_) {}
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkGymStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusCheckTimer?.cancel();
    _webSessionWatcherTimer?.cancel();
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _checkGymStatus() async {
    if (_isCheckingStatus) return;
    _isCheckingStatus = true;

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.gymInfo?['id'];
      if (gymId == null || !SupabaseService.isInitialized) {
        _isCheckingStatus = false;
        return;
      }

      final res = await SupabaseService.client
          .from('gyms')
          .select('status')
          .eq('id', gymId)
          .maybeSingle();

      await authVm.fetchSubscriptionStatus();

      if (res != null && res['status'] != null) {
        final newStatus = res['status'] as String;
        final currentStatus = authVm.gymInfo?['status'] as String? ?? 'active';

        if (newStatus != currentStatus) {
          // Update auth viewmodel and reload profile
          await authVm.loadCurrentProfile();
          if (mounted) {
            setState(() {});
            if (newStatus == 'suspended') {
              _fetchTickets();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Gym status check failed: $e");
    } finally {
      if (mounted) {
        setState(() {});
      }
      _isCheckingStatus = false;
    }
  }

  void _startStatusCheckTimer() {
    // Check gym status periodically (every 15 minutes) as gentle fallback
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      await _checkGymStatus();
    });
  }

  Future<void> _fetchTickets() async {
    if (!mounted) return;
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.gymInfo?['id'];
    if (gymId == null || !SupabaseService.isInitialized) return;

    try {
      setState(() => _loadingTickets = true);
      final List response = await SupabaseService.client
          .from('support_tickets')
          .select()
          .eq('gym_id', gymId)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _tickets = List<Map<String, dynamic>>.from(response);
          _loadingTickets = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch tickets: $e");
      if (mounted) {
        setState(() => _loadingTickets = false);
      }
    }
  }

  Future<void> _createTicket() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    if (title.isEmpty || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter ticket title and description.'), backgroundColor: Colors.red),
      );
      return;
    }

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.gymInfo?['id'];
    final gymName = authVm.gymInfo?['name'] ?? 'GYMOS';
    final ownerId = authVm.currentUser?.id;

    if (gymId == null || ownerId == null || !SupabaseService.isInitialized) return;

    try {
      await SupabaseService.client.from('support_tickets').insert({
        'title': title,
        'description': desc,
        'priority': _selectedPriority,
        'status': 'Open',
        'gym_id': gymId,
        'gym_name': gymName,
        'owner_id': ownerId,
      });

      _titleController.clear();
      _descController.clear();
      if (mounted) {
        setState(() {
          _selectedPriority = 'medium';
          _activeTab = 1; // Switch to history list to show ticket
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support ticket raised successfully!'), backgroundColor: AppTheme.success),
      );

      _fetchTickets();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final isSuspended = authVm.gymInfo?['status'] == 'suspended';
    final isLockedByAdmin = authVm.gymInfo?['is_locked'] == true;
    final isExpired = authVm.isSubscriptionExpired || isLockedByAdmin;

    if (isSuspended) {
      return _buildSuspendedScreen(context, authVm);
    }

    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final repo = Provider.of<GymRepository>(context);
    final activeMembersCount = repo.activeMembersCount;

    final outerScaffold = Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: isDesktop
          ? Row(
              children: [
                DesktopWebSidebar(
                  currentIndex: _currentIndex,
                  onTabSelected: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  activeMembersCount: activeMembersCount,
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    child: IndexedStack(
                      index: _currentIndex,
                      children: _screens,
                    ),
                  ),
                ),
              ],
            )
          : IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
      bottomNavigationBar: isDesktop
          ? null // No mobile bottom bar on desktop monitors
          : Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  )
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_outlined),
                    activeIcon: Icon(Icons.dashboard_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.people_outline),
                    activeIcon: Icon(Icons.people_rounded),
                    label: 'Members',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    activeIcon: Icon(Icons.account_balance_wallet_rounded),
                    label: 'Finance',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.badge_outlined),
                    activeIcon: Icon(Icons.badge_rounded),
                    label: 'Staff',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.grid_view_outlined),
                    activeIcon: Icon(Icons.grid_view_rounded),
                    label: 'More',
                  ),
                ],
              ),
            ),
    );

    if (isExpired) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Account Locked',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Subscription Expired — Please Renew Plan Below',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await authVm.fetchSubscriptionStatus();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh Status'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                await authVm.logout();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WebQrLoginScreen()),
                    (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
              label: const Text('Log Out', style: TextStyle(color: Colors.redAccent)),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: const OwnerSubscriptionScreen(),
      );
    }

    return outerScaffold;
  }


  Widget _buildContactSupportButton(BuildContext context) {
    return ScaleButton(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Contact Support', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.phone, color: Color(0xFF6C4EFF)),
                  title: const Text('+91 8160490013'),
                  subtitle: const Text('Call Support'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final uri = Uri.parse('tel:+918160490013');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.email, color: Color(0xFF6C4EFF)),
                  title: const Text('support@gymos.tech'),
                  subtitle: const Text('Email Support'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final uri = Uri.parse('mailto:support@gymos.tech');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: GoogleFonts.inter(color: Colors.grey)),
              ),
            ],
          ),
        );
      },
      child: Container(
        height: 52,
        width: 190,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.headset_mic_rounded, color: Color(0xFF6C4EFF), size: 20),
            const SizedBox(width: 8),
            Text(
              'Contact Support',
              style: GoogleFonts.inter(
                color: const Color(0xFF6C4EFF),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineRetryButton(AuthViewModel authVm) {
    return ScaleButton(
      onTap: () {
        authVm.fetchSubscriptionStatus();
      },
      child: Container(
        height: 52,
        width: 190,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.refresh_rounded, color: Color(0xFF6C4EFF), size: 20),
            const SizedBox(width: 8),
            Text(
              'Retry Connection',
              style: GoogleFonts.inter(
                color: const Color(0xFF6C4EFF),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuspendedScreen(BuildContext context, AuthViewModel authVm) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;
    final gymName = authVm.gymInfo?['name'] ?? 'Your Gym';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1100),
              padding: const EdgeInsets.all(24.0),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: _buildSuspensionDetails(gymName)),
                        const SizedBox(width: 40),
                        Expanded(flex: 6, child: _buildTicketSection()),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSuspensionDetails(gymName),
                        const SizedBox(height: 32),
                        _buildTicketSection(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuspensionDetails(String gymName) {
    return Container(
      padding: const EdgeInsets.all(28.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFEE2E2)),
            ),
            child: const Icon(
              Icons.block_flipped,
              color: Color(0xFFEF4444),
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Access Suspended',
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            gymName,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your gym account access has been suspended by the administrator. This is usually due to overdue subscription payments, terms of service violations, or policy infractions.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.6,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'All member, staff, and transactional dashboards are temporarily locked. Please raise a support ticket on this page to resolve this restriction immediately.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.6,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 18),
          Text(
            'Urgently Need Help?',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF64748B), size: 18),
              const SizedBox(width: 10),
              Text(
                '+91 99999 99999',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.email_outlined, color: Color(0xFF64748B), size: 18),
              const SizedBox(width: 10),
              Text(
                'support@gymos.tech',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTicketSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.support_agent_rounded, color: AppTheme.primary, size: 48),
          const SizedBox(height: 16),
          Text(
            'Support Ticket Center',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Raise a ticket or track history of your queries directly. Chat with our support agents in real-time.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SupportTicketsScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(
              'Open Support Center',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const ScaleButton({Key? key, required this.child, required this.onTap}) : super(key: key);

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}
