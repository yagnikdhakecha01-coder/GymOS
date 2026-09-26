import 'dart:convert';
import 'dart:io' show Platform;
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
  static Future<void> launchStoreUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }
}

class ForceUpdateScreen extends StatelessWidget {
  final VersionCheckResult result;

  const ForceUpdateScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent physical back button on Android
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.all(28.0),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        size: 38,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'CRITICAL UPDATE',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Update Required',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A mandatory update (v${result.latestVersion}) is required to continue using GymOS. Please update the app to proceed.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    if (result.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGray,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "What's New:",
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              result.releaseNotes,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => VersionCheckService.launchStoreUrl(result.downloadUrl),
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: Text(
                          'Update Now',
                          style: GoogleFonts.inter(
                            fontSize: 15,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VersionCheckEngine {
  static GlobalKey<NavigatorState>? navigatorKey;
  static bool _hasChecked = false;
  static bool isShowingForceDialog = false;

  static void start(BuildContext context, {GlobalKey<NavigatorState>? key}) {
    if (key != null) navigatorKey = key;
    if (_hasChecked) return;
    _hasChecked = true;

    // Perform silent background check
    VersionCheckService.checkVersion().then((result) {
      if (result.isUpdateAvailable) {
        if (result.shouldForce) {
          showForceUpdateDialog(result);
        } else if (result.isOptionalUpdate) {
          final targetContext = navigatorKey?.currentContext;
          if (targetContext != null) {
            _showOptionalUpdateDialog(targetContext, result);
          }
        }
      }
    }).catchError((e) {
      debugPrint('VersionCheckEngine error: $e');
    });
  }

  static void showForceUpdateDialog(VersionCheckResult result, [BuildContext? context]) {
    if (isShowingForceDialog) return;
    final targetContext = navigatorKey?.currentContext ?? context;
    if (targetContext == null) return;
    isShowingForceDialog = true;

    Navigator.of(targetContext, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => ForceUpdateScreen(result: result)),
      (route) => false,
    );
  }

  static void _showOptionalUpdateDialog(BuildContext context, VersionCheckResult result) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Update Available',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version (v${result.latestVersion}) of GymOS is ready. Would you like to update?',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              if (result.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGray,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's New:",
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.releaseNotes,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Later',
                style: GoogleFonts.inter(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _launchStoreUrl(result.downloadUrl);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                'Update Now',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _launchStoreUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }
}
