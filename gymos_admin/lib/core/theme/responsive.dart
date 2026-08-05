import 'package:flutter/material.dart';

/// Desktop-first responsive breakpoints for the admin panel
class AdminBreakpoints {
  static const double mobile = 768.0;
  static const double tablet = 1024.0;
  static const double desktop = 1440.0;
}

enum ScreenSize { mobile, tablet, desktop, largeDesktop }

class AdminResponsive {
  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < AdminBreakpoints.mobile) return ScreenSize.mobile;
    if (width < AdminBreakpoints.tablet) return ScreenSize.tablet;
    if (width < AdminBreakpoints.desktop) return ScreenSize.desktop;
    return ScreenSize.largeDesktop;
  }

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < AdminBreakpoints.mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= AdminBreakpoints.mobile && w < AdminBreakpoints.tablet;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= AdminBreakpoints.tablet;

  static bool isLargeDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= AdminBreakpoints.desktop;

  static double contentPadding(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.mobile:
        return 16.0;
      case ScreenSize.tablet:
        return 24.0;
      case ScreenSize.desktop:
        return 32.0;
      case ScreenSize.largeDesktop:
        return 40.0;
    }
  }

  static int gridColumns(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.mobile:
        return 1;
      case ScreenSize.tablet:
        return 2;
      case ScreenSize.desktop:
        return 3;
      case ScreenSize.largeDesktop:
        return 4;
    }
  }

  static int statCardColumns(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.mobile:
        return 2;
      case ScreenSize.tablet:
        return 3;
      case ScreenSize.desktop:
        return 4;
      case ScreenSize.largeDesktop:
        return 5;
    }
  }

  static T selectValue<T>(BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
    T? largeDesktop,
  }) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.largeDesktop:
        return largeDesktop ?? desktop ?? tablet ?? mobile;
      case ScreenSize.desktop:
        return desktop ?? tablet ?? mobile;
      case ScreenSize.tablet:
        return tablet ?? mobile;
      case ScreenSize.mobile:
        return mobile;
    }
  }
}

/// Extension for quick responsive helpers
extension AdminResponsiveContext on BuildContext {
  ScreenSize get screenSize => AdminResponsive.getScreenSize(this);
  bool get isMobile => AdminResponsive.isMobile(this);
  bool get isTablet => AdminResponsive.isTablet(this);
  bool get isDesktop => AdminResponsive.isDesktop(this);
  bool get isLargeDesktop => AdminResponsive.isLargeDesktop(this);
  double get contentPadding => AdminResponsive.contentPadding(this);
  int get gridColumns => AdminResponsive.gridColumns(this);
  int get statCardColumns => AdminResponsive.statCardColumns(this);
  double get screenWidth => MediaQuery.of(context).size.width;
  double get screenHeight => MediaQuery.of(context).size.height;

  BuildContext get context => this;

  T responsive<T>({
    required T mobile,
    T? tablet,
    T? desktop,
    T? largeDesktop,
  }) => AdminResponsive.selectValue(this,
    mobile: mobile, tablet: tablet, desktop: desktop, largeDesktop: largeDesktop,
  );
}
