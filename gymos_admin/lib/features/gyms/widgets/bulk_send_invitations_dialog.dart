import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/admin_theme.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/services/supabase_service.dart';
import '../../whatsapp_templates/services/template_service.dart';

class BulkSendInvitationsDialog extends StatefulWidget {
  final String gymId;
  final String gymName;

  const BulkSendInvitationsDialog({
    super.key,
    required this.gymId,
    required this.gymName,
  });

  @override
  State<BulkSendInvitationsDialog> createState() =>
      _BulkSendInvitationsDialogState();
}

class _BulkSendInvitationsDialogState extends State<BulkSendInvitationsDialog> {
  final WhatsAppTemplateService _templateService =
      WhatsAppTemplateService.instance;

  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _pendingInvitations = [];
  Map<String, dynamic>? _invitationSettings;

  // Sending progress
  bool _isSending = false;
  int _sentCount = 0;
  int _failCount = 0;
  int _totalToSend = 0;
  String _currentProcessingName = '';
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = AdminSupabaseService.client;

      // 1. Fetch configured template settings
      final settings = await _templateService.getInvitationSettings();

      // 2. Query pending invitations for this gym
      final response = await client
          .from('invitations')
          .select('*, members(id, name, phone), staff(id, name, phone)')
          .eq('gym_id', widget.gymId)
          .eq('status', 'Pending')
          .eq('code_used', false)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> list = [];
      for (final item in response as List) {
        final map = Map<String, dynamic>.from(item);

        // Resolve person name
        String name = 'Member';
        String role = 'Member';
        if (map['members'] != null && map['members']['name'] != null) {
          name = map['members']['name'].toString();
          role = 'Member';
        } else if (map['staff'] != null && map['staff']['name'] != null) {
          name = map['staff']['name'].toString();
          role = 'Staff';
        } else if (map['staff_id'] != null) {
          role = 'Staff';
        }

        map['_resolved_name'] = name;
        map['_resolved_role'] = role;
        list.add(map);
      }

