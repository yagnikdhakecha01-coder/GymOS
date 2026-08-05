import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme/admin_theme.dart';
import 'core/services/supabase_service.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/navigation_provider.dart';
import 'core/widgets/admin_scaffold.dart';

import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/gyms/gyms_screen.dart';
import 'features/subscriptions/subscriptions_screen.dart';
import 'features/revenue/revenue_screen.dart';
import 'features/payments/payments_screen.dart';
import 'features/app_versions/app_versions_screen.dart';
import 'features/feature_control/feature_control_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/support/support_screen.dart';
import 'features/duplicate_detection/duplicate_detection_screen.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/database/database_screen.dart';
import 'features/audit_logs/audit_logs_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/profile/admin_profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdminSupabaseService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
      ],
      child: const GymOSAdminApp(),
    ),
  );
}

class GymOSAdminApp extends StatelessWidget {
  const GymOSAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'Gym OS Admin Panel',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.mode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          if (authProvider.isLoading && !authProvider.isAuthenticated) {
            return const Scaffold(
              backgroundColor: Color(0xFF0F172A),
              body: Center(
                child: CircularProgressIndicator(color: AdminTheme.primary),
              ),
            );
          }
          if (authProvider.isAuthenticated) {
            return AdminScaffold(
              pages: const [
                DashboardScreen(),
                GymsScreen(),
                SubscriptionsScreen(),
                RevenueScreen(),
                PaymentsScreen(),
                AppVersionsScreen(),
                FeatureControlScreen(),
                NotificationsScreen(),
                SupportScreen(),
                DuplicateDetectionScreen(),
                AnalyticsScreen(),
                DatabaseScreen(),
                AuditLogsScreen(),
                SettingsScreen(),
                AdminProfileScreen(),
              ],
            );
          }
          return const LoginScreen();
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AdminTheme.primary,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        primary: AdminTheme.primary,
        secondary: AdminTheme.primaryLight,
        error: AdminTheme.danger,
        surface: isDark ? AdminTheme.darkSurface : AdminTheme.lightSurface,
      ),
      scaffoldBackgroundColor: isDark ? AdminTheme.darkBackground : AdminTheme.lightBackground,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: brightness).textTheme,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AdminTheme.darkCard : Colors.white,
        foregroundColor: isDark ? AdminTheme.darkTextPrimary : AdminTheme.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: isDark ? AdminTheme.darkCard : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
          side: BorderSide(color: isDark ? AdminTheme.darkBorder : AdminTheme.lightBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdminTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? AdminTheme.darkTextPrimary : AdminTheme.textPrimary,
          side: BorderSide(color: isDark ? AdminTheme.darkBorder : AdminTheme.lightBorder),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AdminTheme.darkBorder : AdminTheme.lightBorder,
        thickness: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) return AdminTheme.primary;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) return AdminTheme.primary.withValues(alpha: 0.3);
          return Colors.grey.withValues(alpha: 0.3);
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AdminTheme.primary,
        unselectedLabelColor: isDark ? AdminTheme.darkTextSecondary : AdminTheme.textSecondary,
        indicatorColor: AdminTheme.primary,
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AdminTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusCard)),
        textStyle: GoogleFonts.inter(fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
        contentTextStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AdminTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusLg)),
      ),
    );
  }
}
