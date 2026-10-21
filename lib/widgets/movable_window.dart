import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// Port of `.movable-pop-window` + `makePopMovable()`: a floating glass
/// window, centred on open, draggable by its header, clamped 10px from edges.
class MovableGlassWindow extends StatefulWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;
  final double width;
  final bool lightDialog; // the colour picker uses a white iOS dialog look
  const MovableGlassWindow({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.width = 320,
    this.lightDialog = false,
  });

  @override
  State<MovableGlassWindow> createState() => _MovableGlassWindowState();
}

class _MovableGlassWindowState extends State<MovableGlassWindow> {
  Offset? _pos;
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final screen = MediaQuery.sizeOf(context);
    final w = widget.width.clamp(0.0, screen.width * 0.92);
    if (_pos == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = _key.currentContext?.findRenderObject() as RenderBox?;
        final h = box?.size.height ?? 250;
        if (mounted) {
          setState(() => _pos = Offset(
                ((screen.width - w) / 2).clamp(10, double.infinity),
                ((screen.height - h) / 2).clamp(10, double.infinity),
              ));
        }
      });
    }
    final pos = _pos ?? Offset((screen.width - w) / 2, screen.height * 0.25);
    final headerColor = widget.lightDialog ? const Color(0xFFE5E5EA) : p.popHeader.withValues(alpha: 0.55);
    final textColor = widget.lightDialog ? const Color(0xFF1C1C1E) : p.textMain;

    final window = SizedBox(
      key: _key,
      width: w,
      child: GlassContainer(
        radius: 18,
        blur: 28,
        fill: widget.lightDialog
            ? [Colors.white.withValues(alpha: 0.94), Colors.white.withValues(alpha: 0.86)]
            : [p.popBg.withValues(alpha: p.isDark ? 0.62 : 0.72), p.popBg.withValues(alpha: p.isDark ? 0.45 : 0.55)],
        child: Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) {
                final box = _key.currentContext?.findRenderObject() as RenderBox?;
                final sz = box?.size ?? Size(w, 250);
                setState(() {
                  final n = (_pos ?? pos) + d.delta;
                  _pos = Offset(
                    n.dx.clamp(10, (screen.width - sz.width - 10).clamp(10, double.infinity)),
                    n.dy.clamp(10, (screen.height - sz.height - 10).clamp(10, double.infinity)),
                  );
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
                  decoration: BoxDecoration(
                    color: headerColor,
                    border: Border(bottom: BorderSide(color: p.glassBorder.withValues(alpha: 0.4), width: 0.8)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 4,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: textColor.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(2)),
                    ),
                    Expanded(
                      child: Text(widget.title,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                    ),
                    LiquidGlassButton(
                      onTap: widget.onClose,
                      circle: true,
                      padding: const EdgeInsets.all(5),
                      pressedScale: 0.85,
                      child: SizedBox(width: 18, height: 18, child: Center(child: Text('✕', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, height: 1, color: widget.lightDialog ? Colors.black54 : p.textSub)))),
                    ),
                  ]),
                ),
              ),
            ),
            widget.child,
          ]),
        ),
      ),
    );

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (_, v, c) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: 0.85 + 0.15 * v, child: c)),
        child: window,
      ),
    );
  }
}
