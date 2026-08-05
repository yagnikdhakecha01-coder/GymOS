import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      if (AdminSupabaseService.isInitialized) {
        final client = AdminSupabaseService.client;
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
      }
    } catch (e) {
      debugPrint('Error loading trial settings: $e');
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
          content: Text('Settings saved successfully! Trial defaults updated in backend.'),
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
      _smtpUserController, _appStoreController, _playStoreController, _trialDurationController
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
              Text('Company settings and default free trial configuration', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
              const SizedBox(height: 28),

              // NEW: Default Free Trial Configuration Section
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
              _section(context, 'Company Information', Icons.business_rounded, [
                _field('Company Name', _companyNameController),
                _field('GST Number', _gstController),
                _field('Support Email', _supportEmailController),
                _field('Phone', _phoneController),
              ]),
              const SizedBox(height: 20),
              _section(context, 'Legal', Icons.gavel_rounded, [
                _field('Privacy Policy URL', _privacyUrlController),
                _field('Terms & Conditions URL', _termsUrlController),
              ]),
              const SizedBox(height: 20),
              _section(context, 'SMTP Configuration', Icons.email_rounded, [
                Row(children: [
                  Expanded(child: _field('SMTP Host', _smtpHostController)),
                  const SizedBox(width: 16),
                  SizedBox(width: 120, child: _field('Port', _smtpPortController)),
                ]),
                _field('SMTP Username', _smtpUserController),
              ]),
              const SizedBox(height: 20),
              _section(context, 'App Store Links', Icons.link_rounded, [
                _field('App Store URL', _appStoreController),
                _field('Play Store URL', _playStoreController),
              ]),
              const SizedBox(height: 20),
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
      decoration: BoxDecoration(color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard), border: Border.all(color: AdminTheme.borderColor(context))),
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
}
