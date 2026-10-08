import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/admin_theme.dart';
import '../../../core/theme/responsive.dart';
import '../services/template_service.dart';

class WhatsAppInvitationSettingsDialog extends StatefulWidget {
  final List<WhatsAppTemplate> templates;

  const WhatsAppInvitationSettingsDialog({
    super.key,
    required this.templates,
  });

  @override
  State<WhatsAppInvitationSettingsDialog> createState() =>
      _WhatsAppInvitationSettingsDialogState();
}

class _WhatsAppInvitationSettingsDialogState
    extends State<WhatsAppInvitationSettingsDialog> {
  final WhatsAppTemplateService _service = WhatsAppTemplateService.instance;
  final TextEditingController _testPhoneController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSendingTest = false;
  String? _statusMessage;
  bool _isError = false;

  // Settings State
  bool _autoSendEnabled = false;
  String? _selectedTemplateName;
  String _selectedLanguage = 'en_US';
  Map<String, String> _paramMapping = {
    '1': 'gym_name',
    '2': 'name',
    '3': 'invitation_code',
    '4': 'phone',
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _testPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _service.getInvitationSettings();
      setState(() {
        _autoSendEnabled = settings['auto_send_enabled'] == true;
        _selectedTemplateName = settings['template_name']?.toString();
        _selectedLanguage =
            settings['template_language']?.toString() ?? 'en_US';
        if (settings['param_mapping'] != null) {
          _paramMapping = Map<String, String>.from(
            (settings['param_mapping'] as Map).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
          );
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _statusMessage = 'Could not load existing settings: $e';
      });
    }
  }

  WhatsAppTemplate? get _currentSelectedTemplate {
    if (_selectedTemplateName == null || _selectedTemplateName!.isEmpty) {
      return null;
    }
    return widget.templates
        .where((t) => t.name == _selectedTemplateName)
        .firstOrNull;
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });
    try {
      final payload = {
        'auto_send_enabled': _autoSendEnabled,
        'template_name': _selectedTemplateName ?? '',
        'template_language': _selectedLanguage,
        'param_mapping': _paramMapping,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await _service.saveInvitationSettings(payload);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isError = false;
          _statusMessage = 'Settings saved successfully!';
        });
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) Navigator.pop(context, true);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isError = true;
          _statusMessage = 'Failed to save settings: $e';
        });
      }
    }
  }

  Future<void> _sendTestMessage() async {
    final phone = _testPhoneController.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _isError = true;
        _statusMessage = 'Please enter a test phone number with country code.';
      });
      return;
    }

    if (_selectedTemplateName == null || _selectedTemplateName!.isEmpty) {
      setState(() {
        _isError = true;
        _statusMessage = 'Please select a template first.';
      });
      return;
    }

    setState(() {
      _isSendingTest = true;
      _statusMessage = null;
    });

    try {
      final customSettings = {
        'auto_send_enabled': _autoSendEnabled,
        'template_name': _selectedTemplateName,
        'template_language': _selectedLanguage,
        'param_mapping': _paramMapping,
      };

      await _service.sendInvitationTemplate(
        toPhoneNumber: phone,
        gymName: 'Iron Fitness Club (Test Gym)',
        contactName: 'Test Recipient',
        invitationCode: 'GYM-TEST-99',
        customSettings: customSettings,
      );

      if (mounted) {
        setState(() {
          _isSendingTest = false;
          _isError = false;
          _statusMessage = 'Test invitation sent successfully to $phone!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSendingTest = false;
          _isError = true;
          _statusMessage = 'Test send failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AdminTheme.isDark(context);
    final isMobile = AdminResponsive.isMobile(context);

    return Dialog(
      backgroundColor:
          isDark ? AdminTheme.darkCard : AdminTheme.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminTheme.radiusMd),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 40,
        vertical: 24,
      ),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 820),
        child: Column(
          children: [
            // Header
            _buildDialogHeader(context, isDark),
            const Divider(height: 1),
            // Body Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF25D366)),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusBanner(isDark),
                          const SizedBox(height: 20),
                          _buildAutoSendToggleCard(isDark),
                          const SizedBox(height: 20),
                          _buildTemplatePickerCard(isDark),
                          const SizedBox(height: 20),
                          if (_currentSelectedTemplate != null) ...[
                            _buildTemplatePreviewCard(isDark),
                            const SizedBox(height: 20),
                            _buildVariableMappingCard(isDark),
                            const SizedBox(height: 20),
                          ],
                          _buildTestSendCard(isDark),
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            // Footer
            _buildDialogFooter(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: Color(0xFF25D366),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WhatsApp Invitation Settings',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textColor(context),
                  ),
                ),
                Text(
                  'Configure template & variables for automated & bulk invites',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AdminTheme.secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            color: AdminTheme.secondaryTextColor(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(bool isDark) {
    if (_statusMessage == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF25D366).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF25D366).withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 20, color: Color(0xFF25D366)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'By default, automated dispatch is DISABLED. You can configure the template here and send to pending members manually anytime.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isError
            ? AdminTheme.danger.withValues(alpha: 0.1)
            : AdminTheme.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isError
              ? AdminTheme.danger.withValues(alpha: 0.3)
              : AdminTheme.success.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 20,
            color: _isError ? AdminTheme.danger : AdminTheme.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage!,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _isError ? AdminTheme.danger : AdminTheme.success,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSendToggleCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _autoSendEnabled
              ? const Color(0xFF25D366).withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Auto-Send on New Member / Staff Registration',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AdminTheme.textColor(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _autoSendEnabled
                            ? const Color(0xFF25D366).withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _autoSendEnabled ? 'ACTIVE' : 'DISABLED',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _autoSendEnabled
                              ? const Color(0xFF25D366)
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'If turned ON, every new record added to the invitations table will automatically be dispatched via WhatsApp. (Default: OFF)',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AdminTheme.secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _autoSendEnabled,
            activeThumbColor: const Color(0xFF25D366),
            onChanged: (val) {
              setState(() => _autoSendEnabled = val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatePickerCard(bool isDark) {
    final approvedTemplates =
        widget.templates.where((t) => t.status == 'APPROVED').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select WhatsApp Template',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminTheme.textColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: approvedTemplates.any((t) => t.name == _selectedTemplateName)
                  ? _selectedTemplateName
                  : null,
              hint: Text(
                approvedTemplates.isEmpty
                    ? 'No approved templates found on Meta'
                    : 'Choose an approved template...',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AdminTheme.mutedTextColor(context),
                ),
              ),
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              items: approvedTemplates.map((t) {
                return DropdownMenuItem<String>(
                  value: t.name,
                  child: Row(
                    children: [
                      const Icon(Icons.description_rounded,
                          size: 16, color: Color(0xFF25D366)),
                      const SizedBox(width: 8),
                      Text(
                        t.name,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.textColor(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${t.language} • ${t.category})',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AdminTheme.secondaryTextColor(context),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  final t = widget.templates.firstWhere((item) => item.name == val);
                  setState(() {
                    _selectedTemplateName = val;
                    _selectedLanguage = t.language;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTemplatePreviewCard(bool isDark) {
    final t = _currentSelectedTemplate!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.preview_rounded, size: 16, color: Color(0xFF25D366)),
              const SizedBox(width: 6),
              Text(
                'Template Message Preview:',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.bodyText,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.45,
              color: AdminTheme.textColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariableMappingCard(bool isDark) {
    final t = _currentSelectedTemplate!;
    final keys = t.bodyVariableKeys;

    if (keys.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'This template does not contain dynamic variable placeholders (e.g. {{1}}). Static text will be sent.',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.amber.shade900),
        ),
      );
    }

    final options = [
      {'label': 'Gym Name', 'value': 'gym_name'},
      {'label': 'Member / Staff Name', 'value': 'name'},
      {'label': 'Invitation Code', 'value': 'invitation_code'},
      {'label': 'Registered Mobile Number', 'value': 'phone'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Map Template Variables',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminTheme.textColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Assign which database values replace {{1}}, {{2}}, etc.',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AdminTheme.secondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 10),
        ...keys.map((k) {
          final currentVal = _paramMapping[k] ??
              (k == '1'
                  ? 'gym_name'
                  : k == '2'
                      ? 'name'
                      : k == '3'
                          ? 'invitation_code'
                          : 'phone');

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 90,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      'Variable {{$k}}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF25D366),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: options.any((o) => o['value'] == currentVal)
                            ? currentVal
                            : 'gym_name',
                        isExpanded: true,
                        dropdownColor:
                            isDark ? const Color(0xFF1E293B) : Colors.white,
                        items: options.map((opt) {
                          return DropdownMenuItem<String>(
                            value: opt['value'],
                            child: Text(
                              opt['label']!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AdminTheme.textColor(context),
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _paramMapping[k] = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTestSendCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.send_rounded, size: 16, color: Color(0xFF25D366)),
              const SizedBox(width: 8),
              Text(
                'Test Live Invitation Send',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Test your template with mock data (Gym: Iron Fitness, Code: GYM-TEST-99).',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AdminTheme.secondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _testPhoneController,
                    decoration: InputDecoration(
                      hintText: 'Enter phone with country code (e.g. 919876543210)',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: AdminTheme.mutedTextColor(context),
                      ),
                      prefixIcon: const Icon(Icons.phone_rounded, size: 16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _isSendingTest ? null : _sendTestMessage,
                icon: _isSendingTest
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(
                  _isSendingTest ? 'Sending...' : 'Test Send',
                  style: GoogleFonts.inter(fontSize: 12.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDialogFooter(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AdminTheme.secondaryTextColor(context)),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(
              _isSaving ? 'Saving...' : 'Save Settings',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
