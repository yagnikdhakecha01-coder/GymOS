import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

  static Route<T> slideRoute<T>(Widget page, {bool slideUp = false}) {
    // On iOS, native CupertinoPageRoute leverages Metal hardware layer caching
    // with native 120Hz ProMotion swipe-back gesture and zero raster-thread jank.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoPageRoute<T>(
        builder: (_) => page,
        fullscreenDialog: slideUp,
      );
    }

    if (slideUp) {
      return PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.fastOutSlowIn;
          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 240),
      );
    }

    return MaterialPageRoute<T>(builder: (_) => page);
  }

  static Route<T> scaleRoute<T>(Widget page) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoPageRoute<T>(builder: (_) => page);
    }

    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const curve = Curves.fastOutSlowIn;
        final scaleTween = Tween<double>(begin: 0.96, end: 1.0).chain(CurveTween(curve: curve));
        return ScaleTransition(
          scale: animation.drive(scaleTween),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    );
  }
}

