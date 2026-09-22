import 'package:flutter/material.dart';

/// A lightweight, 60fps pure-Flutter Shimmering effect widget.
/// Zero external package dependencies, highly performant on all Android & iOS devices.
class SkeletonShimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;

  const SkeletonShimmer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFE2E8F0),
    this.highlightColor = const Color(0xFFF8FAFC),
    this.duration = const Duration(milliseconds: 1400),
  });

  /// Dark mode shimmer constructor
  const SkeletonShimmer.dark({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF1E293B),
    this.highlightColor = const Color(0xFF334155),
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final double progress = _controller.value;
            final double width = bounds.width;
            final double dx = (width * 2) * progress - width;

            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(dx: dx),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double dx;
  const _SlidingGradientTransform({required this.dx});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0.0, 0.0);
  }
}

/// A versatile skeleton rectangle/box placeholder.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final Color color;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.margin,
    this.color = const Color(0xFFE2E8F0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// A circular skeleton placeholder (for avatars, icons, badges).
class SkeletonCircle extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry? margin;
  final Color color;

  const SkeletonCircle({
    super.key,
    required this.size,
    this.margin,
    this.color = const Color(0xFFE2E8F0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Responsive Skeleton Loader tailored for Member Dashboard.
/// Adapts gracefully to all mobile screen sizes (small, standard, large, foldables).
class DashboardSkeletonLoader extends StatelessWidget {
  const DashboardSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return SkeletonShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header: Avatar + Greeting + Badge
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: screenWidth * 0.45, height: 22, borderRadius: 6),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SkeletonBox(width: 90, height: 14, borderRadius: 4),
                          const SizedBox(width: 8),
                          SkeletonBox(width: 50, height: 16, borderRadius: 4),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SkeletonBox(width: 120, height: 12, borderRadius: 4),
                    ],
                  ),
                ),
                const SkeletonCircle(size: 40),
                const SizedBox(width: 10),
                const SkeletonCircle(size: 40),
              ],
            ),

            const SizedBox(height: 24),

            // 2. Large Main Card (Membership Status / QR Banner)
            SkeletonBox(
              width: double.infinity,
              height: isTablet ? 180 : 140,
              borderRadius: 20,
            ),

            const SizedBox(height: 20),

            // 3. Section Title Placeholder
            SkeletonBox(width: 140, height: 16, borderRadius: 4),

            const SizedBox(height: 14),

            // 4. Grid of Quick Actions (4 cards)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isTablet ? 4 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (context, index) {
                return const SkeletonBox(
                  borderRadius: 16,
                );
              },
            ),

            const SizedBox(height: 24),

            // 5. Section 2: Attendance / Workout Highlights
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBox(width: 130, height: 16, borderRadius: 4),
                SkeletonBox(width: 60, height: 14, borderRadius: 4),
              ],
            ),

            const SizedBox(height: 12),

            // 6. Recent Activity List Items
            ...List.generate(3, (index) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const SkeletonCircle(size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: screenWidth * 0.4, height: 14, borderRadius: 4),
                          const SizedBox(height: 6),
                          SkeletonBox(width: screenWidth * 0.25, height: 11, borderRadius: 4),
                        ],
                      ),
                    ),
                    const SkeletonBox(width: 60, height: 20, borderRadius: 6),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Responsive Skeleton Loader for Rules and Agreement screens.
class RulesSkeletonLoader extends StatelessWidget {
  const RulesSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SkeletonCircle(size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SkeletonBox(width: double.infinity, height: 16, borderRadius: 4),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 12, borderRadius: 4),
                const SizedBox(height: 6),
                SkeletonBox(width: 220, height: 12, borderRadius: 4),
              ],
            ),
          );
        },
      ),
    );
  }
}
