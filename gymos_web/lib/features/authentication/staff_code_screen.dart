import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import 'package:provider/provider.dart';
import '../../core/navigation/app_router.dart';
import '../staff/portal/staff_shell.dart';
import '../receptionist/portal/receptionist_shell.dart';
import 'auth_viewmodel.dart';

class StaffCodeScreen extends StatefulWidget {
  const StaffCodeScreen({super.key});

  @override
  State<StaffCodeScreen> createState() => _StaffCodeScreenState();
}

class _StaffCodeScreenState extends State<StaffCodeScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
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
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorText = 'Please enter your staff gym code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() => _isLoading = false);
      if (code == '123456' || code == 'STF001') {
        final authVm = Provider.of<AuthViewModel>(context, listen: false);
        await authVm.loadCurrentProfile();
        Widget target = const StaffShell();
        final staffRole = authVm.staffRecord?.role.toLowerCase() ?? '';
        if (staffRole.contains('reception')) {
          target = const ReceptionistShell();
        }
        Navigator.pushAndRemoveUntil(
          context,
          AppRouter.scaleRoute(target),
          (route) => false,
        );
      } else {
        setState(() => _errorText = 'Invalid staff code. Use STF001 or 123456.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
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

                  Text(
                    'Enter Staff Access Code',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your assigned staff code to activate this portal.\n(Use STF001 or 123456 to test)',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  Container(
                    width: 200,
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.badge_rounded,
                            color: AppTheme.primary.withOpacity(0.5),
                            size: 56,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Staff Verification',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                      UpperCaseTextFormatter(),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Enter code here',
                      errorText: _errorText,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 28),

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
                              title: Text('Staff Invitation Code', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                              content: Text(
                                'Please contact your Gym Owner or Manager. They can generate your unique staff invitation code from their GymOS dashboard.',
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
                          'Contact Admin',
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
