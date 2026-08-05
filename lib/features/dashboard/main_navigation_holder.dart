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
import 'support_chat_screen.dart';

class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({Key? key}) : super(key: key);

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkGymStatus();
    });
    _startStatusCheckTimer();
    _fetchTickets();
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
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
    // Check gym status every 10 seconds in background
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
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
    final gymName = authVm.gymInfo?['name'] ?? 'FitZone Gym';
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

    final outerScaffold = Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
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
        body: Stack(
          children: [
            AbsorbPointer(child: outerScaffold),
            _buildPremiumLockOverlay(context, authVm),
          ],
        ),
      );
    }

    return outerScaffold;
  }

  Widget _buildPremiumLockOverlay(BuildContext context, AuthViewModel authVm) {
    final isLockedByAdmin = authVm.gymInfo?['is_locked'] == true;
    return Positioned.fill(
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            color: Colors.black.withOpacity(0.3),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(color: const Color(0xFF6C4EFF).withOpacity(0.15), width: 1.5),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.lock_outline_rounded,
                            color: Color(0xFF6C4EFF),
                            size: 40,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        authVm.isOffline
                            ? 'No Internet Connection'
                            : (isLockedByAdmin ? 'Gym Locked by Admin' : 'Gym Locked'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        authVm.isOffline
                            ? 'Cannot verify subscription.\nPlease check your connection and retry.'
                            : (isLockedByAdmin
                                ? 'Your gym account access has been locked by the administrator.\nPlease contact support to resolve.'
                                : 'Your free trial has ended.\nSubscribe to continue using Gym OS.'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          height: 1.5,
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 36),
                      authVm.isOffline
                          ? _buildOfflineRetryButton(authVm)
                          : (isLockedByAdmin
                              ? _buildContactSupportButton(context)
                              : _buildUnlockButton(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockButton(BuildContext context) {
    return ScaleButton(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const OwnerSubscriptionScreen(),
          ),
        );
      },
      child: Container(
        height: 52,
        width: 190,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF6C4EFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C4EFF).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'Unlock Gym',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
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
                  title: const Text('+91 99999 99999'),
                  subtitle: const Text('Call Support'),
                  onTap: () {},
                ),
                ListTile(
                  leading: const Icon(Icons.email, color: Color(0xFF6C4EFF)),
                  title: const Text('support@gymos.com'),
                  subtitle: const Text('Email Support'),
                  onTap: () {},
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
                'support@gymos.com',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tab Headers
          Row(
            children: [
              _buildTabButton('Raise Support Ticket', 0),
              _buildTabButton('Ticket History (${_tickets.length})', 1),
            ],
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _activeTab == 0 ? _buildRaiseTicketForm() : _buildTicketHistory(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isActive = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _activeTab = index;
          });
          if (index == 1) {
            _fetchTickets();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? AppTheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
              color: isActive ? AppTheme.primary : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRaiseTicketForm() {
    return Column(
      key: const ValueKey('raise_ticket_form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Describe Your Issue',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        // Title field
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'Subject / Title',
            hintText: 'e.g. Account suspended after payment',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          style: GoogleFonts.inter(fontSize: 14),
        ),
        const SizedBox(height: 18),
        // Priority Dropdown
        DropdownButtonFormField<String>(
          value: _selectedPriority,
          decoration: InputDecoration(
            labelText: 'Priority Level',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: const [
            DropdownMenuItem(value: 'low', child: Text('Low')),
            DropdownMenuItem(value: 'medium', child: Text('Medium')),
            DropdownMenuItem(value: 'high', child: Text('High')),
            DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedPriority = val;
              });
            }
          },
        ),
        const SizedBox(height: 18),
        // Description field
        TextField(
          controller: _descController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Detailed Message',
            hintText: 'Please detail your request or details of your transaction...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          style: GoogleFonts.inter(fontSize: 14),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _createTicket,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            shadowColor: AppTheme.primary.withOpacity(0.3),
          ),
          child: Text(
            'Submit Support Ticket',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildTicketHistory() {
    if (_loadingTickets) {
      return const SizedBox(
        key: ValueKey('tickets_loading'),
        height: 200,
        child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (_tickets.isEmpty) {
      return SizedBox(
        key: const ValueKey('tickets_empty'),
        height: 250,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_chat_read_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Support Tickets Found',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            Text(
              'Tickets you raise will be shown here.',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('tickets_list'),
      height: 380,
      child: ListView.builder(
        itemCount: _tickets.length,
        itemBuilder: (context, index) {
          final ticket = _tickets[index];
          final priority = (ticket['priority'] ?? 'medium').toString().toUpperCase();
          final status = ticket['status'] ?? 'Open';
          final title = ticket['title'] ?? 'Support Ticket';
          final desc = ticket['description'] ?? '';
          final date = ticket['created_at'] != null 
              ? DateTime.tryParse(ticket['created_at'])?.toLocal().toString().substring(0, 16) ?? ''
              : '';

          Color priorityColor;
          switch (priority.toLowerCase()) {
            case 'urgent': priorityColor = Colors.red[700]!; break;
            case 'high': priorityColor = Colors.orange[700]!; break;
            case 'medium': priorityColor = Colors.amber[700]!; break;
            default: priorityColor = Colors.blue[700]!;
          }

          Color statusColor;
          switch (status.toString().toLowerCase()) {
            case 'open': statusColor = Colors.blue; break;
            case 'in progress': statusColor = Colors.orange; break;
            case 'resolved': statusColor = Colors.green; break;
            default: statusColor = Colors.grey;
          }

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SupportChatScreen(ticket: ticket),
                ),
              ).then((_) => _fetchTickets());
            },
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: priorityColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                priority,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: priorityColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              date,
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
