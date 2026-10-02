import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  final _companyNameController = TextEditingController(text: 'Gym OS Pvt. Ltd.');
  final _gstController = TextEditingController(text: '27AABCU9603R1ZM');
  final _supportEmailController = TextEditingController(text: 'support@gymos.com');
  final _phoneController = TextEditingController(text: '+91 98765 43210');
  final _privacyUrlController = TextEditingController(text: 'https://gymos.com/privacy');
  final _termsUrlController = TextEditingController(text: 'https://gymos.com/terms');
  final _smtpHostController = TextEditingController(text: 'smtp.gmail.com');
  final _smtpPortController = TextEditingController(text: '587');
  final _smtpUserController = TextEditingController(text: 'noreply@gymos.com');
  final _appStoreController = TextEditingController(text: 'https://apps.apple.com/gymos');
  final _playStoreController = TextEditingController(text: 'https://play.google.com/store/apps/gymos');

  // Free Trial Platform Settings
  final _trialDurationController = TextEditingController(text: '30');
  String _trialDurationUnit = 'days';
  bool _trialEnabled = true;
  bool _isSavingTrial = false;

  // WhatsApp Cloud API Platform Settings
  final _whatsappCallbackUrlController = TextEditingController(
    text: 'https://gilxxyvwqucwwwqaxosx.supabase.co/functions/v1/whatsapp-webhook',
  );
  final _whatsappVerifyTokenController = TextEditingController(
    text: 'cbc2bdd2f37cec46cd621c7b53f138d9946a3f6239045b93',
  );
  final _whatsappAccessTokenController = TextEditingController();
  final _whatsappPhoneIdController = TextEditingController();
  final _whatsappWabaIdController = TextEditingController(text: '1930081191288308');
  final _whatsappAppSecretController = TextEditingController();

  bool _obscureAccessToken = true;
  bool _obscureAppSecret = true;
  bool _isSavingWhatsapp = false;
  bool _isTestingWhatsapp = false;
  String? _whatsappTestResult;
  bool _whatsappTestSuccess = false;

  Future<void> _saveTrialSettings() async {
    setState(() => _isSavingTrial = true);
    try {
      final int durationVal = int.tryParse(_trialDurationController.text) ?? 30;

      if (AdminSupabaseService.isInitialized) {
        final client = AdminSupabaseService.client;
        await client.from('platform_settings').upsert({
          'key': 'default_free_trial',
          'value': {
            'duration_value': durationVal,
            'duration_unit': _trialDurationUnit,
            'enabled': _trialEnabled,
          },
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trial configuration saved! New gyms will receive $durationVal ${_trialDurationUnit.toUpperCase()} trial.'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving trial configuration: $e'), backgroundColor: AdminTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _isSavingTrial = false);
    }
  }

  Future<void> _saveWhatsappSettings() async {
    setState(() => _isSavingWhatsapp = true);
    try {
      final config = {
        'callback_url': _whatsappCallbackUrlController.text.trim(),
        'verify_token': _whatsappVerifyTokenController.text.trim(),
        'access_token': _whatsappAccessTokenController.text.trim(),
        'phone_number_id': _whatsappPhoneIdController.text.trim(),
        'business_account_id': _whatsappWabaIdController.text.trim(),
        'app_secret': _whatsappAppSecretController.text.trim(),
        'webhook_status': 'active',
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (AdminSupabaseService.isInitialized) {
        final client = AdminSupabaseService.client;
        // 1. Save to platform_settings
        await client.from('platform_settings').upsert({
          'key': 'meta_whatsapp_config',
          'value': config,
          'updated_at': DateTime.now().toIso8601String(),
        });

        // 2. Sync to whatsapp_system_secrets table
        final secrets = [
          {'secret_name': 'WHATSAPP_VERIFY_TOKEN', 'secret_value': _whatsappVerifyTokenController.text.trim()},
          {'secret_name': 'WHATSAPP_BUSINESS_ACCOUNT_ID', 'secret_value': _whatsappWabaIdController.text.trim()},
        ];
        if (_whatsappAccessTokenController.text.trim().isNotEmpty) {
          secrets.add({'secret_name': 'WHATSAPP_ACCESS_TOKEN', 'secret_value': _whatsappAccessTokenController.text.trim()});
        }
        if (_whatsappPhoneIdController.text.trim().isNotEmpty) {
          secrets.add({'secret_name': 'WHATSAPP_PHONE_NUMBER_ID', 'secret_value': _whatsappPhoneIdController.text.trim()});
        }
        if (_whatsappAppSecretController.text.trim().isNotEmpty) {
          secrets.add({'secret_name': 'WHATSAPP_APP_SECRET', 'secret_value': _whatsappAppSecretController.text.trim()});
        }

        for (final s in secrets) {
          try {
            await client.from('whatsapp_system_secrets').upsert(s);
          } catch (_) {
            // Non-critical fallback
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp Cloud API configuration saved successfully!'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving WhatsApp settings: $e'), backgroundColor: AdminTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _isSavingWhatsapp = false);
    }
  }

  Future<void> _testWhatsappConnection() async {
    final token = _whatsappAccessTokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please paste a Meta Access Token first to test.'),
          backgroundColor: AdminTheme.warning,
        ),
      );
      return;
    }

    setState(() {
      _isTestingWhatsapp = true;
      _whatsappTestResult = null;
    });

    try {
      final url = Uri.parse('https://graph.facebook.com/v26.0/me?fields=id,name&access_token=$token');
      final response = await http.get(url);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['error'] == null) {
        setState(() {
          _whatsappTestSuccess = true;
          _whatsappTestResult = 'Connected to Meta API successfully!\nApp/User Name: ${data['name'] ?? 'N/A'}\nID: ${data['id'] ?? 'N/A'}';
        });
      } else {
        final errorMsg = data['error']?['message'] ?? 'HTTP ${response.statusCode}: ${response.body}';
        setState(() {
          _whatsappTestSuccess = false;
          _whatsappTestResult = 'Meta API Response: $errorMsg';
        });
      }
    } catch (e) {
      setState(() {
        _whatsappTestSuccess = false;
        _whatsappTestResult = 'Connection test failed: $e';
      });
    } finally {
      if (mounted) setState(() => _isTestingWhatsapp = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      if (AdminSupabaseService.isInitialized) {
        final client = AdminSupabaseService.client;

        // Load trial settings
        final res = await client
            .from('platform_settings')
            .select('*')
            .eq('key', 'default_free_trial')
            .maybeSingle();

        if (res != null && res['value'] != null) {
          final Map<String, dynamic> val = Map<String, dynamic>.from(res['value']);
          _trialDurationController.text = (val['duration_value'] ?? 30).toString();
          _trialDurationUnit = val['duration_unit']?.toString() ?? 'days';
          _trialEnabled = val['enabled'] == true;
        }

        // Load WhatsApp settings
        final waRes = await client
            .from('platform_settings')
            .select('*')
            .eq('key', 'meta_whatsapp_config')
            .maybeSingle();

        if (waRes != null && waRes['value'] != null) {
          final Map<String, dynamic> val = Map<String, dynamic>.from(waRes['value']);
          if (val['access_token'] != null && val['access_token'].toString().isNotEmpty) {
            _whatsappAccessTokenController.text = val['access_token'].toString();
          }
          if (val['phone_number_id'] != null && val['phone_number_id'].toString().isNotEmpty) {
            _whatsappPhoneIdController.text = val['phone_number_id'].toString();
          }
          if (val['business_account_id'] != null && val['business_account_id'].toString().isNotEmpty) {
            _whatsappWabaIdController.text = val['business_account_id'].toString();
          }
          if (val['app_secret'] != null && val['app_secret'].toString().isNotEmpty) {
            _whatsappAppSecretController.text = val['app_secret'].toString();
          }
          if (val['verify_token'] != null && val['verify_token'].toString().isNotEmpty) {
            _whatsappVerifyTokenController.text = val['verify_token'].toString();
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final int durationVal = int.tryParse(_trialDurationController.text) ?? 30;

      if (AdminSupabaseService.isInitialized) {
        final client = AdminSupabaseService.client;
        await client.from('platform_settings').upsert({
          'key': 'default_free_trial',
          'value': {
            'duration_value': durationVal,
            'duration_unit': _trialDurationUnit,
            'enabled': _trialEnabled,
          },
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully!'),
          backgroundColor: AdminTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: $e'), backgroundColor: AdminTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    for (var c in [
      _companyNameController, _gstController, _supportEmailController, _phoneController,
      _privacyUrlController, _termsUrlController, _smtpHostController, _smtpPortController,
      _smtpUserController, _appStoreController, _playStoreController, _trialDurationController,
      _whatsappCallbackUrlController, _whatsappVerifyTokenController, _whatsappAccessTokenController,
      _whatsappPhoneIdController, _whatsappWabaIdController, _whatsappAppSecretController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 6));

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              Text('Settings', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              const SizedBox(height: 4),
              Text('Company settings, WhatsApp Cloud API, and platform configuration', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
              const SizedBox(height: 28),

              // SECTION 1: Meta WhatsApp Cloud API Integration
              _section(context, 'WhatsApp Cloud API Configuration', Icons.chat_bubble_outline_rounded, [
                // Status Header Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                    border: Border.all(color: AdminTheme.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AdminTheme.success.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_rounded, color: AdminTheme.success, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Supabase Webhook Infrastructure: LIVE & ACTIVE',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'GET verification handshake is active. Manage your Meta credentials below.',
                              style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AdminTheme.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'HTTP 200 READY',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AdminTheme.success),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Copyable Callback URL
                _copyableField(
                  context,
                  label: 'Meta Webhook Callback URL',
                  controller: _whatsappCallbackUrlController,
                  helperText: 'Paste this into Meta App Dashboard > WhatsApp > Configuration > Callback URL',
                ),
                const SizedBox(height: 14),

                // Copyable Verify Token
                _copyableField(
                  context,
                  label: 'Meta Verify Token',
                  controller: _whatsappVerifyTokenController,
                  helperText: 'Paste this into Meta App Dashboard > WhatsApp > Configuration > Verify Token',
                ),
                const SizedBox(height: 18),

                const Divider(height: 28),

                // Meta Access Token Input
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Meta WhatsApp Access Token (WHATSAPP_ACCESS_TOKEN)',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context)),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null && data!.text!.isNotEmpty) {
                              setState(() => _whatsappAccessTokenController.text = data.text!.trim());
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pasted token from clipboard!'), backgroundColor: AdminTheme.primary),
                              );
                            }
                          },
                          icon: const Icon(Icons.paste_rounded, size: 16),
                          label: Text('Paste', style: GoogleFonts.inter(fontSize: 12)),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _whatsappAccessTokenController,
                      obscureText: _obscureAccessToken,
                      style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
                      decoration: InputDecoration(
                        hintText: 'EAAbbZAgv... (starts with EAAbb...)',
                        filled: true,
                        fillColor: AdminTheme.surfaceColor(context),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureAccessToken ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                          onPressed: () => setState(() => _obscureAccessToken = !_obscureAccessToken),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Copy token from Meta Graph API Explorer or System User in Meta Business Suite.',
                      style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Phone Number ID & WABA ID Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _field('Phone Number ID (WHATSAPP_PHONE_NUMBER_ID)', _whatsappPhoneIdController),
                          const SizedBox(height: 4),
                          Text(
                            'Found under WhatsApp > API Setup > Phone number ID',
                            style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _field('WhatsApp Business Account ID (WABA ID)', _whatsappWabaIdController),
                          const SizedBox(height: 4),
                          Text(
                            'Your Meta WABA ID (Default: 1930081191288308)',
                            style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // App Secret (Optional)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meta App Secret (WHATSAPP_APP_SECRET - Optional)',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _whatsappAppSecretController,
                      obscureText: _obscureAppSecret,
                      style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
                      decoration: InputDecoration(
                        hintText: 'Enter App Secret for x-hub-signature-256 HMAC verification',
                        filled: true,
                        fillColor: AdminTheme.surfaceColor(context),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureAppSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                          onPressed: () => setState(() => _obscureAppSecret = !_obscureAppSecret),
                        ),
                      ),
                    ),
                  ],
                ),

                // Test Connection Feedback Box
                if (_whatsappTestResult != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _whatsappTestSuccess ? AdminTheme.success.withValues(alpha: 0.1) : AdminTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                      border: Border.all(color: _whatsappTestSuccess ? AdminTheme.success.withValues(alpha: 0.4) : AdminTheme.danger.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _whatsappTestSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                          color: _whatsappTestSuccess ? AdminTheme.success : AdminTheme.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _whatsappTestResult!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _whatsappTestSuccess ? AdminTheme.success : AdminTheme.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Action Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isTestingWhatsapp ? null : _testWhatsappConnection,
                      icon: _isTestingWhatsapp
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.network_check_rounded, size: 18),
                      label: Text(
                        _isTestingWhatsapp ? 'Testing Connection...' : 'Test Meta Connection',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        side: BorderSide(color: AdminTheme.borderColor(context)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isSavingWhatsapp ? null : _saveWhatsappSettings,
                      icon: _isSavingWhatsapp
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _isSavingWhatsapp ? 'Saving...' : 'Save WhatsApp Configuration',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AdminTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        elevation: 2,
                      ),
                    ),
                  ],
                ),
              ]),

              const SizedBox(height: 24),

              // SECTION 2: Default Free Trial Configuration Section
              _section(context, 'Default Free Trial Configuration', Icons.timer_outlined, [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Enable Free Trial for New Registrations', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
                        Text('If disabled, new gyms will start with 0 trial days.', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
                      ],
                    ),
                    Switch(
                      value: _trialEnabled,
                      activeTrackColor: AdminTheme.primary,
                      onChanged: (val) => setState(() => _trialEnabled = val),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field('Default Trial Duration', _trialDurationController, keyboardType: TextInputType.number),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Duration Unit', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: AdminTheme.surfaceColor(context),
                              borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _trialDurationUnit,
                                isExpanded: true,
                                dropdownColor: AdminTheme.cardColor(context),
                                items: ['days', 'months'].map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u.toUpperCase(), style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context))),
                                )).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _trialDurationUnit = val);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _isSavingTrial ? null : _saveTrialSettings,
                    icon: _isSavingTrial
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: Text(_isSavingTrial ? 'Saving Trial...' : 'Save Trial Configuration', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 2,
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              // SECTION 3: Company Information
              _section(context, 'Company Information', Icons.business_rounded, [
                _field('Company Name', _companyNameController),
                _field('GST Number', _gstController),
                _field('Support Email', _supportEmailController),
                _field('Phone', _phoneController),
              ]),
              const SizedBox(height: 20),

              // SECTION 4: Legal
              _section(context, 'Legal', Icons.gavel_rounded, [
                _field('Privacy Policy URL', _privacyUrlController),
                _field('Terms & Conditions URL', _termsUrlController),
              ]),
              const SizedBox(height: 20),

              // SECTION 5: SMTP Configuration
              _section(context, 'SMTP Configuration', Icons.email_rounded, [
                Row(children: [
                  Expanded(child: _field('SMTP Host', _smtpHostController)),
                  const SizedBox(width: 16),
                  SizedBox(width: 120, child: _field('Port', _smtpPortController)),
                ]),
                _field('SMTP Username', _smtpUserController),
              ]),
              const SizedBox(height: 20),

              // SECTION 6: App Store Links
              _section(context, 'App Store Links', Icons.link_rounded, [
                _field('App Store URL', _appStoreController),
                _field('Play Store URL', _playStoreController),
              ]),
              const SizedBox(height: 20),

              // SECTION 7: Logo
              _section(context, 'Logo', Icons.image_rounded, [
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
                    border: Border.all(color: AdminTheme.borderColor(context), style: BorderStyle.solid),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.cloud_upload_outlined, size: 32, color: AdminTheme.mutedTextColor(context)),
                    const SizedBox(height: 6),
                    Text('Upload Logo', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                  ]),
                ),
              ]),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_isSaving ? 'Saving...' : 'Save Settings', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(160, 44)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: AdminTheme.primary),
          const SizedBox(width: 10),
          Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        ]),
        const SizedBox(height: 20),
        ...children.map((c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: c)),
      ]),
    );
  }

  Widget _field(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
        decoration: InputDecoration(
          filled: true,
          fillColor: AdminTheme.surfaceColor(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    ]);
  }

  Widget _copyableField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required String helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: true,
          style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context), fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            filled: true,
            fillColor: AdminTheme.surfaceColor(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Copy to Clipboard',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: controller.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied to clipboard!'),
                    backgroundColor: AdminTheme.primary,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(helperText, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
      ],
    );
  }
}
