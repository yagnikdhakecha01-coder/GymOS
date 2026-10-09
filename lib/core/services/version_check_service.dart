import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../theme/theme.dart';

class VersionCheckResult {
  final String latestVersion;
  final int latestBuildNumber;
  final String minSupportedVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool isForceUpdate;
  final bool isOptionalUpdate;
  final bool isUpdateAvailable;
  final bool shouldForce;

  VersionCheckResult({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.minSupportedVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isForceUpdate,
    required this.isOptionalUpdate,
    required this.isUpdateAvailable,
    required this.shouldForce,
  });

  factory VersionCheckResult.empty() {
    return VersionCheckResult(
      latestVersion: AppConfig.appVersion,
      latestBuildNumber: AppConfig.buildNumber,
      minSupportedVersion: AppConfig.appVersion,
      downloadUrl: '',
      releaseNotes: '',
      isForceUpdate: false,
      isOptionalUpdate: false,
      isUpdateAvailable: false,
      shouldForce: false,
    );
  }

  factory VersionCheckResult.fromJson(Map<String, dynamic> json) {
    return VersionCheckResult(
      latestVersion: json['latest_version'] ?? AppConfig.appVersion,
      latestBuildNumber: json['build_number'] ?? AppConfig.buildNumber,
      minSupportedVersion: json['min_supported_version'] ?? AppConfig.appVersion,
      downloadUrl: json['download_url'] ?? '',
      releaseNotes: json['release_notes'] ?? '',
      isForceUpdate: json['is_force_update'] ?? false,
      isOptionalUpdate: json['is_optional_update'] ?? false,
      isUpdateAvailable: json['is_update_available'] ?? false,
      shouldForce: json['should_force'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latest_version': latestVersion,
      'build_number': latestBuildNumber,
      'min_supported_version': minSupportedVersion,
      'download_url': downloadUrl,
      'release_notes': releaseNotes,
      'is_force_update': isForceUpdate,
      'is_optional_update': isOptionalUpdate,
      'is_update_available': isUpdateAvailable,
      'should_force': shouldForce,
    };
  }
}

class VersionCheckService {
  static const String _cacheKey = 'gymos_version_check_cache';

  static String get _currentPlatform {
    if (kIsWeb) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// Perform semantic version comparison
  /// Returns -1 if v1 < v2, 1 if v1 > v2, 0 if equal
  static int compareVersions(String v1, String v2) {
    List<int> list1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> list2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    int length = list1.length > list2.length ? list1.length : list2.length;
    for (int i = 0; i < length; i++) {
      int val1 = i < list1.length ? list1[i] : 0;
      int val2 = i < list2.length ? list2[i] : 0;
      if (val1 < val2) return -1;
      if (val1 > val2) return 1;
    }
    return 0;
  }

  /// Performs background version check
  static Future<VersionCheckResult> checkVersion() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final platform = _currentPlatform;
      final supabase = Supabase.instance.client;

      // Query latest published version for the platform
      final response = await supabase
          .from('app_versions')
          .select()
          .eq('platform', platform)
          .eq('status', 'published')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final String latestV = response['version_name'] ?? AppConfig.appVersion;
        final int latestBuild = response['build_number'] ?? AppConfig.buildNumber;
        final String minSupported = response['min_supported_version'] ?? AppConfig.appVersion;
        final String rawDl = (response['download_url'] as String? ?? '').trim();
        final String dlUrl = rawDl.isNotEmpty ? rawDl : 'https://gymos.tech/';
        final String notes = response['release_notes'] ?? '';
        final bool isForce = response['is_force_update'] ?? false;
        final bool isOptional = response['is_optional_update'] ?? false;

        // Version comparisons
        final versionCmp = compareVersions(AppConfig.appVersion, latestV);
        final bool hasNewerVersion = versionCmp < 0 || (versionCmp == 0 && latestBuild > AppConfig.buildNumber);
        final bool isBelowMin = compareVersions(AppConfig.appVersion, minSupported) < 0;

        final result = VersionCheckResult(
          latestVersion: latestV,
          latestBuildNumber: latestBuild,
          minSupportedVersion: minSupported,
          downloadUrl: dlUrl,
          releaseNotes: notes,
          isForceUpdate: isForce,
          isOptionalUpdate: isOptional,
          isUpdateAvailable: hasNewerVersion,
          shouldForce: isBelowMin || (hasNewerVersion && isForce),
        );

        // Cache result
        await prefs.setString(_cacheKey, jsonEncode(result.toJson()));
        return result;
      }
    } catch (e) {
      // Offline fallback: Use last cached data
      final cachedStr = prefs.getString(_cacheKey);
      if (cachedStr != null) {
        try {
          return VersionCheckResult.fromJson(jsonDecode(cachedStr));
        } catch (_) {}
      }
    }

