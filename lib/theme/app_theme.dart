import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Palette mirroring the CSS custom properties of the original page
/// (`:root` = dark, `body.light-theme` = light blue).
@immutable
class AppPalette {
  /// 1.0 = dark, 0.0 = light. Fractional while the theme cross-fades.
  final double darkness;
  bool get isDark => darkness >= 0.5;
  final Color bgMain, bgHeader, bgCard, bgCardAlt, bgInput, border;
  final Color textMain, textSub, accent, accentLight, popBg, popHeader;
  final Color shadow, cropLine;
  final List<Color> blobs;

  const AppPalette({
    required this.darkness,
    required this.bgMain,
    required this.bgHeader,
    required this.bgCard,
    required this.bgCardAlt,
    required this.bgInput,
    required this.border,
    required this.textMain,
    required this.textSub,
    required this.accent,
    required this.accentLight,
    required this.popBg,
    required this.popHeader,
    required this.shadow,
    required this.cropLine,
    required this.blobs,
  });

  static const dark = AppPalette(
    darkness: 1,
    bgMain: Color(0xFF0F1115),
    bgHeader: Color(0xFF12141A),
    bgCard: Color(0xFF141823),
    bgCardAlt: Color(0xFF1C2230),
    bgInput: Color(0xFF1A2030),
    border: Color(0xFF2D3344),
    textMain: Colors.white,
    textSub: Color(0xFFAAAAAA),
    accent: Color(0xFF007BFF),
    accentLight: Color(0xFF6EA8FF),
    popBg: Color(0xFF252830),
    popHeader: Color(0xFF1A1D24),
    shadow: Color(0x99000000),
    cropLine: Color(0xFFA0D7FE),
    blobs: [Color(0xFF007BFF), Color(0xFF8E44AD), Color(0xFF00CEC9), Color(0xFFE67E22)],
  );

  static const light = AppPalette(
    darkness: 0,
    bgMain: Color(0xFFF0F6FF),
    bgHeader: Color(0xFFE1EFFE),
    bgCard: Color(0xFFE3E3E3),
    bgCardAlt: Color(0xFFF4F9FF),
    bgInput: Color(0xFFE8F2FE),
    border: Color(0xFFB9D7FB),
    textMain: Color(0xFF0F172A),
    textSub: Color(0xFF475569),
    accent: Color(0xFF007BFF),
    accentLight: Color(0xFF38BDF8),
    popBg: Color(0xFFE3E3E3),
    popHeader: Color(0xFFE1EFFE),
    shadow: Color(0x26007BFF),
    cropLine: Color(0xFF007BFF),
    blobs: [Color(0xFF38BDF8), Color(0xFFB39DFF), Color(0xFF7FE7DC), Color(0xFFFFC38A)],
  );

  Color _w(double darkA, double lightA) => Colors.white.withValues(alpha: lightA + (darkA - lightA) * darkness);

  /// Glass fill tint (top-left → bottom-right).
  List<Color> get glassFill => [_w(0.13, 0.72), _w(0.04, 0.38)];

  Color get glassBorder => _w(0.18, 0.85);

  Color get glassInput => _w(0.07, 0.55);

  /// Smooth interpolation used for the animated theme cross-fade.
  static AppPalette lerp(AppPalette a, AppPalette b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return AppPalette(
      darkness: a.darkness + (b.darkness - a.darkness) * t,
      bgMain: c(a.bgMain, b.bgMain),
      bgHeader: c(a.bgHeader, b.bgHeader),
      bgCard: c(a.bgCard, b.bgCard),
      bgCardAlt: c(a.bgCardAlt, b.bgCardAlt),
      bgInput: c(a.bgInput, b.bgInput),
      border: c(a.border, b.border),
      textMain: c(a.textMain, b.textMain),
      textSub: c(a.textSub, b.textSub),
      accent: c(a.accent, b.accent),
      accentLight: c(a.accentLight, b.accentLight),
      popBg: c(a.popBg, b.popBg),
      popHeader: c(a.popHeader, b.popHeader),
      shadow: c(a.shadow, b.shadow),
      cropLine: c(a.cropLine, b.cropLine),
      blobs: [for (var i = 0; i < a.blobs.length; i++) c(a.blobs[i], b.blobs[i])],
    );
  }
}

/// Common accent colours used by the original buttons.
class AppColors {
  static const orange = Color(0xFFE67E22);
  static const purple = Color(0xFF8E44AD);
  static const violet = Color(0xFF6C5CE7);
  static const green = Color(0xFF28A745);
  static const blue = Color(0xFF007BFF);
  static const red = Color(0xFFE74C3C);
  static const redBright = Color(0xFFFF4444);
  static const teal = Color(0xFF16A085);
  static const cyan = Color(0xFF00CEC9);
  static const yellow = Color(0xFFF1C40F);
  static const amethyst = Color(0xFF9B59B6);
  static const pumpkin = Color(0xFFD35400);
  static const slate = Color(0xFF34495E);
  static const midnight = Color(0xFF2C3E50);
  static const belize = Color(0xFF2980B9);
  static const crimson = Color(0xFFC0392B);
  static const emerald = Color(0xFF2ECC71);
  static const lightBlue = Color(0xFF6EA8FF);
  static const grey = Color(0xFF555555);
  static const darkGrey = Color(0xFF444444);
}

/// Persists theme just like `localStorage.app_theme_mode`.
class ThemeController extends ValueNotifier<bool> {
  static const _key = 'app_theme_mode';
  final SharedPreferences? prefs;

  ThemeController(this.prefs) : super(prefs?.getString(_key) == 'light');

  bool get isLight => value;
  AppPalette get palette => value ? AppPalette.light : AppPalette.dark;

  Future<void> toggle() async {
    value = !value;
    try {
      await prefs?.setString(_key, value ? 'light' : 'dark');
    } catch (_) {}
  }
}

ThemeData buildTheme(AppPalette p) {
  final base = p.isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: p.bgMain,
    colorScheme: base.colorScheme.copyWith(primary: p.accent, secondary: p.accentLight, surface: p.bgCard),
    textTheme: base.textTheme.apply(bodyColor: p.textMain, displayColor: p.textMain),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.border,
      thumbColor: Colors.white,
      overlayColor: p.accent.withValues(alpha: 0.15),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 3),
    ),
  );
}

/// Inherited access to the (animated) palette + controller anywhere in the tree.
class AppThemeScope extends StatelessWidget {
  final ThemeController controller;
  final Widget Function(BuildContext context, AppPalette palette) builder;
  const AppThemeScope({super.key, required this.controller, required this.builder});

  static ThemeController controllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PaletteScope>()!.controller;

  static AppPalette of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_PaletteScope>()!.palette;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: controller,
        builder: (context, light, _) => TweenAnimationBuilder<double>(
          // 1 = dark, 0 = light; animate the palette for a smooth cross-fade.
          tween: Tween(end: light ? 0 : 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic,
          builder: (context, d, _) {
            final pal = d >= 0.999 ? AppPalette.dark : (d <= 0.001 ? AppPalette.light : AppPalette.lerp(AppPalette.light, AppPalette.dark, d));
            return _PaletteScope(controller: controller, palette: pal, child: Builder(builder: (c) => builder(c, pal)));
          },
        ),
      );
}

class _PaletteScope extends InheritedWidget {
  final ThemeController controller;
  final AppPalette palette;
  const _PaletteScope({required this.controller, required this.palette, required super.child});
  @override
  bool updateShouldNotify(_PaletteScope old) => old.palette != palette;
}
