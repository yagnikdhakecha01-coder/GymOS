import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class AchievementsSection extends StatelessWidget {
  final List<Map<String, dynamic>> achievements;
  final VoidCallback? onViewAll;

  const AchievementsSection({
    super.key,
    required this.achievements,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Achievements',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  'View All',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Achievement items
          ...achievements.asMap().entries.map((entry) {
            final index = entry.key;
            final achievement = entry.value;
            final isLast = index == achievements.length - 1;

            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 400 + (index * 100)),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(20 * (1 - value), 0),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  _AchievementItem(
                    title: achievement['title'] as String,
                    description: achievement['description'] as String,
                    icon: achievement['icon'] as IconData,
                    color: achievement['color'] as Color,
                    unlocked: achievement['unlocked'] as bool,
                  ),
                  if (!isLast) ...[
                    const SizedBox(height: 4),
                    const Divider(color: AppTheme.border, height: 1),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AchievementItem extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool unlocked;

  const _AchievementItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Icon badge
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: unlocked ? color.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: unlocked ? color : Colors.grey.withValues(alpha: 0.4),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: unlocked ? AppTheme.textPrimary : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (unlocked)
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.successLight,
              ),
              child: const Icon(Icons.check_rounded, color: AppTheme.success, size: 16),
            ),
        ],
      ),
    );
  }
}
