import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/admin_theme.dart';

class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AdminTheme.isDark(context);
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
      highlightColor: isDark ? const Color(0xFF475569) : const Color(0xFFF3F4F6),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AdminTheme.spacingXl),
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonLoader(width: 40, height: 40, borderRadius: 10),
              Spacer(),
              SkeletonLoader(width: 60, height: 20),
            ],
          ),
          SizedBox(height: 16),
          SkeletonLoader(width: 100, height: 28),
          SizedBox(height: 8),
          SkeletonLoader(width: 140, height: 14),
        ],
      ),
    );
  }
}

class SkeletonTable extends StatelessWidget {
  final int rows;

  const SkeletonTable({super.key, this.rows = 5});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AdminTheme.borderColor(context)),
              ),
            ),
            child: const Row(
              children: [
                Expanded(child: SkeletonLoader(height: 16)),
                SizedBox(width: 16),
                Expanded(child: SkeletonLoader(height: 16)),
                SizedBox(width: 16),
                Expanded(child: SkeletonLoader(height: 16)),
                SizedBox(width: 16),
                Expanded(child: SkeletonLoader(height: 16)),
              ],
            ),
          ),
          // Rows
          ...List.generate(rows, (i) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: i < rows - 1
                  ? Border(bottom: BorderSide(color: AdminTheme.borderColor(context)))
                  : null,
            ),
            child: const Row(
              children: [
                Expanded(child: SkeletonLoader(height: 14)),
                SizedBox(width: 16),
                Expanded(child: SkeletonLoader(height: 14)),
                SizedBox(width: 16),
                Expanded(child: SkeletonLoader(height: 14)),
                SizedBox(width: 16),
                Expanded(child: SkeletonLoader(height: 14)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
