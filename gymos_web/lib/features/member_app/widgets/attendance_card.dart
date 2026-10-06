import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class AttendanceCard extends StatefulWidget {
  final VoidCallback? onScanQR;

  const AttendanceCard({
    super.key,
    this.onScanQR,
  });

  @override
  State<AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<AttendanceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF7C3AED),
                Color(0xFF6D28D9),
                Color(0xFF5B21B6),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                right: -15,
                top: -15,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                left: -10,
                bottom: -10,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.asset(
                            'assets/images/member/qr_attendance.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mark Your Attendance',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Scan the QR code at the gym\nto check-in and maintain your streak',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.75),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Scan QR Code button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: widget.onScanQR,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_scanner_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Scan QR Code',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
