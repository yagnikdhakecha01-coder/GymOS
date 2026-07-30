import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class MemberShareStreak extends StatefulWidget {
  final int streakDays;
  final String muscleGroup;
  final String memberName;

  const MemberShareStreak({
    super.key,
    required this.streakDays,
    required this.muscleGroup,
    required this.memberName,
  });

  @override
  State<MemberShareStreak> createState() => _MemberShareStreakState();
}

class _MemberShareStreakState extends State<MemberShareStreak>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static void show(BuildContext context, {
    required int streakDays,
    required String muscleGroup,
    required String memberName,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberShareStreak(
        streakDays: streakDays,
        muscleGroup: muscleGroup,
        memberName: memberName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Share Your Streak',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),

                // Share Card Preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF7C3AED),
                        Color(0xFF5B21B6),
                        Color(0xFF4C1D95),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Decorative elements
                      Positioned(
                        right: -10,
                        top: -10,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -5,
                        bottom: 20,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                      ),
                      // Stars
                      Positioned(
                        right: 30,
                        top: 10,
                        child: Icon(Icons.star_rounded, color: Colors.white.withValues(alpha: 0.2), size: 16),
                      ),
                      Positioned(
                        right: 60,
                        top: 30,
                        child: Icon(Icons.star_rounded, color: Colors.white.withValues(alpha: 0.15), size: 12),
                      ),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fire + streak
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('🔥', style: TextStyle(fontSize: 36)),
                              const SizedBox(width: 8),
                              Text(
                                '${widget.streakDays}',
                                style: GoogleFonts.inter(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.0,
                                  letterSpacing: -2,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '🏋️‍♂️',
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Day Streak',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${widget.muscleGroup} Completed',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Keep going, stronger every day!',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Powered by GYMOS
                          Row(
                            children: [
                              Text(
                                'Powered by',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'GYMOS',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Share buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _shareButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Instagram',
                      color: const Color(0xFFE1306C),
                      bgColor: const Color(0xFFFCE4EC),
                      onTap: () {},
                    ),
                    _shareButton(
                      icon: Icons.chat_rounded,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      bgColor: const Color(0xFFE8F5E9),
                      onTap: () {},
                    ),
                    _shareButton(
                      icon: Icons.facebook_rounded,
                      label: 'Facebook',
                      color: const Color(0xFF1877F2),
                      bgColor: const Color(0xFFE3F2FD),
                      onTap: () {},
                    ),
                    _shareButton(
                      icon: Icons.more_horiz_rounded,
                      label: 'More',
                      color: AppTheme.textSecondary,
                      bgColor: AppTheme.surfaceGray,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shareButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
