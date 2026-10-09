import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/success_dialog.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/app_review_service.dart';
import '../authentication/auth_viewmodel.dart';
import '../authentication/role_selection_screen.dart';
import '../../core/navigation/app_router.dart';
import '../gym_settings/online_database_screen.dart';
import 'app_review_bottom_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _paymentAlerts = true;
  bool _biometricLock = false;
  String _selectedLanguage = 'English';
  bool _hasReviewed = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final reviewed = await AppReviewService.hasReviewed();
    setState(() {
      _pushNotifications = prefs.getBool('settings_push_notifications') ?? true;
      _paymentAlerts = prefs.getBool('settings_payment_alerts') ?? true;
      _biometricLock = prefs.getBool('settings_biometric_lock') ?? false;
      _selectedLanguage = prefs.getString('settings_selected_language') ?? 'English';
      _hasReviewed = reviewed;
    });

    if (SupabaseService.isInitialized) {
      try {
        final userId = SupabaseService.client.auth.currentUser?.id;
        if (userId != null) {
          final res = await SupabaseService.client
              .from('user_settings')
              .select()
              .eq('user_id', userId)
              .maybeSingle();

          if (res != null) {
            setState(() {
              _pushNotifications = res['push_notifications'] ?? true;
              _paymentAlerts = res['payment_alerts'] ?? true;
              _biometricLock = res['biometric_lock'] ?? false;
              _selectedLanguage = res['selected_language'] ?? 'English';
            });
            await prefs.setBool('settings_push_notifications', _pushNotifications);
            await prefs.setBool('settings_payment_alerts', _paymentAlerts);
            await prefs.setBool('settings_biometric_lock', _biometricLock);
            await prefs.setString('settings_selected_language', _selectedLanguage);
          }
        }
      } catch (e) {
        debugPrint('Error loading remote settings: $e');
      }
    }
  }

  Future<void> _saveSettingsField(String field, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool('settings_$field', value);
    } else if (value is String) {
      await prefs.setString('settings_$field', value);
    }

    if (SupabaseService.isInitialized) {
      try {
        final userId = SupabaseService.client.auth.currentUser?.id;
        if (userId != null) {
          await SupabaseService.client.from('user_settings').upsert({
            'user_id': userId,
            field: value,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
        debugPrint('Error saving setting: $e');
      }
    }
  }

  Widget _buildSwitchRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: AppTheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _showPasswordActionDialog(BuildContext context, bool hasPassword, String? email) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    
    bool showOldPassword = false;
    bool showNewPassword = false;
    bool showConfirmPassword = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                hasPassword ? 'Change Password' : 'Set Password',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasPassword) ...[
                      Text('Old Password', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: oldPasswordController,
                        obscureText: !showOldPassword,
                        style: GoogleFonts.inter(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Enter old password',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          suffixIcon: IconButton(
                            icon: Icon(showOldPassword ? Icons.visibility : Icons.visibility_off, size: 20),
                            onPressed: () => setDialogState(() => showOldPassword = !showOldPassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('New Password', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: newPasswordController,
                      obscureText: !showNewPassword,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Min 6 characters',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        suffixIcon: IconButton(
                          icon: Icon(showNewPassword ? Icons.visibility : Icons.visibility_off, size: 20),
                          onPressed: () => setDialogState(() => showNewPassword = !showNewPassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Confirm New Password', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: !showConfirmPassword,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Repeat new password',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        suffixIcon: IconButton(
                          icon: Icon(showConfirmPassword ? Icons.visibility : Icons.visibility_off, size: 20),
                          onPressed: () => setDialogState(() => showConfirmPassword = !showConfirmPassword),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final oldP = oldPasswordController.text.trim();
                          final newP = newPasswordController.text.trim();
                          final confirmP = confirmPasswordController.text.trim();

                          if (hasPassword && oldP.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter old password'), backgroundColor: AppTheme.danger),
                            );
                            return;
                          }
                          if (newP.isEmpty || newP.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password must be at least 6 characters'), backgroundColor: AppTheme.danger),
                            );
                            return;
                          }
                          if (newP != confirmP) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Passwords do not match'), backgroundColor: AppTheme.danger),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          try {
                            if (SupabaseService.isInitialized) {
                              final client = SupabaseService.client;
                              if (hasPassword && email != null) {
                                try {
                                  await client.auth.signInWithPassword(
                                    email: email,
                                    password: oldP,
                                  );
                                } catch (e) {
                                  throw Exception('Incorrect old password');
                                }
                              }

                              await client.auth.updateUser(
                                UserAttributes(
                                  password: newP,
                                  data: {'has_password': true},
                                ),
                              );
                            }

                            if (context.mounted) {
                              Navigator.pop(context);
                              SuccessDialog.show(
                                context,
                                title: 'Password Saved',
                                message: 'Your password has been updated successfully.',
                              );
                              setState(() {});
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString().replaceAll('Exception:', '').trim()),
                                  backgroundColor: AppTheme.danger,
                                ),
                              );
                            }
                          } finally {
                            setDialogState(() => isSaving = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openReviewSheet(BuildContext context) async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final role = (authVm.selectedRole ?? 'owner').toLowerCase();
    final gymId = authVm.gymInfo?['id']?.toString();
    await AppReviewBottomSheet.show(context, role: role, gymId: gymId);
    // Refresh tile state after returning from sheet
    if (mounted) {
      final reviewed = await AppReviewService.hasReviewed();
      setState(() => _hasReviewed = reviewed);
    }
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser;
    bool hasPassword = false;

    if (SupabaseService.isInitialized) {
      currentUser = SupabaseService.client.auth.currentUser;
      hasPassword = currentUser?.userMetadata?['has_password'] == true || 
          currentUser?.appMetadata['provider'] == 'email' ||
          (currentUser?.identities?.any((id) => id.provider == 'email') ?? false);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('General Settings'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          children: [
            // Notifications Group
            Text('NOTIFICATIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildSwitchRow(
                    'Push Notifications',
                    'Receive alerts for renewals and signups',
                    _pushNotifications,
                    (val) {
                      setState(() => _pushNotifications = val);
                      _saveSettingsField('push_notifications', val);
                    },
                  ),
                  const Divider(height: 1),
                  _buildSwitchRow(
                    'Payment Alerts',
                    'Get notified when payments are recorded',
                    _paymentAlerts,
                    (val) {
                      setState(() => _paymentAlerts = val);
                      _saveSettingsField('payment_alerts', val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Security Group
            Text('SECURITY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildSwitchRow(
                    'Biometric Lock',
                    'Require FaceID / TouchID to open app',
                    _biometricLock,
                    (val) async {
                      final supported = await BiometricService.isBiometricsSupported();
                      if (!supported) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Biometric authentication is not supported or set up on this device.'),
                              backgroundColor: AppTheme.danger,
                            ),
                          );
                        }
                        return;
                      }

                      final label = await BiometricService.getBiometricTypeLabel();
                      final authenticated = await BiometricService.authenticate(
                        message: 'Authenticate to ${val ? "enable" : "disable"} $label lock',
                      );

                      if (authenticated) {
                        setState(() => _biometricLock = val);
                        await BiometricService.setLockEnabled(val);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$label Lock ${val ? "enabled" : "disabled"} successfully!'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to authenticate. $label lock state not changed.'),
                              backgroundColor: AppTheme.danger,
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(hasPassword ? 'Change Password' : 'Set Password', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    subtitle: Text(hasPassword ? 'Update your account password' : 'Create a password for your account', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                    onTap: () => _showPasswordActionDialog(context, hasPassword, currentUser?.email),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Preferences Group
            Text('PREFERENCES', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text('Language', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    subtitle: Text(_selectedLanguage, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: const Text('Select Language'),
                          children: ['English', 'Hindi', 'Gujarati', 'Spanish'].map((lang) {
                            return SimpleDialogOption(
                              onPressed: () {
                                setState(() => _selectedLanguage = lang);
                                _saveSettingsField('selected_language', lang);
                                Navigator.pop(context);
                              },
                              child: Text(lang),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text('Online Database', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    subtitle: Text('View sync status, queue size, and retry operations', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineDatabaseScreen())),
                  ),
                  const Divider(height: 1),

                  // ── Rate GymOS ─────────────────────────────────
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      width: AppTheme.iconContainerSize,
                      height: AppTheme.iconContainerSize,
                      decoration: BoxDecoration(
                        color: _hasReviewed
                            ? AppTheme.successLight
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(AppTheme.radiusIconContainer),
                      ),
                      child: Icon(
                        Icons.star_rounded,
                        color: _hasReviewed
                            ? AppTheme.success
                            : const Color(0xFFF59E0B),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      _hasReviewed ? 'Thank You for Rating! ✓' : 'Rate GymOS',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      _hasReviewed
                          ? 'Your review helps other gyms discover GymOS'
                          : 'Love the app? Leave a review on Play Store',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                    onTap: () => _openReviewSheet(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Danger Zone
            Text('DANGER ZONE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            CustomCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 20),
                ),
                title: Text(
                  'Delete Account',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.red),
                ),
                subtitle: Text(
                  'Permanently erase your account and all associated gym data',
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.red),
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Account?',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete your account? All your gym records, profiles, staff and members will be permanently erased. This action CANNOT be undone.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: const Color(0xFF64748B),
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final authVm = Provider.of<AuthViewModel>(context, listen: false);
              final success = await authVm.deleteAccount();
              if (context.mounted && success) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  AppRouter.scaleRoute(const RoleSelectionScreen()),
                  (route) => false,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Your account has been permanently deleted.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(
              'Delete Forever',
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
