import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/theme.dart';
import 'core/services/local_storage.dart';
import 'core/repository/gym_repository.dart';
import 'core/services/supabase_service.dart';

import 'features/authentication/auth_viewmodel.dart';
import 'features/authentication/splash_screen.dart';
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
import 'core/services/alerts_notification_engine.dart';
import 'core/services/version_check_service.dart';
import 'core/config/supabase_config.dart';
import 'core/widgets/configuration_error_screen.dart';
import 'core/navigation/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase safely
  try {
    await SupabaseService.initialize();
  } catch (e, stack) {
    debugPrint('Supabase initialization error: $e');
    debugPrint(stack.toString());
  }

  // Refuse to start if critical environment variables are missing
  if (!SupabaseConfig.isValid || !SupabaseService.isInitialized) {
    runApp(const ConfigurationErrorScreen(
      missingDetails: 'Missing SUPABASE_URL or SUPABASE_ANON_KEY.\nProvide them via --dart-define or .env file before launching.',
    ));
    return;
  }

  // Initialize Notification Service safely (channels & handlers initialized; permissions requested in user flow)
  try {
    await NotificationService.initialize();
  } catch (e, stack) {
    debugPrint('Notification initialization error: $e');
    debugPrint(stack.toString());
  }

  // Set system UI overlay style for premium iOS-like status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Initialize shared preferences and repository
  LocalStorageService? localStorageService;
  GymRepository? gymRepository;

  try {
    final prefs = await SharedPreferences.getInstance();
    localStorageService = LocalStorageService(prefs);
    gymRepository = GymRepository(localStorageService);
  } catch (e, stack) {
    debugPrint('LocalStorage/Repository initialization error: $e');
    debugPrint(stack.toString());
  }

  if (localStorageService != null && gymRepository != null) {
    runApp(GymOSApp(
      localStorageService: localStorageService,
      gymRepository: gymRepository,
    ));
  } else {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Failed',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Failed to initialize local storage. Please clear app data or contact support.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = AppRouter.rootNavigatorKey;

class GymOSApp extends StatefulWidget {
  final LocalStorageService localStorageService;
  final GymRepository gymRepository;

  const GymOSApp({
    Key? key,
    required this.localStorageService,
    required this.gymRepository,
  }) : super(key: key);

  @override
  State<GymOSApp> createState() => _GymOSAppState();
}

class _GymOSAppState extends State<GymOSApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.setAppInForeground(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      NotificationService.setAppInForeground(true);
    } else {
      NotificationService.setAppInForeground(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: widget.gymRepository,
        ),
        // Auth
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(widget.localStorageService, widget.gymRepository),
        ),
        // Members
        ChangeNotifierProvider(
          create: (_) => MembersViewModel(widget.gymRepository),
        ),
        // Trial Members
        ChangeNotifierProvider(
          create: (_) => TrialMembersViewModel(widget.gymRepository),
        ),
        // Staff
        ChangeNotifierProvider(
          create: (_) => StaffViewModel(widget.gymRepository),
        ),
        // Finance
        ChangeNotifierProvider(
          create: (_) => FinanceViewModel(widget.gymRepository),
        ),
        // Workout
        ChangeNotifierProvider(
          create: (_) => WorkoutViewModel(widget.gymRepository),
        ),
        // Diet
        ChangeNotifierProvider(
          create: (_) => DietViewModel(widget.gymRepository),
        ),
        // Membership
        ChangeNotifierProvider(
          create: (_) => MembershipViewModel(widget.gymRepository),
        ),
        // Attendance
        ChangeNotifierProvider(
          create: (_) => AttendanceViewModel(widget.gymRepository),
        ),
        // Member App
        ChangeNotifierProvider(
          create: (_) => MemberAppViewModel(),
        ),
        // Gym Settings Setup
        ChangeNotifierProxyProvider<AuthViewModel, GymSettingsViewModel>(
          create: (context) => GymSettingsViewModel(
            widget.gymRepository,
            Provider.of<AuthViewModel>(context, listen: false),
          ),
          update: (context, authVm, previous) => GymSettingsViewModel(widget.gymRepository, authVm),
        ),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: 'GymOS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
        builder: (context, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            VersionCheckEngine.navigatorKey = rootNavigatorKey;
            AlertsNotificationEngine.start(context);
          });
          return child!;
        },
      ),
    );
  }
}
