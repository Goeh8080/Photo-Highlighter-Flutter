import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/movable_window.dart';

/// `#dpadControls` – Transform Pad.
class DPadWindow extends StatelessWidget {
  final String title;
  final String tab;
  final ValueChanged<String> onTab;
  final int step;
  final ValueChanged<int> onStep;
  final void Function(double dx, double dy) onNudge;
  final VoidCallback onCenter;
  final void Function(String edge, double delta) onEdge;
  final VoidCallback onClose;
  const DPadWindow({
    super.key,
    required this.title,
    required this.tab,
    required this.onTab,
    required this.step,
    required this.onStep,
    required this.onNudge,
    required this.onCenter,
    required this.onEdge,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final s = step.toDouble();
    Widget pad(String t, VoidCallback f, {Color? c}) => SizedBox(
          width: 46,
          height: 46,
          child: GlassButton(label: t, color: c, fontSize: 17, padding: EdgeInsets.zero, radius: 12, onTap: f),
        );
    Widget edgeRow(String label, String e1, String l1, double d1, String l2, double d2) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 68, child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.yellow))),
            const Spacer(),
            GlassButton.small(label: l1, fontSize: 11, onTap: () => onEdge(e1, d1)),
            const SizedBox(width: 4),
            GlassButton.small(label: l2, fontSize: 11, onTap: () => onEdge(e1, d2)),
          ]),
        );
    return MovableGlassWindow(
      title: title,
      width: 320,
      onClose: onClose,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GlassSegmented<String>(
            height: 34,
            fontSize: 11,
            values: const ['move', 'resize'],
            selected: tab,
            labelOf: (v) => v == 'move' ? '📍 Move Position' : '📐 1-Side Edge Size',
            onChanged: onTab,
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(a), child: c)),
            child: tab == 'move'
                ? Column(key: const ValueKey('m'), children: [
                    pad('⬆️', () => onNudge(0, -s)),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      pad('⬅️', () => onNudge(-s, 0)),
                      const SizedBox(width: 6),
                      pad('🎯', onCenter, c: AppColors.orange),
                      const SizedBox(width: 6),
                      pad('➡️', () => onNudge(s, 0)),
                    ]),
                    const SizedBox(height: 6),
                    pad('⬇️', () => onNudge(0, s)),
                  ])
                : Container(
                    key: const ValueKey('r'),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: p.glassInput, borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      edgeRow('Top Edge:', 'top', '⬆️+ Expand', -s, '⬇️- Shrink', s),
                      edgeRow('Bottom:', 'bottom', '⬇️+ Expand', s, '⬆️- Shrink', -s),
                      edgeRow('Left Edge:', 'left', '⬅️+ Expand', -s, '➡️- Shrink', s),
                      edgeRow('Right:', 'right', '➡️+ Expand', s, '⬅️- Shrink', -s),
                    ]),
                  ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Text('Step Speed:', style: TextStyle(fontSize: 11, color: p.textSub)),
            const Spacer(),
            SizedBox(
              width: 150,
              child: GlassSegmented<int>(
                height: 28,
                fontSize: 10,
                values: const [1, 4, 10],
                selected: step,
                labelOf: (v) => '${v}px',
                onChanged: onStep,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// `#csModalWindow` – Canvas Size Settings.
class CanvasSizeWindow extends StatefulWidget {
  final void Function(double dw, double dh, String unit) onApply;
  final VoidCallback onClose;
  const CanvasSizeWindow({super.key, required this.onApply, required this.onClose});
  @override
  State<CanvasSizeWindow> createState() => _CanvasSizeWindowState();
}

class _CanvasSizeWindowState extends State<CanvasSizeWindow> {
  String unit = 'px';
  final w = TextEditingController(text: '0'), h = TextEditingController(text: '0');

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    Widget row(String l, Widget child, [String? suffix]) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 105, child: Text(l, style: TextStyle(fontSize: 12, color: p.textMain))),
            Expanded(child: child),
            if (suffix != null) ...[const SizedBox(width: 8), SizedBox(width: 22, child: Text(suffix, style: TextStyle(fontSize: 12, color: p.textSub)))],
          ]),
        );
    return MovableGlassWindow(
      title: '📐 Canvas Size Settings',
      width: 330,
      onClose: widget.onClose,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          row(
              'Unit:',
              GlassSelect<String>(
                expand: true,
                value: unit,
                items: const ['px', 'mm', 'cm'],
                labelOf: (u) => const {'px': 'Pixels (px)', 'mm': 'Millimeters (mm)', 'cm': 'Centimeters (cm)'}[u]!,
                onChanged: (u) => setState(() => unit = u),
              )),
          row('Width (+/-):', GlassTextField(controller: w, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), textAlign: TextAlign.center, fontSize: 13), unit),
          row('Height (+/-):', GlassTextField(controller: h, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), textAlign: TextAlign.center, fontSize: 13), unit),
          const SizedBox(height: 4),
          Text('(Enter positive to expand, negative to shrink)', style: TextStyle(fontSize: 11, color: p.textSub)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            GlassButton.small(label: 'Cancel', color: AppColors.grey, onTap: widget.onClose),
            const SizedBox(width: 8),
            GlassButton.small(
              label: 'OK',
              color: AppColors.blue,
              onTap: () => widget.onApply(double.tryParse(w.text) ?? 0, double.tryParse(h.text) ?? 0, unit),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// `#adjModalWindow` – Photo Adjustments.
class AdjustmentsWindow extends StatelessWidget {
  final Map<String, int> values; // colorScan,bwScan,hue,sat,bright,contrast
  final void Function(String key, int v) onChanged;
  final VoidCallback onReset, onCancel, onApply;
  const AdjustmentsWindow({
    super.key,
    required this.values,
    required this.onChanged,
    required this.onReset,
    required this.onCancel,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    Widget slider(String key, String label, int min, int max, {Color? color}) => Row(children: [
          SizedBox(
            width: 105,
            child: Text(label, style: TextStyle(fontSize: 12, color: color ?? p.textMain, fontWeight: color != null ? FontWeight.bold : FontWeight.normal)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(activeTrackColor: color ?? p.accent),
              child: Slider(
                value: values[key]!.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                onChanged: (v) => onChanged(key, v.round()),
              ),
            ),
          ),
          SizedBox(width: 32, child: Text('${values[key]}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: p.textMain))),
        ]);
    return MovableGlassWindow(
      title: '🎨 Photo Adjustments',
      onClose: onCancel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          slider('colorScan', 'Colour Scan:', -100, 100, color: AppColors.cyan),
          slider('bwScan', 'B&W Scan:', -100, 100, color: AppColors.yellow),
          Divider(color: p.glassBorder.withValues(alpha: 0.4), height: 10),
          slider('hue', 'Hue:', -180, 180),
          slider('sat', 'Saturation:', -100, 100),
          slider('bright', 'Brightness/Lvl:', -100, 100),
          slider('contrast', 'Contrast/Curve:', -100, 100),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            GlassButton.small(label: 'Reset', color: AppColors.red, onTap: onReset),
            const SizedBox(width: 8),
            GlassButton.small(label: 'Cancel', color: AppColors.grey, onTap: onCancel),
            const SizedBox(width: 8),
            GlassButton.small(label: 'Apply', color: AppColors.green, onTap: onApply),
          ]),
        ]),
      ),
    );
  }
}

