import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import 'attendance_viewmodel.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'owner_success_screen.dart';

class OwnerQRScannerScreen extends StatefulWidget {
  final bool isCheckIn;
  const OwnerQRScannerScreen({super.key, required this.isCheckIn});

  @override
  State<OwnerQRScannerScreen> createState() => _OwnerQRScannerScreenState();
}

class _OwnerQRScannerScreenState extends State<OwnerQRScannerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scanLineAnim;
  final MobileScannerController _scannerController = MobileScannerController();
  bool _flashOn = false;
  bool _isScanCompleted = false;
  bool _showScanner = false;

  // Verification overlay state
  String? _verificationState;
  String? _verificationErrorMessage;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }
      if (status.isGranted) {
        // Small delay to let camera hardware initialize in release builds
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          await _scannerController.start();
        } catch (e) {
          print('Scanner controller start error: $e');
        }
      }
    } catch (e) {
      print('Camera permission check error: $e');
    }
    if (mounted) {
      setState(() => _showScanner = true);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onQRDetected(String code) async {
    final vm = Provider.of<AttendanceViewModel>(context, listen: false);
    final trimmedCode = code.trim();

    // DEBUG: Immediately show what was scanned
    print('[SCANNER DEBUG] Raw scanned value: "$code"');
    print('[SCANNER DEBUG] Trimmed value: "$trimmedCode"');
    print('[SCANNER DEBUG] Length: ${trimmedCode.length}');

    // Check if it's a display verification token (64-char hex string)
    final isVerificationToken = RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmedCode);
    print('[SCANNER DEBUG] Is 64-char hex token? $isVerificationToken');

    if (isVerificationToken) {
      setState(() {
        _verificationState = 'verifying';
        _verificationErrorMessage = null;
      });

      try {
        print('[SCANNER DEBUG] Calling verifyDisplay RPC...');
        await vm.verifyDisplay(trimmedCode);
        print('[SCANNER DEBUG] verifyDisplay SUCCESS');
        
        if (mounted) {
          setState(() {
            _verificationState = 'success';
          });
          
          // Wait 2 seconds to show success screen, then close
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context);
          }
        }
      } catch (e) {
        print('[SCANNER DEBUG] verifyDisplay FAILED: $e');
        if (mounted) {
          setState(() {
            _verificationState = 'error';
            _verificationErrorMessage = e.toString().replaceAll('Exception:', '').trim();
          });
        }
      }
      return;
    }

    // Show instant feedback that scan happened (only for non-verification codes)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scanned: ${trimmedCode.substring(0, trimmedCode.length > 20 ? 20 : trimmedCode.length)}... (${trimmedCode.length} chars)'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Not a verification token - try attendance marking
    print('[SCANNER DEBUG] Not a verification token, trying attendance...');

    // WiFi verification (Only for attendance marking)
    if (!vm.isGymWiFiConnected) {
      print('[SCANNER DEBUG] WiFi not connected, showing error');
      setState(() {
        _isScanCompleted = false;
      });
      _showWiFiError();
      return;
    }

    final method = vm.isDynamicQrEnabled ? 'Dynamic QR' : 'Static QR';

    final result = await vm.markAttendance(
      token: trimmedCode,
      method: method,
    );

    if (mounted) {
      if (result['success'] == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OwnerAttendanceSuccessScreen(
              name: result['user_name'] ?? result['userName'] ?? 'User',
              role: result['user_type'] ?? result['userType'] ?? 'Member',
              time: result['action'] == 'Check Out' ? (result['check_out'] ?? result['checkOutTime'] ?? '') : (result['check_in'] ?? result['checkInTime'] ?? ''),
              date: result['attendance_date'] ?? DateFormat('dd-MM-yyyy').format(DateTime.now()),
              status: result['status'] ?? 'Present',
              isCheckIn: result['action'] != 'Check Out',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['reason'] ?? 'Verification failed'),
            backgroundColor: AppTheme.danger,
          ),
        );
        setState(() {
          _isScanCompleted = false;
        });
      }
    }
  }

  void _showWiFiError() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.dangerLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded, color: AppTheme.danger, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Gym WiFi Not Connected',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Please connect to the registered Gym WiFi to mark attendance.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  final vm = Provider.of<AttendanceViewModel>(context, listen: false);
                  vm.setCurrentConnectedSSID(vm.savedGymWiFiSSID);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Connected to ${vm.savedGymWiFiSSID}'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Open WiFi Settings', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualScanDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Simulate QR Scan', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Enter Display ID or QR Token',
            labelStyle: GoogleFonts.inter(fontSize: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _onQRDetected(controller.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Submit', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final frameSize = MediaQuery.of(context).size.width * 0.65;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Simulated dark gym background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF2D1B4E).withOpacity(0.95),
                  const Color(0xFF1A1A2E),
                ],
              ),
            ),
          ),

          // Subtle gym pattern overlay
          Opacity(
            opacity: 0.08,
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage('https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Top Bar ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'Scan QR Code',
                        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      IconButton(
                        icon: Icon(
                          _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          color: _flashOn ? Colors.amber : Colors.white70,
                          size: 22,
                        ),
                        onPressed: () {
                          _scannerController.toggleTorch();
                          setState(() => _flashOn = !_flashOn);
                        },
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // ── Scanner Frame ──
                SizedBox(
                  width: frameSize,
                  height: frameSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        // Real Camera Preview
                        if (_showScanner)
                          MobileScanner(
                            controller: _scannerController,
                            onDetect: (capture) async {
                              if (_isScanCompleted) return;
                              final List<Barcode> barcodes = capture.barcodes;
                              if (barcodes.isNotEmpty) {
                                final String? codeValue = barcodes.first.rawValue;
                                if (codeValue != null) {
                                  setState(() {
                                    _isScanCompleted = true;
                                  });
                                  await _onQRDetected(codeValue);
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
                                      'Camera not available or permission denied.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                                    ),
                                    const SizedBox(height: 14),
                                    TextButton(
                                      onPressed: () => _showManualScanDialog(context),
                                      child: Text(
                                        'Simulate Scan (Type/Paste Code)',
                                        style: TextStyle(
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        else
                          Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(color: AppTheme.primary),
                            ),
                          ),
                        // Corner brackets
                        _Corner(alignment: Alignment.topLeft),
                        _Corner(alignment: Alignment.topRight),
                        _Corner(alignment: Alignment.bottomLeft),
                        _Corner(alignment: Alignment.bottomRight),

                        // Animated green scan line
                        AnimatedBuilder(
                          animation: _scanLineAnim,
                          builder: (context, child) {
                            return Positioned(
                              top: _scanLineAnim.value * (frameSize - 4),
                              left: 16,
                              right: 16,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.green.withOpacity(0.0),
                                      Colors.green.withOpacity(0.8),
                                      Colors.green,
                                      Colors.green.withOpacity(0.8),
                                      Colors.green.withOpacity(0.0),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.4),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // ── Instructions ──
                Text(
                  'Point your camera at the\nQR code displayed in the gym',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                // Camera icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white54, size: 28),
                ),
                const SizedBox(height: 16),

                Text(
                  'Make sure the QR code is\nclearly visible',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white38, height: 1.4),
                ),

                const Spacer(),
              ],
            ),
          ),
          if (_verificationState != null)
            _buildVerificationOverlay(),
        ],
      ),
    );
  }

  Widget _buildVerificationOverlay() {
    final isVerifying = _verificationState == 'verifying';
    final isSuccess = _verificationState == 'success';
    final isError = _verificationState == 'error';

    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Circular Indicator/Animation
              if (isVerifying) ...[
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        backgroundColor: Colors.white10,
                      ),
                    ),
                    const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Verifying Display...',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connecting to the display screen',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
              ] else if (isSuccess) ...[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, val, child) {
                    return Transform.scale(
                      scale: val,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.done_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'Succeeded!',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Display screen verified successfully',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white54,
                  ),
                ),
              ] else if (isError) ...[
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, val, child) {
                    return Transform.scale(
                      scale: val,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          color: AppTheme.danger,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'Verification Failed',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Text(
                    _verificationErrorMessage ?? 'Unknown error occurred.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.dangerLight,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _verificationState = null;
                        _isScanCompleted = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                    ),
                    child: Text(
                      'Try Again',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Corner Bracket Widget ──
class _Corner extends StatelessWidget {
  final Alignment alignment;
  const _Corner({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final isTop = alignment == Alignment.topLeft || alignment == Alignment.topRight;
    final isLeft = alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;

    return Align(
      alignment: alignment,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? const BorderSide(color: Colors.white, width: 3.5) : BorderSide.none,
            bottom: !isTop ? const BorderSide(color: Colors.white, width: 3.5) : BorderSide.none,
            left: isLeft ? const BorderSide(color: Colors.white, width: 3.5) : BorderSide.none,
            right: !isLeft ? const BorderSide(color: Colors.white, width: 3.5) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
