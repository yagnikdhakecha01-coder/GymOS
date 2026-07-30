import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class StreakHeroCard extends StatefulWidget {
  final int currentStreak;
  final List<bool> weekAttendance;
  final List<String> weekDays;
  final List<int> weekDates;

  const StreakHeroCard({
    super.key,
    required this.currentStreak,
    required this.weekAttendance,
    required this.weekDays,
    required this.weekDates,
  });

  @override
  State<StreakHeroCard> createState() => _StreakHeroCardState();
}

class _StreakHeroCardState extends State<StreakHeroCard> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
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
                color: AppTheme.primary.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Background decorative circles
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: 40,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Fire icon + text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Fire emoji / icon
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Center(
                                      child: Text('🔥', style: TextStyle(fontSize: 20)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Current Streak',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '${widget.currentStreak} Days',
                                style: GoogleFonts.inter(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -1,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Don't break your streak today!",
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Illustration
                        SizedBox(
                          width: 90,
                          height: 100,
                          child: Image.asset(
                            'assets/images/member/streak_hero_bg.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.fitness_center_rounded,
                                color: Colors.white.withValues(alpha: 0.4),
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Week attendance circles
                    _buildWeekRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(widget.weekDays.length, (index) {
        final attended = widget.weekAttendance[index];
        final isToday = index == widget.weekDays.length - 1;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 400 + (index * 80)),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: child,
            );
          },
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday
                      ? Colors.white
                      : attended
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                  border: isToday
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(alpha: attended ? 0.4 : 0.15),
                          width: 1.5,
                        ),
                ),
                child: Center(
                  child: isToday
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.weekDates[index]}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        )
                      : attended
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                          : Text(
                              '${widget.weekDates[index]}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.weekDays[index],
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday ? Colors.white : Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
