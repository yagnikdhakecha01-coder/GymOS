import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class MemberCheckInFailure extends StatefulWidget {
  final String errorMessage;
  final VoidCallback? onDone;

  const MemberCheckInFailure({
    super.key,
    required this.errorMessage,
    this.onDone,
  });

  @override
  State<MemberCheckInFailure> createState() => _MemberCheckInFailureState();
}

class _MemberCheckInFailureState extends State<MemberCheckInFailure>
    with TickerProviderStateMixin {
  late AnimationController _failController;
  late Animation<double> _failScaleAnim;

  @override
  void initState() {
    super.initState();
    _failController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _failScaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _failController, curve: Curves.elasticOut),
    );
    _failController.forward();
  }

  @override
  void dispose() {
    _failController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Attendance Failed',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // ═══════ RED CROSS CIRCLE ═══════
              ScaleTransition(
                scale: _failScaleAnim,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFEE2E2),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.cancel_rounded,
                      color: AppTheme.danger,
                      size: 90,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Header Title
              Text(
                'Attendance Failed',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Please verify your credentials or status.",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // ═══════ ERROR DETAILS CARD ═══════
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      widget.errorMessage,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ═══════ TRY AGAIN BUTTON ═══════
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: widget.onDone ?? () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'OK, Try Again',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
