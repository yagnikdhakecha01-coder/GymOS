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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (will gracefully skip if credentials are not set yet)
  await SupabaseService.initialize();

  // Initialize Notification Service and request permissions on first launch
  await NotificationService.initialize();
  await NotificationService.requestPermissions();

  // Set system UI overlay style for premium iOS-like status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Initialize shared preferences for local storage
  final prefs = await SharedPreferences.getInstance();
  final localStorageService = LocalStorageService(prefs);
  final gymRepository = GymRepository(localStorageService);

  runApp(GymOSApp(
    localStorageService: localStorageService,
    gymRepository: gymRepository,
  ));
}

class GymOSApp extends StatelessWidget {
  final LocalStorageService localStorageService;
  final GymRepository gymRepository;

  const GymOSApp({
    Key? key,
    required this.localStorageService,
    required this.gymRepository,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: gymRepository,
        ),
        // Auth
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(localStorageService, gymRepository),
        ),
        // Members
        ChangeNotifierProvider(
          create: (_) => MembersViewModel(gymRepository),
        ),
        // Staff
        ChangeNotifierProvider(
          create: (_) => StaffViewModel(gymRepository),
        ),
        // Finance
        ChangeNotifierProvider(
          create: (_) => FinanceViewModel(gymRepository),
        ),
        // Workout
        ChangeNotifierProvider(
          create: (_) => WorkoutViewModel(gymRepository),
        ),
        // Diet
        ChangeNotifierProvider(
          create: (_) => DietViewModel(gymRepository),
        ),
        // Membership
        ChangeNotifierProvider(
          create: (_) => MembershipViewModel(gymRepository),
        ),
        // Attendance
        ChangeNotifierProvider(
          create: (_) => AttendanceViewModel(gymRepository),
        ),
        // Member App
        ChangeNotifierProvider(
          create: (_) => MemberAppViewModel(),
        ),
        // Gym Settings Setup
        ChangeNotifierProxyProvider<AuthViewModel, GymSettingsViewModel>(
          create: (context) => GymSettingsViewModel(
            gymRepository,
            Provider.of<AuthViewModel>(context, listen: false),
          ),
          update: (context, authVm, previous) => GymSettingsViewModel(gymRepository, authVm),
        ),
      ],
      child: MaterialApp(
        title: 'GymOS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
        builder: (context, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AlertsNotificationEngine.start(context);
          });
          return child!;
        },
      ),
    );
  }
}