/// `#cpModalWindow` – infinite colour panel (Grid / Spectrum + Hex + RGB).
class ColorPickerWindow extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onLivePick; // canvas drag (updates selected shape live)
  final ValueChanged<Color> onInputChange; // hex / rgb typing (applyColorLogic)
  final ValueChanged<Color> onOk;
  final VoidCallback onCancel;
  const ColorPickerWindow({
    super.key,
    required this.initial,
    required this.onLivePick,
    required this.onInputChange,
    required this.onOk,
    required this.onCancel,
  });

  @override
  State<ColorPickerWindow> createState() => _ColorPickerWindowState();
}

class _ColorPickerWindowState extends State<ColorPickerWindow> {
  static String _mode = 'grid';
  late int r = (widget.initial.r * 255).round(), g = (widget.initial.g * 255).round(), b = (widget.initial.b * 255).round();
  Offset? cursor;
  final hex = TextEditingController(), rc = TextEditingController(), gc = TextEditingController(), bc = TextEditingController();
  static const cw = 260.0, ch = 180.0;

  @override
  void initState() {
    super.initState();
    _syncFields();
  }

  Color get color => Color.fromARGB(255, r, g, b);

  void _syncFields() {
    String h2(int v) => v.toRadixString(16).padLeft(2, '0');
    hex.text = '#${h2(r)}${h2(g)}${h2(b)}'.toUpperCase();
    rc.text = '$r';
    gc.text = '$g';
    bc.text = '$b';
  }

