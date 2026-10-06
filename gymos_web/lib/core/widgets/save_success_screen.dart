import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme.dart';

class SaveSuccessScreen extends StatefulWidget {
  final String title;
  final String message;

  const SaveSuccessScreen({
    super.key,
    required this.title,
    required this.message,
  });

  static void show(BuildContext context, {required String title, required String message}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaveSuccessScreen(title: title, message: message),
      ),
    );
  }

  @override
  State<SaveSuccessScreen> createState() => _SaveSuccessScreenState();
}

class _SaveSuccessScreenState extends State<SaveSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _checkAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _checkAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _checkAnim, curve: Curves.elasticOut);
    _checkAnim.forward();

    // Auto dismiss after 2 seconds
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _checkAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF16A34A),
                    size: 80,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
