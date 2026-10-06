import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../authentication/auth_viewmodel.dart';
import 'staff_dashboard_screen.dart';
import 'staff_clients_screen.dart';
import '../portal/staff_more_screen.dart';
import '../portal/staff_requests_screen.dart';
import '../../attendance/staff_attendance_screen.dart';

import 'dart:async';
import '../../../core/services/unlink_guard.dart';

class StaffShell extends StatefulWidget {
  const StaffShell({super.key});

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _syncTimer;
  bool _isRedirecting = false;

  final List<Widget> _screens = const [
    StaffDashboardScreen(),
    StaffClientsScreen(),
    StaffAttendanceScreen(),
    StaffRequestsScreen(),
    StaffMoreScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUnlinkedStatus();
    });
    // Relaxed 5-minute periodic sync instead of aggressive 3s polling
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkUnlinkedStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkUnlinkedStatus();
    }
  }

  Future<void> _checkUnlinkedStatus() async {
    if (!mounted || _isRedirecting) return;
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    if (!authVm.isLoggedIn) return;

    final blocked = await UnlinkGuard.checkAndForceLogout(context, authVm);
    if (blocked && mounted) {
      setState(() => _isRedirecting = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRedirecting) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final authVm = Provider.of<AuthViewModel>(context);
    final isLockedByAdmin = authVm.gymInfo?['is_locked'] == true;
    final isExpired = authVm.isSubscriptionExpired || isLockedByAdmin;

    if (isExpired) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isLockedByAdmin ? 'Gym Locked by Admin' : 'Gym Access Expired',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isLockedByAdmin
                      ? 'This gym account has been locked by the administrator. Please contact support.'
                      : 'This gym\'s active subscription has expired. Please contact the gym owner.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
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
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded),
              label: 'My Clients',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today_rounded),
              label: 'Attendance',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.description_outlined),
              activeIcon: Icon(Icons.description_rounded),
              label: 'Requests',
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
  }
}