    return VersionCheckResult.empty();
  }
  static const String _snoozeDateKey = 'gymos_update_snooze_date';

  /// Returns true if the user has already snoozed the update dialog today
  static Future<bool> isSnoozedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString(_snoozeDateKey);
      if (savedDate == null || savedDate.isEmpty) return false;

      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      return savedDate == todayStr;
    } catch (_) {
      return false;
    }
  }

  /// Snoozes the update dialog for the current calendar day
  static Future<void> snoozeForToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await prefs.setString(_snoozeDateKey, todayStr);
    } catch (_) {}
  }

  /// Clears the snooze date
  static Future<void> clearSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_snoozeDateKey);
    } catch (_) {}
  }

  static Future<void> launchStoreUrl(String url) async {
    String storeUrl = url.trim();
    if (storeUrl.isEmpty || !storeUrl.startsWith('http')) {
      if (!kIsWeb && Platform.isIOS) {
        storeUrl = 'https://apps.apple.com/app/gymos';
      } else {
        storeUrl = 'https://play.google.com/store/apps/details?id=com.gymos.fitness.app.v1';
      }
    }
    final uri = Uri.tryParse(storeUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Error launching store url: $e');
      }
    }
  }
}

/// Clean center modal dialog with [X] close button, Later, and Update buttons
class UpdatePromptDialog extends StatelessWidget {
  final VersionCheckResult result;

  const UpdatePromptDialog({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          VersionCheckService.snoozeForToday();
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Bar with Version Badge and Close [X] Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'v${result.latestVersion}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () async {
                      await VersionCheckService.snoozeForToday();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceGray,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Center Icon
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  size: 34,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Text(
                'Update Available',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                'A new version of GymOS is ready. Please update the app to enjoy the latest version and improvements.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons: Later and Update
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () async {
                          await VersionCheckService.snoozeForToday();
                          if (context.mounted) Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          foregroundColor: AppTheme.textSecondary,
                        ),
                        child: Text(
                          'Later',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          VersionCheckService.launchStoreUrl(result.downloadUrl);
                        },
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          'Update',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fallback legacy screen retained for backward compatibility
class ForceUpdateScreen extends StatelessWidget {
  final VersionCheckResult result;

  const ForceUpdateScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: UpdatePromptDialog(result: result),
      ),
    );
  }
}

class VersionCheckEngine {
  static GlobalKey<NavigatorState>? navigatorKey;
  static bool _hasChecked = false;
  static bool isShowingDialog = false;

  // Compatibility getter/setter for any external references
  static bool get isShowingForceDialog => isShowingDialog;
  static set isShowingForceDialog(bool val) => isShowingDialog = val;

  static void start(BuildContext context, {GlobalKey<NavigatorState>? key}) {
    if (key != null) navigatorKey = key;
    if (_hasChecked) return;
    _hasChecked = true;

    // Do NOT prompt on frame 1 while splash screen is displaying.
    // Instead, schedule check smoothly after app is loaded.
    scheduleCheckAfterAppLoad(context: context);
  }

  /// Schedules the version check to trigger smoothly after the app has fully loaded and settled.
  static void scheduleCheckAfterAppLoad({BuildContext? context, Duration delay = const Duration(milliseconds: 1500)}) {
    Future.delayed(delay, () {
      final targetContext = navigatorKey?.currentContext ?? context;
      if (targetContext != null && targetContext.mounted) {
        checkAndPrompt(context: targetContext);
      }
    });
  }

  static Future<void> checkAndPrompt({BuildContext? context}) async {
    if (isShowingDialog) return;

    try {
      final isSnoozed = await VersionCheckService.isSnoozedToday();
      if (isSnoozed) return;

      final result = await VersionCheckService.checkVersion();
      // CRITICAL: Only prompt dialog on startup if FORCE UPDATE is configured (shouldForce == true)!
      // Normal/optional updates should NOT interrupt the user on launch with a modal popup.
      if (result.shouldForce) {
        final targetContext = navigatorKey?.currentContext ?? context;
        if (targetContext != null && targetContext.mounted) {
          showUpdateDialog(result, targetContext);
        }
      }
    } catch (e) {
      debugPrint('VersionCheckEngine error: $e');
    }
  }

  static void showUpdateDialog(VersionCheckResult result, BuildContext context) async {
    if (isShowingDialog) return;
    final isSnoozed = await VersionCheckService.isSnoozedToday();
    if (isSnoozed || !context.mounted) return;

    isShowingDialog = true;

    try {
      await showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: UpdatePromptDialog(result: result),
        ),
      );
    } finally {
      isShowingDialog = false;
    }
  }

  static void showForceUpdateDialog(VersionCheckResult result, [BuildContext? context]) {
    final targetContext = navigatorKey?.currentContext ?? context;
    if (targetContext != null) {
      showUpdateDialog(result, targetContext);
    }
  }
}
