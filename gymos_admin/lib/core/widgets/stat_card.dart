import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/admin_theme.dart';

class AdminStatCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color? iconBgColor;
  final String value;
  final String label;
  final String? change;
  final bool isPositiveChange;
  final VoidCallback? onTap;

  const AdminStatCard({
    super.key,
    required this.icon,
    required this.iconColor,
    this.iconBgColor,
    required this.value,
    required this.label,
    this.change,
    this.isPositiveChange = true,
    this.onTap,
  });

  @override
  State<AdminStatCard> createState() => _AdminStatCardState();
}

class _AdminStatCardState extends State<AdminStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AdminTheme.animFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AdminTheme.isDark(context);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AdminTheme.animNormal,
            padding: const EdgeInsets.all(AdminTheme.spacingXl),
            decoration: BoxDecoration(
              color: AdminTheme.cardColor(context),
              borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
              border: Border.all(
                color: _isHovered
                    ? AdminTheme.primary.withValues(alpha: 0.3)
                    : AdminTheme.borderColor(context),
                width: 1,
              ),
              boxShadow: _isHovered ? AdminTheme.cardShadow : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (widget.iconBgColor ?? widget.iconColor).withValues(alpha: isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(AdminTheme.radiusMd),
                      ),
                      child: Icon(widget.icon, color: widget.iconColor, size: 20),
                    ),
                    const Spacer(),
                    if (widget.change != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.isPositiveChange
                              ? AdminTheme.successLight.withValues(alpha: isDark ? 0.2 : 1.0)
                              : AdminTheme.dangerLight.withValues(alpha: isDark ? 0.2 : 1.0),
                          borderRadius: BorderRadius.circular(AdminTheme.radiusXs),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isPositiveChange ? Icons.trending_up : Icons.trending_down,
                              size: 12,
                              color: widget.isPositiveChange ? AdminTheme.success : AdminTheme.danger,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              widget.change!,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: widget.isPositiveChange ? AdminTheme.success : AdminTheme.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.value,
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AdminTheme.textColor(context),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AdminTheme.secondaryTextColor(context),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
