import 'package:flutter/material.dart';

/// Breakpoints for screen scaling categories
class AppBreakpoints {
  static const double mobileSmall = 360.0;
  static const double mobileMedium = 480.0;
  static const double tablet = 768.0;
  static const double desktop = 1024.0;
}

/// Centralized responsive layout constants and helper methods
class Responsive {
  /// Check if device screen width matches a tablet or larger device
  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= AppBreakpoints.tablet;
  }

  /// Check if device screen width matches a small mobile phone
  static bool isSmallMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < AppBreakpoints.mobileSmall;
  }

  /// Check if device orientation is set to Landscape
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Return dynamic size relative to active device screen width percentage
  static double widthPercent(BuildContext context, double percent) {
    return MediaQuery.of(context).size.width * (percent / 100);
  }

  /// Return dynamic size relative to active device screen height percentage
  static double heightPercent(BuildContext context, double percent) {
    return MediaQuery.of(context).size.height * (percent / 100);
  }

  /// Calculate layout scaling factor based on device category standards
  static double scaleFactor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= AppBreakpoints.tablet) {
      return 1.2; // Scale moderately for tablet surfaces
    } else if (width < AppBreakpoints.mobileSmall) {
      return 0.85; // Scale down for extremely tiny screens
    }
    return 1.0;
  }

  /// Scaled font size based on dynamic layout checks
  static double font(BuildContext context, double baseSize) {
    return baseSize * scaleFactor(context);
  }

  /// Scaled layout spacing based on dynamic layout checks
  static double spacing(BuildContext context, double baseSpacing) {
    return baseSpacing * scaleFactor(context);
  }

  /// Choose layout value dynamically matching screen category
  static T selectValue<T>({
    required BuildContext context,
    required T mobile,
    T? tablet,
    T? smallMobile,
  }) {
    final width = MediaQuery.of(context).size.width;
    if (width >= AppBreakpoints.tablet && tablet != null) {
      return tablet;
    } else if (width < AppBreakpoints.mobileSmall && smallMobile != null) {
      return smallMobile;
    }
    return mobile;
  }
}

/// Helper extension on BuildContext for quick inline responsive mappings
extension ResponsiveContext on BuildContext {
  bool get isTablet => Responsive.isTablet(this);
  bool get isSmallMobile => Responsive.isSmallMobile(this);
  bool get isLandscape => Responsive.isLandscape(this);
  
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  
  double widthPercent(double percent) => Responsive.widthPercent(this, percent);
  double heightPercent(double percent) => Responsive.heightPercent(this, percent);
  
  double scale(double value) => value * Responsive.scaleFactor(this);
  double scaleFont(double value) => Responsive.font(this, value);
  double scaleSpacing(double value) => Responsive.spacing(this, value);

  T selectValue<T>({
    required T mobile,
    T? tablet,
    T? smallMobile,
  }) {
    return Responsive.selectValue(
      context: this,
      mobile: mobile,
      tablet: tablet,
      smallMobile: smallMobile,
    );
  }
}

/// A responsive widget builder choosing layouts automatically matching active screen size category
class ResponsiveWidget extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? smallMobile;

  const ResponsiveWidget({
    super.key,
    required this.mobile,
    this.tablet,
    this.smallMobile,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= AppBreakpoints.tablet && tablet != null) {
      return tablet!;
    } else if (width < AppBreakpoints.mobileSmall && smallMobile != null) {
      return smallMobile!;
    }
    return mobile;
  }
}

/// A responsive grid wrapping items cleanly relative to column counts and cross axis counts
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int crossAxisCountMobile;
  final int? crossAxisCountTablet;
  final double spacing;
  final double runSpacing;
  final double? childAspectRatio;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.crossAxisCountMobile = 2,
    this.crossAxisCountTablet,
    this.spacing = 12.0,
    this.runSpacing = 12.0,
    this.childAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final isTab = Responsive.isTablet(context);
    final columns = isTab ? (crossAxisCountTablet ?? 3) : crossAxisCountMobile;

    if (childAspectRatio != null) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: runSpacing,
          childAspectRatio: childAspectRatio!,
        ),
        itemCount: children.length,
        itemBuilder: (context, index) => children[index],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children.map((child) {
            return SizedBox(
              width: itemWidth,
              child: child,
            );
          }).toList(),
        );
      },
    );
  }
}
