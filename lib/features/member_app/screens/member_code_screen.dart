import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../../core/navigation/app_router.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../authentication/role_selection_screen.dart';
import '../../staff/portal/staff_shell.dart';
import 'member_shell.dart';
import '../member_app_viewmodel.dart';

class MemberCodeScreen extends StatefulWidget {
  const MemberCodeScreen({super.key});

  @override
  State<MemberCodeScreen> createState() => _MemberCodeScreenState();
}

class _MemberCodeScreenState extends State<MemberCodeScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  final _mobileController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _mobileController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim();
    final mobile = _mobileController.text.trim();

    if (code.isEmpty) {
      setState(() => _errorText = 'Please enter your invitation code');
      return;
    }
    if (mobile.isEmpty) {
      setState(() => _errorText = 'Please enter your mobile number');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final result = await authVm.submitInvitationCode(
      code: code,
      mobileNumber: mobile,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result['success'] == true) {
        Widget targetScreen;
        final roleStr = result['role'] as String? ?? 'member';
        if (roleStr == 'staff') {
          targetScreen = const StaffShell();
        } else {
          try {
            await Provider.of<MemberAppViewModel>(context, listen: false).loadMemberDataFromSupabase();
          } catch (e) {
            debugPrint('loadMemberDataFromSupabase warning on code redeem: $e');
          }
          targetScreen = const MemberShell();
        }

        Navigator.pushAndRemoveUntil(
          context,
          AppRouter.scaleRoute(targetScreen),
          (route) => false,
        );
      } else {
        setState(() => _errorText = result['error'] ?? 'Verification failed.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        await authVm.logout();
        if (context.mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            AppRouter.scaleRoute(const RoleSelectionScreen()),
            (route) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () async {
            final authVm = Provider.of<AuthViewModel>(context, listen: false);
            await authVm.logout();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                AppRouter.scaleRoute(const RoleSelectionScreen()),
                (route) => false,
              );
            }
          },
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // ── Title (matching reference image 3) ──
                  Text(
                    'Enter Gym Code',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ask your gym owner for the code',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Illustration Placeholder ──
                  Container(
                    width: 200,
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/images/member/gym_code_illustration.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.groups_rounded,
                              color: AppTheme.primary.withValues(alpha: 0.5),
                              size: 56,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'gym_code_illustration.png',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ── Invitation Code Input ──
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.none,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Enter 8-character code here',
                      errorText: _errorText,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Mobile Number Input ──
                  TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Enter Registered Mobile Number',
                      contentPadding: EdgeInsets.symmetric(vertical: 16),
                      prefixIcon: Icon(Icons.phone_iphone_outlined, size: 20),
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Continue Button (matching reference) ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleVerify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'Continue',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Help link ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Need help? ',
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                      ),
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: Text('Member Invitation Code', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                              content: Text(
                                'Ask your Gym Receptionist or Trainer for your 6-digit invitation code registered with your gym.',
                                style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textSecondary),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text('Got it', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Text(
                          'Contact Support',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
