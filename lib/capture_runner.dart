import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'core/theme/theme.dart';
import 'core/services/local_storage.dart';
import 'core/repository/gym_repository.dart';
import 'core/services/supabase_service.dart';
import 'core/models/user_profile.dart';

import 'features/authentication/auth_viewmodel.dart';
import 'features/authentication/role_selection_screen.dart';
import 'features/members/members_viewmodel.dart';
import 'features/members/trial_members_viewmodel.dart';
import 'features/staff/staff_viewmodel.dart';
import 'features/finance/finance_viewmodel.dart';
import 'features/workout/workout_viewmodel.dart';
import 'features/diet/diet_viewmodel.dart';
import 'features/membership/membership_viewmodel.dart';
import 'features/attendance/attendance_viewmodel.dart';
import 'features/member_app/member_app_viewmodel.dart';
import 'features/gym_settings/gym_settings_viewmodel.dart';
import 'core/services/notification_service.dart';
import 'core/navigation/app_router.dart';

import 'features/dashboard/main_navigation_holder.dart';
import 'features/member_app/screens/member_shell.dart';
import 'features/member_app/screens/member_exercise_library_screen.dart';
import 'features/staff/portal/staff_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseService.initialize();
  await NotificationService.initialize();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('gymos_rule_agreed_global', true);
  await prefs.setBool('is_rules_agreed', true);
  final localStorageService = LocalStorageService(prefs);
  final gymRepository = GymRepository(localStorageService);

  runApp(CaptureApp(
    localStorageService: localStorageService,
    gymRepository: gymRepository,
  ));
}

class CaptureApp extends StatefulWidget {
  final LocalStorageService localStorageService;
  final GymRepository gymRepository;

  const CaptureApp({
    super.key,
    required this.localStorageService,
    required this.gymRepository,
  });

  @override
  State<CaptureApp> createState() => _CaptureAppState();
}

class _CaptureAppState extends State<CaptureApp> {
  late final AuthViewModel _authVm;
  late final MembersViewModel _membersVm;
  late final TrialMembersViewModel _trialMembersVm;
  late final StaffViewModel _staffVm;
  late final FinanceViewModel _financeVm;
  late final WorkoutViewModel _workoutVm;
  late final DietViewModel _dietVm;
  late final MembershipViewModel _membershipVm;
  late final AttendanceViewModel _attendanceVm;
  late final MemberAppViewModel _memberVm;

  bool _initialized = false;
  String _targetScreen = 'owner_dashboard';

