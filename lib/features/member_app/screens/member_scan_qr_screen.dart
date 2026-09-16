import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'member_check_in_success.dart';
import 'member_check_in_failure.dart';
import '../../../core/repository/gym_repository.dart';

class MemberScanQRScreen extends StatefulWidget {
  const MemberScanQRScreen({super.key});

  @override
  State<MemberScanQRScreen> createState() => _MemberScanQRScreenState();
}

class _MemberScanQRScreenState extends State<MemberScanQRScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _scanLineController;
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isScanCompleted = false;
  bool _scanCompletedSync = false;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }
      if (status.isGranted) {
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          await _scannerController.start();
        } catch (e) {
          print('Scanner controller start error: $e');
        }
      }
    } catch (e) {
      print('Camera permission error: $e');
    }
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<MemberAppViewModel>(context);
    
    // If already checked in today, show attendance summary instead of scanner
    if (vm.checkedInToday) {
      return _buildAlreadyCheckedInScreen(vm);
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Scan QR Code', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.qr_code_rounded, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const Spacer(flex: 1),

          // ═══════ QR SCANNER FRAME (Image 6) ═══════
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    // Real Camera Preview
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: (capture) async {
                        if (_scanCompletedSync) return;
                        final List<Barcode> barcodes = capture.barcodes;
                        if (barcodes.isNotEmpty) {
                          final String? codeValue = barcodes.first.rawValue;
                          if (codeValue != null) {
                            _scanCompletedSync = true;
                            setState(() {
                              _isScanCompleted = true;
                            });
                            final vm = Provider.of<MemberAppViewModel>(context, listen: false);
                            final result = await vm.markCheckIn(codeValue);
                            if (mounted) {
                              if (result['success'] == true) {
                                final bool alreadyMarked = result['already_marked'] == true;
                                try {
                                  final repo = Provider.of<GymRepository>(context, listen: false);
                                  await repo.fetchAttendanceLogsFromSupabase();
                                } catch (e) {
                                  print('Error reloading attendance calendar logs: $e');
                                }
                                
                                if (mounted) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MemberCheckInSuccess(
                                        alreadyMarked: alreadyMarked,
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MemberCheckInFailure(
                                      errorMessage: result['reason'] ?? result['message'] ?? 'Attendance verification failed',
                                    ),
                                  ),
                                );
                                _scanCompletedSync = false;
                                if (mounted) {
                                  setState(() {
                                    _isScanCompleted = false;
                                  });
                                }
                              }
                            }
                          }
                        }
                      },
                      errorBuilder: (context, error, child) {
                        return Container(
                          color: Colors.black.withValues(alpha: 0.85),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 40),
                              const SizedBox(height: 12),
                              Text(
                                'Webcam/Camera not available or permission denied.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    // Corner decorations (purple scan frame corners)
                    ..._buildCorners(),
                    // Scanning line animation
                    AnimatedBuilder(
                      animation: _scanLineController,
                      builder: (context, child) {
                        return Positioned(
                          top: 20 + (_scanLineController.value * 220),
                          left: 20,
                          right: 20,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, AppTheme.primary.withValues(alpha: 0.8), Colors.transparent],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_isScanCompleted)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ═══════ INSTRUCTION TEXT (Image 6 bottom) ═══════
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Point your camera at the\nQR code to check-in',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure the QR code is clearly visible',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 24),

          // ═══════ HELPFUL QR SCANNING TIP ═══════
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Attendance is verified securely through live QR code scanning.',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }

  List<Widget> _buildCorners() {
    const cornerSize = 28.0;
    const thickness = 3.0;
    const color = AppTheme.primary;

    return [
      // Top-left
      Positioned(top: 0, left: 0, child: _corner(color, cornerSize, thickness, true, true)),
      // Top-right
      Positioned(top: 0, right: 0, child: _corner(color, cornerSize, thickness, true, false)),
      // Bottom-left
      Positioned(bottom: 0, left: 0, child: _corner(color, cornerSize, thickness, false, true)),
      // Bottom-right
      Positioned(bottom: 0, right: 0, child: _corner(color, cornerSize, thickness, false, false)),
    ];
  }

  Widget _corner(Color color, double size, double thickness, bool isTop, bool isLeft) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(color: color, thickness: thickness, isTop: isTop, isLeft: isLeft),
      ),
    );
  }

  Widget _buildAlreadyCheckedInScreen(MemberAppViewModel vm) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text('Attendance', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEFF6FF),
                ),
                child: const Center(
                  child: Icon(Icons.info_outline_rounded, color: Colors.blue, size: 60),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Your Attendance is Already Done!',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                "You're all set for today.",
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Attendance Time', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                        Text(
                          vm.checkInTime.isNotEmpty ? vm.checkInTime : '--:-- --',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(height: 0.5, color: AppTheme.border),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Date', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                        Text(
                          vm.checkInDate.isNotEmpty ? vm.checkInDate : '--',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(height: 0.5, color: AppTheme.border),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Status', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Present', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.success)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool isTop;
  final bool isLeft;

  _CornerPainter({required this.color, required this.thickness, required this.isTop, required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    if (isTop && isLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (isTop && !isLeft) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!isTop && isLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
