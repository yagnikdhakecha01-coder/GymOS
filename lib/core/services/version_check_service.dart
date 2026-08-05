import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';

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
        final String dlUrl = response['download_url'] ?? '';
        final String notes = response['release_notes'] ?? '';
        final bool isForce = response['is_force_update'] ?? false;
        final bool isOptional = response['is_optional_update'] ?? false;

        // Version comparisons
        final hasNewerVersion = compareVersions(AppConfig.appVersion, latestV) < 0;
        final isBelowMin = compareVersions(AppConfig.appVersion, minSupported) < 0;

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
}

class VersionCheckEngine {
  static bool _hasChecked = false;

  static void start(BuildContext context) {
    if (_hasChecked) return;
    _hasChecked = true;

    // Perform silent background check
    VersionCheckService.checkVersion().then((result) {
      if (result.isUpdateAvailable) {
        if (result.shouldForce) {
          _showForceUpdateDialog(context, result);
        } else if (result.isOptionalUpdate) {
          _showOptionalUpdateDialog(context, result);
        }
      }
    });
  }

  static void _showForceUpdateDialog(BuildContext context, VersionCheckResult result) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Force Update',
      pageBuilder: (context, anim1, anim2) {
        return PopScope(
          canPop: false, // Prevent physical back button on Android
          child: Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update_rounded, size: 40, color: Colors.redAccent),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Update Required',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A critical update (v${result.latestVersion}) is required to continue using GymOS. Please update the app to proceed.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.5),
                    ),
                    if (result.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'What\'s New:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              result.releaseNotes,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 36),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => _launchStoreUrl(result.downloadUrl),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C3AED),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: const Text('Update Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static void _showOptionalUpdateDialog(BuildContext context, VersionCheckResult result) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'New Version Available',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version (v${result.latestVersion}) of GymOS is available. Would you like to update now?',
                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14, height: 1.4),
              ),
              if (result.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Release Notes:',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        result.releaseNotes,
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Later',
                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _launchStoreUrl(result.downloadUrl);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
