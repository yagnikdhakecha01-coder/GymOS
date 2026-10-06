import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../theme/responsive.dart';

class CustomCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? borderRadius;
  final Border? border;

  const CustomCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: padding ?? EdgeInsets.all(context.scaleSpacing(AppTheme.spacingLg)),
      decoration: BoxDecoration(
        color: color ?? AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(borderRadius ?? AppTheme.radiusCard),
        border: border ?? Border.all(color: AppTheme.border, width: 1),
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius ?? AppTheme.radiusCard),
          splashColor: AppTheme.primary.withValues(alpha: 0.05),
          highlightColor: AppTheme.primary.withValues(alpha: 0.02),
          child: content,
        ),
      );
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: content,
    );
  }
}
