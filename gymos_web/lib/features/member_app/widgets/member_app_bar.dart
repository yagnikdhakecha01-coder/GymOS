import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class MemberAppBar extends StatelessWidget {
  final String greeting;
  final String memberName;
  final String gymName;
  final int notificationCount;
  final VoidCallback? onMenuTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;

  const MemberAppBar({
    super.key,
    required this.greeting,
    required this.memberName,
    required this.gymName,
    this.notificationCount = 0,
    this.onMenuTap,
    this.onNotificationTap,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${memberName.split(' ').first} 👋',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Keep pushing, keep growing!',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Notification Bell
          GestureDetector(
            onTap: onNotificationTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Icon(Icons.notifications_outlined, color: AppTheme.textPrimary, size: 22),
                ),
                if (notificationCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          notificationCount > 9 ? '9+' : '$notificationCount',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Profile Avatar
          GestureDetector(
            onTap: onProfileTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
                image: const DecorationImage(
                  image: AssetImage('assets/images/member/avatar_default.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/member/avatar_default.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppTheme.primaryLight,
                    child: const Icon(Icons.person_rounded, color: AppTheme.primary, size: 24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
