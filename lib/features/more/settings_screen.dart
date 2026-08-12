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
import '../authentication/auth_viewmodel.dart';
import '../gym_settings/online_database_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pushNotifications = prefs.getBool('settings_push_notifications') ?? true;
      _paymentAlerts = prefs.getBool('settings_payment_alerts') ?? true;
      _biometricLock = prefs.getBool('settings_biometric_lock') ?? false;
      _selectedLanguage = prefs.getString('settings_selected_language') ?? 'English';
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
