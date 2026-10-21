import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Shared sigma for all button-level glass so they can share one backdrop
/// snapshot via [BackdropGroup] (see `main.dart`).
const double kButtonBlur = 10;

/// Exposes the press state + shimmer progress to a glass surface.
class PressInfo {
  final bool down;
  final double shimmer; // 0..1 sweep progress, 0 = idle
  const PressInfo(this.down, this.shimmer);
}

/// Spring-physics pressable: squishes to [pressedScale] with a real spring,
/// bounces back on release and fires a highlight shimmer sweep.
class SpringPressable extends StatefulWidget {
  final VoidCallback? onTap;
  final double pressedScale;
  final Widget Function(BuildContext, PressInfo) builder;
  final bool haptic;
  const SpringPressable({super.key, required this.builder, this.onTap, this.pressedScale = 0.94, this.haptic = true});

  @override
  State<SpringPressable> createState() => _SpringPressableState();
}

class _SpringPressableState extends State<SpringPressable> with TickerProviderStateMixin {
  // Unbounded so the spring can overshoot past 1.0 (the "jelly" bounce).
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);
  late final AnimationController _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  bool _down = false;

  static const _spring = SpringDescription(mass: 1, stiffness: 520, damping: 15);

  void _to(double target, {double velocity = 0}) {
    _scale.animateWith(SpringSimulation(_spring, _scale.value, target, velocity));
  }

  void _press(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    if (v) {
      _to(widget.pressedScale);
    } else {
      _to(1, velocity: 2.5);
      _shimmer.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _press(true) : null,
        onTapCancel: enabled ? () => _press(false) : null,
        onTapUp: enabled ? (_) => _press(false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: AnimatedBuilder(
            animation: Listenable.merge([_scale, _shimmer]),
            builder: (context, _) {
              final s = _scale.value;
              // Squish: slightly wider than tall when pressed => water-drop feel.
              final dy = 1 - s;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(s + dy * 0.25, s - dy * 0.15, 1),
                child: widget.builder(context, PressInfo(_down, _shimmer.isAnimating ? _shimmer.value : 0)),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The "water-filled glass" surface: blurred backdrop, translucent tinted
/// fill with a convex radial bulge, strong upper specular sheen, rim light
/// (bright top-left, dark bottom-right), inner bottom refraction glow,
/// coloured soft drop shadow and an optional shimmer sweep.
class LiquidGlassSurface extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  final PressInfo press;
  final bool glow; // stronger shadow, e.g. "active"
  final bool blur;
  final bool circle;

  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.tint,
    this.radius = 14,
    this.padding = EdgeInsets.zero,
    this.press = const PressInfo(false, 0),
    this.glow = false,
    this.blur = true,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final shape = circle
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)) as ShapeBorder;
    final shadowColor = tint ?? (p.isDark ? Colors.black : const Color(0xFF6A8CC0));
    Widget body = CustomPaint(
      painter: _LiquidGlassPainter(
        tint: tint,
        dark: p.isDark,
        neutral: p.glassInput,
        radius: radius,
        circle: circle,
        pressed: press.down,
        shimmer: press.shimmer,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (blur) {
      body = BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: kButtonBlur, sigmaY: kButtonBlur),
        child: body,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: [
          // Theme-aware drop shadow: dark = rich coloured glow,
          // light = small, soft, low-opacity shadow (no wide halo).
          if (p.isDark)
            BoxShadow(
              color: shadowColor.withValues(alpha: tint != null ? (glow ? 0.55 : 0.38) : 0.35),
              blurRadius: press.down ? 6 : (glow ? 18 : 12),
              offset: Offset(0, press.down ? 2 : 5),
              spreadRadius: -3,
            )
          else
            BoxShadow(
              color: (tint ?? const Color(0xFF6A8CC0)).withValues(alpha: tint != null ? (glow ? 0.22 : 0.16) : 0.12),
              blurRadius: press.down ? 3 : 6,
              offset: Offset(0, press.down ? 1 : 2),
              spreadRadius: -2,
            ),
        ],
      ),
      child: ClipPath(clipper: ShapeBorderClipper(shape: shape), child: body),
    );
  }
}

class _LiquidGlassPainter extends CustomPainter {
  final Color? tint;
  final bool dark;
  final Color neutral;
  final double radius;
  final bool circle;
  final bool pressed;
  final double shimmer;
  _LiquidGlassPainter({
    required this.tint,
    required this.dark,
    required this.neutral,
    required this.radius,
    required this.circle,
    required this.pressed,
    required this.shimmer,
  });

  RRect _rr(Rect r) => circle
      ? RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2))
      : RRect.fromRectAndRadius(r, Radius.circular(radius.clamp(0, r.shortestSide / 2)));

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = _rr(rect);
    final t = tint;

    // 1. Translucent tinted "water" fill with a convex bulge: brighter in the
    //    upper-centre, deeper towards the rim.
    // Light theme: slightly desaturated tint for a cleaner iOS look.
    final base = t == null ? (dark ? const Color(0xFF8FA6C8) : Colors.white) : (dark ? t : Color.lerp(t, const Color(0xFFB8C4D6), 0.06)!);
    final fillA = t != null ? (dark ? 0.82 : 0.86) : (dark ? 0.14 : 0.42);
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.15,
          colors: [
            Color.lerp(base, Colors.white, t != null ? 0.1 : 0.0)!.withValues(alpha: fillA * (pressed ? 1.12 : 1.0)),
            base.withValues(alpha: fillA * 0.92),
            Color.lerp(base, Colors.black, t != null ? (dark ? 0.28 : 0.14) : 0.1)!.withValues(alpha: fillA + 0.12),
          ],
          stops: const [0, 0.6, 1],
        ).createShader(rect),
    );

    // 2. Inner bottom refraction glow (light pooled at the bottom of the drop).
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: t != null ? (dark ? 0.30 : 0.16) : (dark ? 0.18 : 0.12)), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );

    // 3. Strong specular sheen on the upper half, inset from the rim.
    final inset = (size.shortestSide * 0.08).clamp(1.5, 4.0);
    final sheenRect = Rect.fromLTRB(inset, inset * 0.7, size.width - inset, size.height * 0.52);
    final sheenR = circle ? sheenRect.shortestSide / 2 : (radius - inset).clamp(2.0, sheenRect.shortestSide / 2);
    canvas.drawRRect(
      RRect.fromRectAndCorners(sheenRect,
          topLeft: Radius.circular(sheenR),
          topRight: Radius.circular(sheenR),
          bottomLeft: Radius.circular(sheenR * 0.6),
          bottomRight: Radius.circular(sheenR * 0.6)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: pressed ? 0.15 : (t == null ? (dark ? 0.22 : 0.25) : (dark ? 0.32 : 0.17))),
            Colors.white.withValues(alpha: 0.04),
          ],
        ).createShader(sheenRect),
    );

    // 4. Shimmer sweep (on release): diagonal light band travelling across.
    if (shimmer > 0 && shimmer < 1) {
      final x = -size.width * 0.6 + shimmer * size.width * 2.2;
      final band = Rect.fromLTWH(x - size.height, 0, size.height * 1.6, size.height);
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.45 * (1 - shimmer)),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.3, 0.5, 0.7],
          ).createShader(band),
      );
      canvas.restore();
    }

    // 5. Rim light: bright top-left -> dark bottom-right (glass edge refraction).
    final rimW = size.shortestSide < 28 ? 1.0 : 1.3;
    canvas.drawRRect(
      rr.deflate(rimW / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.75 : 0.95),
            Colors.white.withValues(alpha: 0.12),
            Colors.black.withValues(alpha: dark ? 0.35 : 0.18),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
    // Thin inner highlight line just under the top rim.
    canvas.drawRRect(
      rr.deflate(rimW + 0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter o) =>
      o.tint != tint || o.dark != dark || o.pressed != pressed || o.shimmer != shimmer || o.radius != radius || o.circle != circle;
}

/// Convenience: a pressable liquid-glass blob (used for icon buttons, chips,
/// the × badge, arrows ...).
class LiquidGlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool circle;
  final bool glow;
  final double pressedScale;
  const LiquidGlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.tint,
    this.radius = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.circle = false,
    this.glow = false,
    this.pressedScale = 0.94,
  });

  @override
  Widget build(BuildContext context) => SpringPressable(
        onTap: onTap,
        pressedScale: pressedScale,
        builder: (context, press) => LiquidGlassSurface(
          tint: tint,
          radius: radius,
          padding: padding,
          circle: circle,
          glow: glow,
          press: press,
          child: child,
        ),
      );
}
