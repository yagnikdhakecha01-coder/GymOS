import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../../core/repository/gym_repository.dart';
import '../../authentication/auth_viewmodel.dart';
import '../receptionist_viewmodel.dart';
import 'receptionist_dashboard_screen.dart';
import 'receptionist_members_screen.dart';
import '../../attendance/staff_attendance_screen.dart';
import 'receptionist_finance_screen.dart';
import 'receptionist_more_screen.dart';

import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/supabase_service.dart';
import '../../authentication/role_selection_screen.dart';

class ReceptionistShell extends StatefulWidget {
  const ReceptionistShell({super.key});

  @override
  State<ReceptionistShell> createState() => _ReceptionistShellState();
}

class _ReceptionistShellState extends State<ReceptionistShell> {
  int _currentIndex = 0;
  Timer? _syncTimer;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUnlinkedStatus();
    });
    // Check every 15 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _checkUnlinkedStatus();
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkUnlinkedStatus() async {
    if (!mounted || _isLoggingOut) return;
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      if (authVm.isLoggedIn) {
        await authVm.loadCurrentProfile();
        
        final user = SupabaseService.client.auth.currentUser;
        if (user != null) {
          final staffData = await SupabaseService.client
              .from('staff')
              .select('status')
              .eq('user_id', user.id)
              .maybeSingle();

          if (authVm.userAssociations.isEmpty) {
            _triggerLogout('Account Unlinked', 'Gym Owner unlinked your account.');
          } else if (staffData != null && staffData['status'] == 'Inactive') {
            _triggerLogout('Account Inactive', 'Your account has been deactivated by the gym owner.');
          }
        }
      }
    } catch (e) {
      print('Error checking unlinked status: $e');
    }
  }

  void _triggerLogout(String title, String message) {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    _syncTimer?.cancel();

    final authVm = Provider.of<AuthViewModel>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: Text(message, style: GoogleFonts.inter()),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await authVm.logout();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                    (route) => false,
                  );
                }
              },
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final staffUserId = authVm.currentUser?.id ?? '';
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';

    final repo = Provider.of<GymRepository>(context, listen: false);
    return ChangeNotifierProvider<ReceptionistViewModel>(
      key: ValueKey(gymId),
      create: (_) => ReceptionistViewModel(staffUserId: staffUserId, gymId: gymId, repository: repo),
      child: Consumer<ReceptionistViewModel>(
        builder: (context, vm, child) {
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

          if (vm.staffRecord == null) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            );
          }

          final List<Widget> screens = [
            const ReceptionistDashboardScreen(),
            const ReceptionistMembersScreen(),
            const StaffAttendanceScreen(),
            const ReceptionistFinanceScreen(),
            const ReceptionistMoreScreen(),
          ];

          return Scaffold(
            body: IndexedStack(
              index: _currentIndex,
              children: screens,
            ),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 15,
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
                type: BottomNavigationBarType.fixed,
                selectedItemColor: AppTheme.primary,
                unselectedItemColor: AppTheme.textSecondary,
                selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                unselectedLabelStyle: const TextStyle(fontSize: 11),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_outlined),
                    activeIcon: Icon(Icons.dashboard_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.people_outline_rounded),
                    activeIcon: Icon(Icons.people_rounded),
                    label: 'Members',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.qr_code_scanner_outlined),
                    activeIcon: Icon(Icons.qr_code_scanner_rounded),
                    label: 'Attendance',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    activeIcon: Icon(Icons.account_balance_wallet_rounded),
                    label: 'Finance',
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
        },
      ),
    );
  }
}
