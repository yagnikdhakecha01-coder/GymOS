import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

/// Rest timer widget — counts down from [seconds].
/// Plays a haptic alert + callback when done.
class RestTimerWidget extends StatefulWidget {
  final int seconds;
  final VoidCallback? onFinished;
  final VoidCallback? onSkip;

  const RestTimerWidget({
    super.key,
    this.seconds = 90,
    this.onFinished,
    this.onSkip,
  });

  @override
  State<RestTimerWidget> createState() => RestTimerWidgetState();
}

class RestTimerWidgetState extends State<RestTimerWidget>
    with TickerProviderStateMixin {
  late int _remaining;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  bool _isDone = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) {
          _remaining--;
        } else {
          _isDone = true;
          _timer?.cancel();
          HapticFeedback.heavyImpact();
          widget.onFinished?.call();
        }
      });
    });
  }

  void addTime(int seconds) {
    setState(() => _remaining += seconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _format(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor {
    if (_isDone) return AppTheme.success;
    if (_remaining <= 10) return AppTheme.danger;
    if (_remaining <= 30) return AppTheme.warning;
    return AppTheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _timerColor.withValues(alpha: 0.3)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isDone ? '✅ Ready!' : '⏱️ Rest',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (!_isDone)
                GestureDetector(
                  onTap: widget.onSkip,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGray,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Skip',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Circular progress + timer display ──
          ScaleTransition(
            scale: _pulseAnim,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: _isDone
                        ? 1.0
                        : 1.0 - (_remaining / widget.seconds).clamp(0.0, 1.0),
                    strokeWidth: 6,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_timerColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isDone ? '00:00' : _format(_remaining),
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _timerColor,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── +15s / +30s buttons ──
          if (!_isDone)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _timeButton('+15s', () => addTime(15)),
                const SizedBox(width: 12),
                _timeButton('+30s', () => addTime(30)),
              ],
            ),

          if (_isDone)
            Text(
              'Time to crush the next set! 💪',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }
}