  @override
  void initState() {
    super.initState();
    _authVm = AuthViewModel(widget.localStorageService, widget.gymRepository);
    _membersVm = MembersViewModel(widget.gymRepository);
    _trialMembersVm = TrialMembersViewModel(widget.gymRepository);
    _staffVm = StaffViewModel(widget.gymRepository);
    _financeVm = FinanceViewModel(widget.gymRepository);
    _workoutVm = WorkoutViewModel(widget.gymRepository);
    _dietVm = DietViewModel(widget.gymRepository);
    _membershipVm = MembershipViewModel(widget.gymRepository);
    _attendanceVm = AttendanceViewModel(widget.gymRepository);
    _memberVm = MemberAppViewModel();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final uri = Uri.base;
    _targetScreen = uri.queryParameters['screen'] ?? 'owner_dashboard';

    if (_targetScreen == 'welcome_screen' || _targetScreen == 'login') {
      if (mounted) setState(() => _initialized = true);
      return;
    }

    try {
      final email = uri.queryParameters['email'] ?? const String.fromEnvironment('DEMO_EMAIL');
      final pwd = uri.queryParameters['pwd'] ?? const String.fromEnvironment('DEMO_PASSWORD');
      
      if (email.isNotEmpty && pwd.isNotEmpty) {
        debugPrint('[CaptureApp] Logging in as $email...');
        await _authVm.login(email, pwd);
      }
      
      final assocs = _authVm.userAssociations;
      debugPrint('[CaptureApp] Available associations: ${assocs.length}');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('gymos_rule_agreed_global', true);
      await prefs.setBool('is_rules_agreed', true);

      if (_targetScreen.startsWith('member_')) {
        // --- MEMBER FLOW ---
        debugPrint('[CaptureApp] Bootstrapping MEMBER context...');
        await prefs.setString('gymos_user_role', 'member');
        await prefs.setBool('member_logged_in', true);
        await prefs.setBool('member_code_verified', true);

        final memberAssoc = assocs.firstWhere(
          (a) => a.role == UserRole.member,
          orElse: () => assocs.first,
        );
        await _authVm.selectAssociation(memberAssoc);
        
        // Hydrate member repository and view model
        await _memberVm.loadMemberDataFromSupabase();
        debugPrint('[CaptureApp] Member data hydrated: ${_memberVm.memberName}, gym: ${_memberVm.gymName}');
      } else if (_targetScreen == 'staff_portal') {
        final staffAssoc = assocs.firstWhere(
          (a) => a.role == UserRole.staff,
          orElse: () => assocs.first,
        );
        await _authVm.selectAssociation(staffAssoc);
      } else {
        // --- OWNER FLOW ---
        debugPrint('[CaptureApp] Bootstrapping OWNER context...');
        await prefs.setString('gymos_user_role', 'owner');

        final ownerAssoc = assocs.firstWhere(
          (a) => a.role == UserRole.owner,
          orElse: () => assocs.first,
        );
        await _authVm.selectAssociation(ownerAssoc);
        final gymId = ownerAssoc.gymId;
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

        debugPrint('[CaptureApp] Hydrating Owner data for gym: $gymId on $todayStr...');
        // Hydrate GymRepository
        await widget.gymRepository.fetchDashboardStatsFromSupabase(gymId, todayStr);
        await widget.gymRepository.fetchMembersFromSupabase();
        await widget.gymRepository.fetchTransactionsFromSupabase();
        await widget.gymRepository.fetchStaffFromSupabase();
        await widget.gymRepository.fetchAttendanceLogsFromSupabase();
        await widget.gymRepository.fetchReportsAnalyticsFromSupabase(gymId, todayStr);
        await widget.gymRepository.fetchOwnerDashboardStats(gymId);

        // Hydrate ViewModels
        await _membersVm.fetchMembers();
        await _financeVm.fetchTransactions();
        await _staffVm.fetchStaff();
        _attendanceVm.refresh();

        debugPrint('[CaptureApp] Owner hydration complete: ${widget.gymRepository.totalMembersCount} members, Rev: ${widget.gymRepository.monthlyRevenue}');
      }
    } catch (e, stack) {
      debugPrint('[CaptureApp] Bootstrap error: $e\n$stack');
    }

    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  Widget _buildTargetWidget() {
    switch (_targetScreen) {
      case 'login':
      case 'welcome_screen':
        return const RoleSelectionScreen();
      case 'owner_dashboard':
        return const MainNavigationHolder(initialIndex: 0);
      case 'members_directory':
        return const MainNavigationHolder(initialIndex: 1);
      case 'finance_overview':
        return const MainNavigationHolder(initialIndex: 2);
      case 'owner_staff':
        return const MainNavigationHolder(initialIndex: 3);
      case 'member_dashboard':
        return const MemberShell(initialIndex: 0);
      case 'member_exercises':
        return const MemberExerciseLibraryScreen();
      case 'member_attendance':
        return const MemberShell(initialIndex: 1);
      case 'staff_portal':
        return const StaffShell();
      default:
        return const MainNavigationHolder(initialIndex: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.gymRepository),
        ChangeNotifierProvider.value(value: _authVm),
        ChangeNotifierProvider.value(value: _membersVm),
        ChangeNotifierProvider.value(value: _trialMembersVm),
        ChangeNotifierProvider.value(value: _staffVm),
        ChangeNotifierProvider.value(value: _financeVm),
        ChangeNotifierProvider.value(value: _workoutVm),
        ChangeNotifierProvider.value(value: _dietVm),
        ChangeNotifierProvider.value(value: _membershipVm),
        ChangeNotifierProvider.value(value: _attendanceVm),
        ChangeNotifierProvider.value(value: _memberVm),
        ChangeNotifierProxyProvider<AuthViewModel, GymSettingsViewModel>(
          create: (context) => GymSettingsViewModel(
            widget.gymRepository,
            _authVm,
          ),
          update: (context, authVm, previous) => GymSettingsViewModel(widget.gymRepository, authVm),
        ),
      ],
      child: MaterialApp(
        navigatorKey: AppRouter.rootNavigatorKey,
        title: 'GymOS Real App Capture',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: _initialized
            ? Scaffold(
                body: _buildTargetWidget(),
              )
            : const Scaffold(
                backgroundColor: Colors.white,
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
      ),
    );
  }
}
