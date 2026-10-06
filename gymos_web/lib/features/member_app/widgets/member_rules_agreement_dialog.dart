import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/models/gym_rules_model.dart';
import '../member_app_viewmodel.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../authentication/role_selection_screen.dart';

class MemberRulesAgreementDialog extends StatefulWidget {
  final bool isViewOnly;
  final MemberAgreementRecord? existingAgreement;

  const MemberRulesAgreementDialog({
    super.key,
    this.isViewOnly = false,
    this.existingAgreement,
  });

  static Future<bool?> show(
    BuildContext context, {
    bool isViewOnly = false,
    MemberAgreementRecord? existingAgreement,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: isViewOnly,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => MemberRulesAgreementDialog(
        isViewOnly: isViewOnly,
        existingAgreement: existingAgreement,
      ),
    );
  }

  @override
  State<MemberRulesAgreementDialog> createState() => _MemberRulesAgreementDialogState();
}

class _MemberRulesAgreementDialogState extends State<MemberRulesAgreementDialog> {
  late RuleLanguage _selectedLanguage;
  bool _hasReadRules = false;
  bool _hasAgreedRules = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingAgreement != null && widget.existingAgreement!.language.isNotEmpty) {
      _selectedLanguage = RuleLanguage.fromCode(widget.existingAgreement!.language);
    } else {
      _selectedLanguage = RuleLanguage.en;
    }

    if (widget.isViewOnly) {
      _hasReadRules = true;
      _hasAgreedRules = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktopOrTablet = screenSize.width > 700;
    final vm = Provider.of<MemberAppViewModel>(context);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);

    // Strictly resolve Gym Name — NEVER show GYMOS or generic app name
    String gymName = vm.gymName.trim();
    if (gymName.isEmpty || gymName.toUpperCase() == 'GYMOS') {
      gymName = (authVm.gymInfo?['name']?.toString() ?? '').trim();
    }
    if (gymName.isEmpty || gymName.toUpperCase() == 'GYMOS') {
      gymName = (authVm.activeAssociation?.gymName ?? '').trim();
    }

    String? gymLogoUrl = vm.gymLogoUrl;
    if (gymLogoUrl.isEmpty) {
      gymLogoUrl = authVm.gymInfo?['logo_url']?.toString();
    }


    final rules = DefaultGymRules.getRules(_selectedLanguage, customRulesData: vm.customRulesData);
    final labels = DefaultGymRules.getLabels(_selectedLanguage, gymName: gymName);

    final dialogContent = Container(
      width: isDesktopOrTablet ? 680 : double.infinity,
      constraints: BoxConstraints(
        maxHeight: screenSize.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isDesktopOrTablet ? 24 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isDesktopOrTablet ? 24 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ════════════ HEADER BAR ════════════
            _buildHeader(context, labels, gymName, gymLogoUrl, isDesktopOrTablet),

            // ════════════ SCROLLABLE RULES LIST ════════════
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isViewOnly && widget.existingAgreement != null)
                      _buildVerifiedBanner(widget.existingAgreement!),

                    // Rules Cards List
                    ...rules.asMap().entries.map((entry) {
                      final index = entry.key;
                      final rule = entry.value;
                      return _buildRuleCard(index + 1, rule);
                    }),

                    const SizedBox(height: 12),

                    // Checkboxes Section (Only if not view-only)
                    if (!widget.isViewOnly) ...[
                      const Divider(height: 32, thickness: 1),
                      _buildCheckboxes(labels),
                    ],
                  ],
                ),
              ),
            ),

            // ════════════ FOOTER ACTIONS ════════════
            _buildFooter(context, labels, vm),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: widget.isViewOnly,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: isDesktopOrTablet ? 24 : 12,
          vertical: 16,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: dialogContent,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(
    BuildContext context,
    Map<String, String> labels,
    String gymName,
    String? gymLogoUrl,
    bool isDesktopOrTablet,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.5),
                  child: (gymLogoUrl != null && gymLogoUrl.trim().isNotEmpty)
                      ? Image.network(
                          gymLogoUrl.trim(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildFallbackLogo(gymName),
                        )
                      : _buildFallbackLogo(gymName),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            gymName.isNotEmpty ? gymName.toUpperCase() : 'GYM RULES & POLICIES',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: const Color(0xFF94A3B8),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'OFFICIAL RULES',
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF34D399),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      labels['title'] ?? 'Gym Rules & Agreement',
                      style: GoogleFonts.inter(
                        fontSize: isDesktopOrTablet ? 17 : 14.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.isViewOnly)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  splashRadius: 20,
                ),
            ],
          ),
          if (labels['subtitle'] != null && labels['subtitle']!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              labels['subtitle']!,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: const Color(0xFF94A3B8),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),

          // ── Language Selector Segmented Row (Fully responsive for any phone width) ──
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: RuleLanguage.values.map((lang) {
                final isSelected = _selectedLanguage == lang;
                return Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedLanguage = lang;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(lang.flag, style: const TextStyle(fontSize: 13)),
                                const SizedBox(width: 5),
                                Text(
                                  lang.label,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
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
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // VERIFIED BADGE (VIEW-ONLY MODE)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildVerifiedBanner(MemberAgreementRecord record) {
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(record.agreedAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agreement Officially Verified & Signed',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF065F46),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Agreed by ${record.memberName} on $formattedDate (v${record.rulesVersion})',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // RULE CARD (MAIN + SUB-RULES)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildRuleCard(int index, GymRuleItem rule) {
    // Dynamic color accents based on rule type
    Color accentColor = const Color(0xFF2563EB);
    Color lightBg = const Color(0xFFEFF6FF);
    if (rule.id == 'injury' || rule.id == 'refund') {
      accentColor = const Color(0xFFDC2626);
      lightBg = const Color(0xFFFEF2F2);
    } else if (rule.id == 'transfer') {
      accentColor = const Color(0xFFD97706);
      lightBg = const Color(0xFFFFFBEB);
    } else if (rule.id == 'equipment') {
      accentColor = const Color(0xFF059669);
      lightBg = const Color(0xFFECFDF5);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Rule Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: lightBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(
                bottom: BorderSide(color: accentColor.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(rule.icon, color: accentColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$index. ${rule.mainRule}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sub-rules List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rule.subRules.map((sub) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 8),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          sub,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF334155),
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CONFIRMATION CHECKBOXES
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCheckboxes(Map<String, String> labels) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        children: [
          // Checkbox 1: Read rules
          InkWell(
            onTap: () {
              setState(() {
                _hasReadRules = !_hasReadRules;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _hasReadRules,
                      activeColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) {
                        setState(() => _hasReadRules = val ?? false);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      labels['chkRead'] ?? 'I have read and understood all rules.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Checkbox 2: Agree & abide
          InkWell(
            onTap: () {
              setState(() {
                _hasAgreedRules = !_hasAgreedRules;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _hasAgreedRules,
                      activeColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) {
                        setState(() => _hasAgreedRules = val ?? false);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      labels['chkAgree'] ?? 'I agree to strictly abide by all rules.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER ACTIONS
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildFooter(BuildContext context, Map<String, String> labels, MemberAppViewModel vm) {
    if (widget.isViewOnly) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(
              'Close',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
      );
    }

    final canSubmit = _hasReadRules && _hasAgreedRules && !_isSubmitting;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: canSubmit ? () => _handleAccept(context, vm, labels) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              labels['btnAccept'] ?? 'Accept Rules & Enter Gym',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isSubmitting ? null : () => _handleLogout(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                labels['btnLogout'] ?? 'Decline & Logout',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackLogo(String gymName) {
    final initial = gymName.trim().isNotEmpty ? gymName.trim().substring(0, 1).toUpperCase() : 'G';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HANDLERS
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _handleAccept(
    BuildContext context,
    MemberAppViewModel vm,
    Map<String, String> labels,
  ) async {
    setState(() => _isSubmitting = true);
    final success = await vm.submitRulesAgreement(
      languageCode: _selectedLanguage.code,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    labels['acceptedSuccess'] ?? 'Gym rules agreed successfully!',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      Navigator.of(context, rootNavigator: true).pop(true);
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final memberAppVm = Provider.of<MemberAppViewModel>(context, listen: false);
    await memberAppVm.logout();
    await authVm.logout();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }
}
