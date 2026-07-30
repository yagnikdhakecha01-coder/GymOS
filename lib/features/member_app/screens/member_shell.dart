import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../../core/navigation/app_router.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../authentication/role_selection_screen.dart';
import '../member_app_viewmodel.dart';
import '../../../core/services/supabase_service.dart';
import 'member_dashboard_screen.dart';
import 'member_attendance_screen.dart';
import 'member_scan_qr_screen.dart';
import 'member_achievements_screen.dart';
import 'member_profile_screen.dart';

class MemberShell extends StatefulWidget {
  const MemberShell({super.key});

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int _currentIndex = 0;
  Timer? _syncTimer;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUnlinkedStatus();
    });
    // Start periodic background check every 5 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
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
          final memberData = await SupabaseService.client
              .from('members')
              .select('status')
              .eq('user_id', user.id)
              .maybeSingle();

          if (authVm.userAssociations.isEmpty) {
            _triggerLogout('Account Unlinked', 'Gym Owner unlinked your account.');
          } else if (memberData != null && memberData['status'] == 'Inactive') {
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
                    AppRouter.scaleRoute(const RoleSelectionScreen()),
                    (route) => false,
                  );
                }
              },
              child: Text('OK', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ),
          ],
        );
      },
    );
  }

  final Map<int, GlobalKey<NavigatorState>> _navigatorKeys = {
    0: GlobalKey<NavigatorState>(),
    1: GlobalKey<NavigatorState>(),
    2: GlobalKey<NavigatorState>(),
    3: GlobalKey<NavigatorState>(),
    4: GlobalKey<NavigatorState>(),
  };

  void _onTabTapped(int index) {
    if (_currentIndex == index) {
      _navigatorKeys[index]?.currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _currentIndex = index);
    }
  }

  Future<bool> _onWillPop() async {
    final isFirstRouteInCurrentTab =
        !await _navigatorKeys[_currentIndex]!.currentState!.maybePop();
    if (isFirstRouteInCurrentTab) {
      if (_currentIndex != 0) {
        _onTabTapped(0);
        return false;
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildTabNavigator(0, const MemberDashboardScreen()),
            _buildTabNavigator(1, const MemberAttendanceScreen()),
            _buildTabNavigator(2, const MemberScanQRScreen()),
            _buildTabNavigator(3, const MemberAchievementsScreen()),
            _buildTabNavigator(4, const MemberProfileScreen()),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(
              top: BorderSide(color: AppTheme.border, width: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Home'),
                  _buildNavItem(1, Icons.calendar_month_rounded, Icons.calendar_month_outlined, 'Attendance'),
                  _buildNavItem(2, Icons.qr_code_scanner_rounded, Icons.qr_code_scanner_rounded, 'Scan QR'),
                  _buildNavItem(3, Icons.emoji_events_rounded, Icons.emoji_events_outlined, 'Achievements'),
                  _buildNavItem(4, Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabNavigator(int index, Widget rootPage) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (routeSettings) {
        return MaterialPageRoute(builder: (context) => rootPage);
      },
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTabTapped(index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? AppTheme.primary : AppTheme.textMuted,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppTheme.primary : AppTheme.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
