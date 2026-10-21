import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'liquid_glass.dart';

export 'liquid_glass.dart';

/// Core "liquid glass" surface: backdrop blur + translucent gradient fill +
/// thin light border + specular highlight + soft shadow.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;
  final List<Color>? fill;
  final Color? borderColor;
  final double borderWidth;
  final bool highlight;
  final bool shadow;
  final double? width;
  final double? height;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding,
    this.margin,
    this.blur = 22,
    this.fill,
    this.borderColor,
    this.borderWidth = 1,
    this.highlight = true,
    this.shadow = true,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final br = BorderRadius.circular(radius);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fill ?? p.glassFill,
        ),
        border: Border.all(color: borderColor ?? p.glassBorder, width: borderWidth),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (highlight) {
      body = Stack(children: [
        body,
        // Specular highlight: bright sheen on the top edge, fading out.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: br,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.18, 0.5],
                  colors: [
                    Colors.white.withValues(alpha: p.isDark ? 0.16 : 0.45),
                    Colors.white.withValues(alpha: p.isDark ? 0.03 : 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ]);
    }
    Widget clipped = ClipRRect(
      borderRadius: br,
      child: blur > 0
          ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: body)
          : body,
    );
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: shadow
          ? BoxDecoration(borderRadius: br, boxShadow: [
              BoxShadow(color: p.shadow, blurRadius: 24, offset: const Offset(0, 8), spreadRadius: -6),
            ])
          : null,
      child: clipped,
    );
  }
}

/// A padded glass card, equivalent to the original `.card`.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  const GlassCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: GlassContainer(margin: margin, padding: padding, radius: 22, child: child),
      );
}

/// Spring-y pressable wrapper with real spring physics, squish and haptics.
class Pressable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  const Pressable({super.key, required this.child, this.onTap, this.pressedScale = 0.93});

  @override
  Widget build(BuildContext context) =>
      SpringPressable(onTap: onTap, pressedScale: pressedScale, builder: (_, _) => child);
}

/// Glass pill button. `color == null` renders neutral frosted glass; a colour
/// renders a tinted, glossy "jelly" button (like the coloured HTML buttons).
class GlassButton extends StatelessWidget {
  final String label;
  final String? emoji;
  final IconData? icon;
  final Color? color;
  final Color? textColor;
  final VoidCallback? onTap;
  final bool active;
  final Color activeColor;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool bold;
  final bool expand;

  const GlassButton({
    super.key,
    required this.label,
    this.emoji,
    this.icon,
    this.color,
    this.textColor,
    this.onTap,
    this.active = false,
    this.activeColor = AppColors.blue,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.radius = 14,
    this.bold = false,
    this.expand = false,
  });

  const GlassButton.small({
    super.key,
    required this.label,
    this.emoji,
    this.icon,
    this.color,
    this.textColor,
    this.onTap,
    this.active = false,
    this.activeColor = AppColors.blue,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.radius = 11,
    this.bold = true,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final tint = active ? activeColor : color;
    final fg = textColor ?? (tint != null ? (tint.computeLuminance() > 0.6 ? Colors.black : Colors.white) : p.textMain);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (emoji != null) ...[Text(emoji!, style: TextStyle(fontSize: fontSize)), const SizedBox(width: 5)],
        if (icon != null) ...[Icon(icon, size: fontSize + 3, color: fg), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: (bold || active) ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.1,
              // Soft engraved shadow keeps white labels legible on the glass.
              shadows: fg == Colors.white ? const [Shadow(color: Color(0x59000000), blurRadius: 3, offset: Offset(0, 1))] : null,
            ),
          ),
        ),
      ],
    );
    return SpringPressable(
      onTap: onTap,
      pressedScale: 0.94,
      builder: (context, press) => LiquidGlassSurface(
        tint: tint,
        radius: radius,
        padding: padding,
        press: press,
        glow: active,
        child: content,
      ),
    );
  }
}

/// Segmented control with an animated sliding glass indicator.
class GlassSegmented<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final Color activeColor;
  final double fontSize;
  final double height;

  const GlassSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.activeColor = AppColors.blue,
    this.fontSize = 13,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final idx = values.indexOf(selected).clamp(0, values.length - 1);
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.glassInput,
        borderRadius: BorderRadius.circular(height / 2.6),
        border: Border.all(color: p.glassBorder.withValues(alpha: 0.5), width: 0.8),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final segW = c.maxWidth / values.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            left: segW * idx,
            top: 0,
            bottom: 0,
            width: segW,
            child: LiquidGlassSurface(
              tint: activeColor,
              radius: height / 3,
              glow: p.isDark,
              blur: false,
              child: const SizedBox.expand(),
            ),
          ),
          Row(
            children: [
              for (final v in values)
                Expanded(
                  child: Pressable(
                    pressedScale: 0.9,
                    onTap: () => onChanged(v),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: TextStyle(
                          fontSize: fontSize,
                          color: v == selected ? Colors.white : p.textMain.withValues(alpha: 0.85),
                          fontWeight: v == selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        child: Text(labelOf(v), maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ]);
      }),
    );
  }
}

