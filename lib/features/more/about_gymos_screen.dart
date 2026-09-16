import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/config/app_config.dart';
import '../../core/services/version_check_service.dart';
import 'package:provider/provider.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/widgets/app_branding_header.dart';

class AboutGymOSScreen extends StatefulWidget {
  const AboutGymOSScreen({super.key});

  @override
  State<AboutGymOSScreen> createState() => _AboutGymOSScreenState();
}

class _AboutGymOSScreenState extends State<AboutGymOSScreen> {
  bool _isChecking = false;
  VersionCheckResult? _checkResult;

  Future<void> _checkUpdate() async {
    setState(() {
      _isChecking = true;
      _checkResult = null;
    });

    // Add a slight artificial delay for premium loading experience
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      final result = await VersionCheckService.checkVersion();
      setState(() {
        _checkResult = result;
        _isChecking = false;
      });

      if (mounted) {
        if (result.isUpdateAvailable) {
          _showUpdateDetailsBottomSheet(result);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'You are on the latest version!',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isChecking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check for updates: ${e.toString()}'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _showUpdateDetailsBottomSheet(VersionCheckResult result) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.system_update_rounded, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Update Available',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${result.latestVersion} (Build ${result.latestBuildNumber})',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (result.releaseNotes.isNotEmpty) ...[
                Text(
                  'Release Notes:',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      result.releaseNotes,
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), height: 1.4),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _launchStoreUrl(result.downloadUrl);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Update Now',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchStoreUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(Provider.of<AuthViewModel>(context, listen: false).isCustomBrandingEnabled
            ? 'About ${Provider.of<AuthViewModel>(context, listen: false).customBrandingName}'
            : 'About GymOS'),
        centerTitle: false,
        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              // App Branding Header (Custom logo & Name)
              const AppBrandingHeader(
                logoSize: 72,
                fontSize: 24,
                spacing: 16,
                welcomeText: false,
              ),
              const SizedBox(height: 6),
              Text(
                'Version ${AppConfig.appVersion} (Build ${AppConfig.buildNumber})',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              // Check Update Button
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _isChecking ? null : _checkUpdate,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primary, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                  ),
                  icon: _isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          ),
                        )
                      : const Icon(Icons.sync_rounded, size: 18, color: AppTheme.primary),
                  label: Text(
                    _isChecking ? 'Checking...' : 'Check for Updates',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary),
                  ),
                ),
              ),
              const Spacer(flex: 1),

              // Version Details List
              CustomCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      title: Text('Terms of Service', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textMuted),
                      onTap: () async {
                        final uri = Uri.parse('https://gymos.tech/terms-of-service.html');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text('Privacy Policy', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textMuted),
                      onTap: () async {
                        final uri = Uri.parse('https://gymos.tech/privacy-policy.html');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text('Licensing Agreement', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textMuted),
                      onTap: () async {
                        final uri = Uri.parse('https://gymos.tech/licensing-agreement.html');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text('Account & Data Deletion', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textMuted),
                      onTap: () async {
                        final uri = Uri.parse('https://gymos.tech/delete-account.html');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              
              Text(
                '© 2026 GymOS Inc. All rights reserved.',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
