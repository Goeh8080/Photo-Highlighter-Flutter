import 'package:flutter/material.dart';

/// Shared-axis (Z) style transition: incoming page fades + scales up from 0.92,
/// outgoing page fades + scales slightly up. Spring-like easing.
class GlassPageRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;
  GlassPageRoute({required this.builder, super.fullscreenDialog})
      : super(
          transitionDuration: const Duration(milliseconds: 520),
          reverseTransitionDuration: const Duration(milliseconds: 380),
          opaque: false,
          barrierColor: Colors.transparent,
          pageBuilder: (context, _, _) => builder(context),
          transitionsBuilder: (context, anim, secondary, child) {
            final inCurve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            final scaleIn = Tween(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic));
            final outScale = Tween(begin: 1.0, end: 1.06).animate(CurvedAnimation(parent: secondary, curve: Curves.easeOutCubic));
            final outFade = Tween(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: secondary, curve: const Interval(0, 0.6)));
            return FadeTransition(
              opacity: outFade,
              child: ScaleTransition(
                scale: outScale,
                child: FadeTransition(opacity: inCurve, child: ScaleTransition(scale: scaleIn, child: child)),
              ),
            );
          },
        );
}

/// Bottom-sheet-like slide-up for full-screen editors.
class SlideUpRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;
  SlideUpRoute({required this.builder})
      : super(
          transitionDuration: const Duration(milliseconds: 480),
          reverseTransitionDuration: const Duration(milliseconds: 340),
          pageBuilder: (context, _, _) => builder(context),
          transitionsBuilder: (context, anim, _, child) {
            final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            return FadeTransition(
              opacity: c,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(c),
                child: child,
              ),
            );
          },
        );
}