  static Color colorAt(String mode, double x, double y) {
    if (mode == 'grid') {
      const cols = 12, rows = 10;
      final c = (x / (cw / cols)).floor().clamp(0, cols - 1);
      final rr = (y / (ch / rows)).floor().clamp(0, rows - 1);
      if (c == 0) {
        final v = (255 * (1 - rr / (rows - 1))).round();
        return Color.fromARGB(255, v, v, v);
      }
      final hue = (c - 1) / (cols - 1) * 360;
      final light = (90 - rr / (rows - 1) * 80) / 100;
      return HSLColor.fromAHSL(1, hue % 360, 1, light).toColor();
    }
    // spectrum: horizontal hue gradient + vertical white→clear→black overlay
    const stops = [0.0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0];
    const cols = [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000)];
    final t = (x / cw).clamp(0.0, 1.0);
    var i = 0;
    while (i < stops.length - 2 && t > stops[i + 1]) {
      i++;
    }
    final base = Color.lerp(cols[i], cols[i + 1], (t - stops[i]) / (stops[i + 1] - stops[i]))!;
    final ty = (y / ch).clamp(0.0, 1.0);
    if (ty < 0.5) return Color.lerp(Colors.white, base, ty / 0.5)!;
    return Color.lerp(base, Colors.black, (ty - 0.5) / 0.5)!;
  }

  void _pick(Offset o) {
    final x = o.dx.clamp(0.0, cw - 1), y = o.dy.clamp(0.0, ch - 1);
    final c = colorAt(_mode, x, y);
    setState(() {
      cursor = Offset(x, y);
      r = (c.r * 255).round();
      g = (c.g * 255).round();
      b = (c.b * 255).round();
      _syncFields();
    });
    widget.onLivePick(color);
  }

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF1C1C1E);
    Widget box(String label, TextEditingController c, double w, ValueChanged<String> f) => Container(
          width: w,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(7)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF8E8E93))),
            TextField(
              controller: c,
              onChanged: f,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black),
              inputFormatters: [LengthLimitingTextInputFormatter(7)],
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 2)),
            ),
          ]),
        );
    void rgbChanged(String _) {
      setState(() {
        r = (int.tryParse(rc.text) ?? 0).clamp(0, 255);
        g = (int.tryParse(gc.text) ?? 0).clamp(0, 255);
        b = (int.tryParse(bc.text) ?? 0).clamp(0, 255);
        hex.text = '#${[r, g, b].map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
      });
      widget.onInputChange(color);
    }

    return MovableGlassWindow(
      title: '🎨 Color Spectrum',
      width: 310,
      lightDialog: true,
      onClose: widget.onCancel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(9)),
            child: Row(children: [
              for (final m in const ['grid', 'spectrum'])
                Expanded(
                  child: Pressable(
                    onTap: () => setState(() => _mode = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: _mode == m ? const Color(0xFFD0E1FF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      alignment: Alignment.center,
                      child: Text('${_mode == m ? '✓ ' : ''}${m == 'grid' ? 'Grid' : 'Spectrum'}',
                          style: TextStyle(
                              fontSize: 12,
                              color: _mode == m ? const Color(0xFF0056B3) : Colors.black,
                              fontWeight: _mode == m ? FontWeight.w600 : FontWeight.w500)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onPanDown: (d) => _pick(d.localPosition),
            onPanUpdate: (d) => _pick(d.localPosition),
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: SizedBox(
                width: cw,
                height: ch,
                child: Stack(clipBehavior: Clip.none, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: CustomPaint(key: ValueKey(_mode), size: const Size(cw, ch), painter: _CpPainter(_mode)),
                    ),
                  ),
                  if (cursor != null)
                    Positioned(
                      left: cursor!.dx - 7,
                      top: cursor!.dy - 7,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
            ),
            box('HEX', hex, 80, (v) {
              if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v)) {
                final n = int.parse(v.substring(1), radix: 16);
                setState(() {
                  r = (n >> 16) & 255;
                  g = (n >> 8) & 255;
                  b = n & 255;
                  rc.text = '$r';
                  gc.text = '$g';
                  bc.text = '$b';
                });
                widget.onInputChange(color);
              }
            }),
            Row(children: [
              box('R', rc, 40, rgbChanged),
              const SizedBox(width: 4),
              box('G', gc, 40, rgbChanged),
              const SizedBox(width: 4),
              box('B', bc, 40, rgbChanged),
            ]),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Pressable(onTap: widget.onCancel, child: const Padding(padding: EdgeInsets.all(6), child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, color: dark)))),
            const SizedBox(width: 10),
            Pressable(onTap: () => widget.onOk(color), child: const Padding(padding: EdgeInsets.all(6), child: Text('OK', style: TextStyle(fontWeight: FontWeight.w600, color: dark)))),
          ]),
        ]),
      ),
    );
  }
}

class _CpPainter extends CustomPainter {
  final String mode;
  _CpPainter(this.mode);
  @override
  void paint(Canvas c, Size s) {
    if (mode == 'grid') {
      const cols = 12, rows = 10;
      final cw = s.width / cols, ch = s.height / rows;
      for (var r = 0; r < rows; r++) {
        for (var k = 0; k < cols; k++) {
          c.drawRect(Rect.fromLTWH(k * cw, r * ch, cw + 0.5, ch + 0.5),
              Paint()..color = _ColorPickerWindowState.colorAt('grid', k * cw + cw / 2, r * ch + ch / 2));
        }
      }
    } else {
      final rect = Offset.zero & s;
      c.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(colors: [
              Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000)
            ], stops: [0, 0.17, 0.33, 0.5, 0.67, 0.83, 1]).createShader(rect));
      c.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF), Color(0x00000000), Color(0xFF000000)],
              stops: [0, 0.5, 0.5, 1],
            ).createShader(rect));
    }
  }

  @override
  bool shouldRepaint(covariant _CpPainter o) => o.mode != mode;
}

double unitScale(String unit) => unit == 'mm' ? 3.7795 : (unit == 'cm' ? 37.795 : 1.0);
double clampD(double v, double lo, double hi) => math.max(lo, math.min(hi, v));