      if (mounted) {
        setState(() {
          _invitationSettings = settings;
          _pendingInvitations = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load pending invitations: $e';
        });
      }
    }
  }

  Future<void> _startBulkDispatch() async {
    if (_pendingInvitations.isEmpty) return;

    final templateName = _invitationSettings?['template_name']?.toString() ?? '';
    if (templateName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No WhatsApp template selected! Please configure template in WA Templates > Invitation Settings first.'),
          backgroundColor: AdminTheme.danger,
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
      _sentCount = 0;
      _failCount = 0;
      _totalToSend = _pendingInvitations.length;
      _isFinished = false;
    });

    for (int i = 0; i < _pendingInvitations.length; i++) {
      if (!mounted) break;
      final invite = _pendingInvitations[i];
      final name = invite['_resolved_name'] ?? 'Member';
      final phone = invite['registered_mobile']?.toString() ?? '';
      final code = invite['invitation_code']?.toString() ?? '';

      setState(() {
        _currentProcessingName = name;
      });

      if (phone.isEmpty || code.isEmpty) {
        _failCount++;
        continue;
      }

      try {
        await _templateService.sendInvitationTemplate(
          toPhoneNumber: phone,
          gymName: widget.gymName,
          contactName: name,
          invitationCode: code,
          customSettings: _invitationSettings,
        );
        _sentCount++;
      } catch (e) {
        debugPrint('Failed to send invite to $phone ($name): $e');
        _failCount++;
      }

      if (mounted) {
        setState(() {});
      }

      // 350ms delay between dispatches to respect Meta rate limits
      await Future.delayed(const Duration(milliseconds: 350));
    }

    if (mounted) {
      setState(() {
        _isSending = false;
        _isFinished = true;
      });
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
        width: 680,
        constraints: const BoxConstraints(maxHeight: 780),
        child: Column(
          children: [
            // Header
            _buildHeader(context, isDark),
            const Divider(height: 1),
            // Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF25D366)),
                    )
                  : _errorMessage != null
                      ? _buildErrorView()
                      : _buildMainContent(isDark),
            ),
            const Divider(height: 1),
            // Footer
            _buildFooter(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
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
              Icons.send_rounded,
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
                  'Send WhatsApp Invites to Pending Contacts',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AdminTheme.textColor(context),
                  ),
                ),
                Text(
                  'Target Gym: ${widget.gymName}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF25D366),
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

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AdminTheme.danger),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.danger),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchData,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(bool isDark) {
    final templateName =
        _invitationSettings?['template_name']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Template Info Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.mark_email_read_rounded,
                    size: 20, color: Color(0xFF25D366)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        templateName.isNotEmpty
                            ? 'Active Template: $templateName'
                            : 'No WhatsApp Template Configured',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: templateName.isNotEmpty
                              ? AdminTheme.textColor(context)
                              : AdminTheme.danger,
                        ),
                      ),
                      Text(
                        templateName.isNotEmpty
                            ? 'Dynamic fields: Gym Name, Name, Invitation Code & Mobile are auto-injected.'
                            : 'Please configure a template in WA Templates > Invitation Settings first.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: AdminTheme.secondaryTextColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Sending Status or Summary
          if (_isSending || _isFinished) ...[
            _buildProgressCard(isDark),
            const SizedBox(height: 20),
          ],

          // Pending Recipients List
          Text(
            'Pending Recipients (${_pendingInvitations.length})',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Members and staff who have not yet linked their mobile app.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AdminTheme.secondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 12),

          if (_pendingInvitations.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 40, color: Color(0xFF25D366)),
                  const SizedBox(height: 10),
                  Text(
                    'No Pending Invitations!',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AdminTheme.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'All members and staff for this gym are active or verified.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AdminTheme.secondaryTextColor(context),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _pendingInvitations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _pendingInvitations[index];
                final name = item['_resolved_name'] ?? 'Member';
                final role = item['_resolved_role'] ?? 'Member';
                final phone = item['registered_mobile'] ?? '-';
                final code = item['invitation_code'] ?? '-';

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: role == 'Staff'
                            ? Colors.purple.withValues(alpha: 0.15)
                            : const Color(0xFF25D366).withValues(alpha: 0.15),
                        child: Icon(
                          role == 'Staff'
                              ? Icons.badge_rounded
                              : Icons.person_rounded,
                          size: 16,
                          color: role == 'Staff'
                              ? Colors.purple
                              : const Color(0xFF25D366),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AdminTheme.textColor(context),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: role == 'Staff'
                                        ? Colors.purple.withValues(alpha: 0.1)
                                        : Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    role,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: role == 'Staff'
                                          ? Colors.purple
                                          : Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Phone: $phone',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AdminTheme.secondaryTextColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          code,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: const Color(0xFF25D366),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(bool isDark) {
    final progress = _totalToSend > 0
        ? ((_sentCount + _failCount) / _totalToSend).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF25D366).withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isFinished
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_top_rounded,
                size: 18,
                color: const Color(0xFF25D366),
              ),
              const SizedBox(width: 8),
              Text(
                _isFinished
                    ? 'Bulk Dispatch Complete!'
                    : 'Dispatching: Sending to $_currentProcessingName...',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark ? Colors.black26 : Colors.black12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF25D366)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sent: $_sentCount • Failed: $_failCount of $_totalToSend',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.textColor(context),
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF25D366),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _isFinished ? 'Close' : 'Cancel',
              style: GoogleFonts.inter(
                  color: AdminTheme.secondaryTextColor(context)),
            ),
          ),
          if (!_isFinished) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: (_isSending || _pendingInvitations.isEmpty)
                  ? null
                  : _startBulkDispatch,
              icon: _isSending
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
                _isSending
                    ? 'Sending ($_sentCount/$_totalToSend)...'
                    : 'Send to All (${_pendingInvitations.length})',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
