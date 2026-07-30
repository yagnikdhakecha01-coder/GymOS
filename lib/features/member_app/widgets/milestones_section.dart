import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class MilestonesSection extends StatelessWidget {
  final int currentProgress;
  final int nextTarget;

  const MilestonesSection({
    super.key,
    required this.currentProgress,
    required this.nextTarget,
  });

  @override
  Widget build(BuildContext context) {
    final milestones = [
      {'days': 7, 'label': 'Bronze', 'color': const Color(0xFFCD7F32)},
      {'days': 14, 'label': 'Silver', 'color': const Color(0xFFC0C0C0)},
      {'days': 30, 'label': 'Gold', 'color': const Color(0xFFFFD700)},
      {'days': 60, 'label': 'Platinum', 'color': const Color(0xFFE5E4E2)},
      {'days': 100, 'label': 'Diamond', 'color': const Color(0xFFB9F2FF)},
    ];

    final daysToNext = nextTarget - currentProgress;
    final progressFraction = currentProgress / nextTarget;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Streak Milestones',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 18),

          // Milestone badges row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: milestones.asMap().entries.map((entry) {
              final index = entry.key;
              final milestone = entry.value;
              final days = milestone['days'] as int;
              final label = milestone['label'] as String;
              final color = milestone['color'] as Color;
              final achieved = currentProgress >= days;

              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 500 + (index * 100)),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Column(
                  children: [
                    // Trophy badge
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: achieved
                            ? color.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: achieved
                            ? Border.all(color: color.withValues(alpha: 0.4), width: 1.5)
                            : null,
                      ),
                      child: Icon(
                        Icons.emoji_events_rounded,
                        color: achieved ? color : Colors.grey.withValues(alpha: 0.3),
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$days Days',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: achieved ? AppTheme.textPrimary : AppTheme.textMuted,
                      ),
                    ),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Next milestone info
          Row(
            children: [
              Text(
                '🔥',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 6),
              Text(
                'Next Milestone',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '$daysToNext Days to go!',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$currentProgress / $nextTarget Days',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress bar
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: progressFraction.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Container(
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
