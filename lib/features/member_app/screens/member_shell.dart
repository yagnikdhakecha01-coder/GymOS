import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../../core/services/unlink_guard.dart';
import 'member_dashboard_screen.dart';
import 'member_attendance_screen.dart';
import 'member_scan_qr_screen.dart';
import 'member_achievements_screen.dart';
import 'member_profile_screen.dart';
import '../member_app_viewmodel.dart';
import '../widgets/member_rules_agreement_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemberShell extends StatefulWidget {
  final int initialIndex;
  const MemberShell({super.key, this.initialIndex = 0});

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> with WidgetsBindingObserver {
  late int _currentIndex;
  Timer? _syncTimer;
  bool _isRedirecting = false;
  bool _isAgreementModalShowing = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUnlinkedStatus();
      _checkRulesAgreement();
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
      final memberVm = Provider.of<MemberAppViewModel>(context, listen: false);
      if (!memberVm.hasAgreedRules) {
        _checkRulesAgreement();
      }
    }
  }

  Future<void> _checkRulesAgreement() async {
    if (!mounted || _isRedirecting || _isAgreementModalShowing) return;
    final memberVm = Provider.of<MemberAppViewModel>(context, listen: false);

    // If ALREADY agreed in memory, NEVER open modal!
    if (memberVm.hasAgreedRules) return;

    // Check persistent cache directly first before doing network calls
    final prefs = await SharedPreferences.getInstance();
    final memberId = memberVm.memberId.isNotEmpty ? memberVm.memberId : (prefs.getString('member_cached_id') ?? '');
    final gymId = memberVm.gymId.isNotEmpty ? memberVm.gymId : (prefs.getString('member_cached_gym_id') ?? '');

    final isAgreedLocally = (gymId.isNotEmpty && memberId.isNotEmpty && (prefs.getBool('gymos_rule_agreed_${gymId}_$memberId') == true)) ||
        (memberId.isNotEmpty && (prefs.getBool('gymos_rule_agreed_member_$memberId') == true)) ||
        (prefs.getBool('gymos_rule_agreed_global') == true);

    if (isAgreedLocally) {
      await memberVm.checkRulesAgreementStatus();
      return;
    }

    // Only if not agreed locally, load member data and check Supabase
    if (memberVm.memberId.isEmpty || memberVm.gymId.isEmpty) {
      await memberVm.loadMemberDataFromSupabase();
    }
    final agreed = await memberVm.checkRulesAgreementStatus();

    if (!mounted) return;
    if (agreed || memberVm.hasAgreedRules) return;

    // For all members (new and old existing members): if not agreed, enforce modal agreement
    if (!memberVm.hasAgreedRules && !_isAgreementModalShowing) {
      _isAgreementModalShowing = true;
      final didAgree = await MemberRulesAgreementDialog.show(context);
      _isAgreementModalShowing = false;
      if (didAgree == true || memberVm.hasAgreedRules) {
        return;
      }
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

  final Map<int, GlobalKey<NavigatorState>> _navigatorKeys = {
    0: GlobalKey<NavigatorState>(),
    1: GlobalKey<NavigatorState>(),
    2: GlobalKey<NavigatorState>(),
    3: GlobalKey<NavigatorState>(),
    4: GlobalKey<NavigatorState>(),
  };

  void _onTabTapped(int index) {
    final memberVm = Provider.of<MemberAppViewModel>(context, listen: false);
    if (!memberVm.hasAgreedRules) {
      _checkRulesAgreement();
      return;
    }
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
    if (_isRedirecting) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

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