/// Glass text input.
class GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final double fontSize;
  final TextAlign textAlign;
  final EdgeInsetsGeometry contentPadding;

  const GlassTextField({
    super.key,
    required this.controller,
    this.hint = '',
    this.onChanged,
    this.keyboardType,
    this.fontSize = 14,
    this.textAlign = TextAlign.start,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final b = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: p.glassBorder.withValues(alpha: 0.55), width: 0.8),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      textAlign: textAlign,
      style: TextStyle(color: p.textMain, fontSize: fontSize),
      cursorColor: p.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(color: p.textSub.withValues(alpha: 0.8), fontSize: fontSize),
        filled: true,
        fillColor: p.glassInput,
        contentPadding: contentPadding,
        enabledBorder: b,
        border: b,
        focusedBorder: b.copyWith(borderSide: BorderSide(color: p.accent, width: 1.4)),
      ),
    );
  }
}

/// Animated glass checkbox with label.
class GlassCheck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final double fontSize;
  const GlassCheck({super.key, required this.value, required this.onChanged, required this.label, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    return Pressable(
      onTap: () => onChanged(!value),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: value ? p.accent : p.glassInput,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: value ? Colors.white.withValues(alpha: 0.6) : p.border),
            boxShadow: value ? [BoxShadow(color: p.accent.withValues(alpha: 0.5), blurRadius: 8)] : null,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: value ? const Icon(Icons.check_rounded, key: ValueKey(1), size: 15, color: Colors.white) : const SizedBox(key: ValueKey(0)),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(fontSize: fontSize, color: p.textMain)),
      ]),
    );
  }
}

/// Glass dropdown (replacement for `<select>`), opening a frosted menu.
class GlassSelect<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final double fontSize;
  final bool expand;

  const GlassSelect({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.fontSize = 13,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    return PopupMenuButton<T>(
      tooltip: '',
      initialValue: value,
      onSelected: onChanged,
      color: p.popBg.withValues(alpha: 0.96),
      elevation: 12,
      shadowColor: p.shadow,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 180),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.glassBorder.withValues(alpha: 0.5))),
      position: PopupMenuPosition.under,
      popUpAnimationStyle: const AnimationStyle(curve: Curves.easeOutCubic, duration: Duration(milliseconds: 240)),
      itemBuilder: (_) => [
        for (final it in items)
          PopupMenuItem<T>(
            value: it,
            height: 38,
            child: Text(labelOf(it),
                style: TextStyle(
                    fontSize: fontSize,
                    color: it == value ? p.accent : p.textMain,
                    fontWeight: it == value ? FontWeight.w700 : FontWeight.w400)),
          ),
      ],
      child: LiquidGlassSurface(
        radius: 11,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [
          if (expand)
            Expanded(child: _label(p))
          else
            _label(p),
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: fontSize + 5, color: p.textSub),
        ]),
      ),
    );
  }

  // Cross-fades + slides the label when the selected tool/option changes.
  Widget _label(AppPalette p) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: c),
        ),
        child: Text(labelOf(value),
            key: ValueKey(value), overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(fontSize: fontSize, color: p.textMain)),
      );
}

/// Animated "liquid" background: slow-drifting colour blobs behind the glass
/// so that the backdrop blur has something to refract.
class LiquidBackground extends StatefulWidget {
  final Widget child;
  const LiquidBackground({super.key, required this.child});

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 22))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    return Stack(children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            color: p.bgMain,
            child: CustomPaint(painter: _BlobPainter(_c, p.blobs, p.isDark)),
          ),
        ),
      ),
      widget.child,
    ]);
  }
}

class _BlobPainter extends CustomPainter {
  final Animation<double> t;
  final List<Color> colors;
  final bool dark;
  _BlobPainter(this.t, this.colors, this.dark) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value * 2 * 3.141592653589793;
    final specs = <(double, double, double, double)>[
      (0.15, 0.12, 0.55, 0.0),
      (0.85, 0.30, 0.50, 1.7),
      (0.25, 0.75, 0.60, 3.1),
      (0.80, 0.88, 0.45, 4.4),
    ];
    for (var i = 0; i < specs.length; i++) {
      final s = specs[i];
      final cx = size.width * (s.$1 + 0.12 * _sin(v + s.$4));
      final cy = size.height * (s.$2 + 0.08 * _cos(v * 0.8 + s.$4));
      final r = size.shortestSide * s.$3 * (1 + 0.1 * _sin(v * 1.3 + i));
      final c = colors[i % colors.length];
      final paint = Paint()
        ..shader = RadialGradient(colors: [
          c.withValues(alpha: dark ? 0.42 : 0.55),
          c.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  static double _sin(double x) => math.sin(x);
  static double _cos(double x) => math.cos(x);

  @override
  bool shouldRepaint(covariant _BlobPainter old) => old.colors != colors || old.dark != dark;
}

/// Glass header bar (blurred) used by home + gallery screens.
class GlassBar extends StatelessWidget {
  final Widget child;
  const GlassBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, top + 10, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.bgHeader.withValues(alpha: 0.72), p.bgHeader.withValues(alpha: 0.45)],
            ),
            border: Border(bottom: BorderSide(color: p.glassBorder.withValues(alpha: 0.5), width: 0.8)),
          ),
          child: child,
        ),
      ),
    );
  }
}
