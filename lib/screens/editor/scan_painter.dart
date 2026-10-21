import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/constants.dart';
import '../../models/hl_shape.dart';

/// Shared highlight renderer, used both for the live editor canvas and for
/// burning highlights into the full-resolution image (`applyScan`).
/// Coordinates are relative to the image centre.
class HighlightRenderer {
  static void _renderShape(Canvas c, HlShape s) {
    final color = Color(s.color);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    if (s.type == 'free' && s.pts != null && s.pts!.isNotEmpty) {
      final path = Path()..moveTo(s.pts![0].x, s.pts![0].y);
      for (var k = 1; k < s.pts!.length; k++) {
        path.lineTo(s.pts![k].x, s.pts![k].y);
      }
      if (s.pts!.length == 1) path.lineTo(s.pts![0].x + 0.01, s.pts![0].y);
      c.drawPath(path, stroke);
    } else if (s.type == 'free_straight' && s.start != null && s.current != null) {
      c.drawLine(Offset(s.start!.x, s.start!.y), Offset(s.current!.x, s.current!.y), stroke);
    } else if (s.type == 'rect' && s.start != null && s.current != null) {
      c.drawRect(Rect.fromPoints(Offset(s.start!.x, s.start!.y), Offset(s.current!.x, s.current!.y)), fill);
    } else if (s.type == 'oval' && s.start != null && s.current != null) {
      c.drawOval(Rect.fromPoints(Offset(s.start!.x, s.start!.y), Offset(s.current!.x, s.current!.y)), fill);
    }
  }

  static void _withRotation(Canvas c, HlShape s, void Function() f) {
    c.save();
    final ctr = s.center();
    c.translate(ctr.x, ctr.y);
    c.rotate(s.angle * math.pi / 180);
    c.translate(-ctr.x, -ctr.y);
    f();
    c.restore();
  }

  /// multiply layer → normal (source-over) layers → text layers.
  static void paintAll(Canvas c, List<HlShape> shapes, {HlShape? drawing, Rect? layerBounds}) {
    c.saveLayer(layerBounds, Paint()..blendMode = BlendMode.multiply);
    for (final s in shapes) {
      if (s.blendMode != 'source-over') _withRotation(c, s, () => _renderShape(c, s));
    }
    if (drawing != null && drawing.blendMode != 'source-over') _withRotation(c, drawing, () => _renderShape(c, drawing));
    c.restore();

    for (final s in shapes) {
      if (s.blendMode == 'source-over') _withRotation(c, s, () => _renderShape(c, s));
    }
    if (drawing != null && drawing.blendMode == 'source-over') _withRotation(c, drawing, () => _renderShape(c, drawing));

    for (final s in shapes) {
      if (s.type == 'text' && (s.textValue ?? '').isNotEmpty && s.start != null && s.current != null) {
        _withRotation(c, s, () {
          final minX = math.min(s.start!.x, s.current!.x), minY = math.min(s.start!.y, s.current!.y);
          final col = (!isWhiteColor(s.color) && Color(s.color).a > 0) ? Color(s.color) : Colors.black;
          final lineH = s.fontSize * 1.2;
          final lines = s.textValue!.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final tp = TextPainter(
              text: TextSpan(
                text: lines[i],
                style: TextStyle(color: col, fontSize: s.fontSize, fontWeight: FontWeight.bold, height: 1.0, fontFamily: 'sans-serif'),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(c, Offset(minX + 6, minY + 6 + i * lineH));
          }
        });
      }
    }
  }
}

/// Everything `drawScan()` needs.
class ScanViewState {
  final ui.Image image;
  final ColorFilter? previewFilter;
  final int rotation;
  final double sw, sh, zoom, panX, panY;
  final List<HlShape> shapes;
  final HlShape? drawing;
  final String editorMode;
  final int selectedIndex;
  final bool dpadOpen;
  final List<Pt> pts;
  ScanViewState({
    required this.image,
    this.previewFilter,
    required this.rotation,
    required this.sw,
    required this.sh,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.shapes,
    required this.drawing,
    required this.editorMode,
    required this.selectedIndex,
    required this.dpadOpen,
    required this.pts,
  });
}

class ScanPainter extends CustomPainter {
  final ScanViewState Function() read;
  final Listenable repaintSignal;

  /// Optional magnifier transform: draws the region around [magCenter] at 2x.
  final Offset? magCenter;
  ScanPainter(this.read, this.repaintSignal, {this.magCenter}) : super(repaint: repaintSignal);

  static const _crop = Color(0xFFA0D7FE);

  @override
  void paint(Canvas canvas, Size size) {
    final v = read();
    final sw = v.sw, sh = v.sh, z = v.zoom;
    if (magCenter != null) {
      canvas.clipRect(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(2);
      canvas.translate(-magCenter!.dx, -magCenter!.dy);
      canvas.clipRect(Rect.fromLTWH(0, 0, sw, sh));
    } else {
      canvas.clipRect(Offset.zero & size);
    }
    canvas.save();
    canvas.translate(sw / 2 + v.panX, sh / 2 + v.panY);
    canvas.scale(z);

    // image
    canvas.save();
    canvas.rotate(v.rotation * math.pi / 180);
    final isRot = (v.rotation ~/ 90) % 2 != 0;
    final dw = isRot ? sh : sw, dh = isRot ? sw : sh;
    final ip = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = v.previewFilter;
    canvas.drawImageRect(v.image, Rect.fromLTWH(0, 0, v.image.width.toDouble(), v.image.height.toDouble()),
        Rect.fromLTWH(-dw / 2, -dh / 2, dw, dh), ip);
    canvas.restore();

    // highlights
    HighlightRenderer.paintAll(canvas, v.shapes, drawing: v.drawing, layerBounds: Rect.fromLTWH(-sw / 2, -sh / 2, sw, sh));

    // selection handles
    if (v.editorMode == 'highlight' && !v.dpadOpen && v.selectedIndex >= 0 && v.selectedIndex < v.shapes.length) {
      final s = v.shapes[v.selectedIndex];
      final ctr = s.center();
      canvas.save();
      canvas.translate(ctr.x, ctr.y);
      canvas.rotate(s.angle * math.pi / 180);
      canvas.translate(-ctr.x, -ctr.y);
      final hs = s.handles();
      final b = s.bounds();
      _dashedRect(canvas, Rect.fromLTRB(b[0], b[1], b[2], b[3]),
          Paint()
            ..color = const Color(0xFF00FFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / z,
          4 / z);
      final tc = hs[1];
      final rotY = tc.y - 25 / z;
      final blue = Paint()
        ..color = const Color(0xFF007BFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / z;
      canvas.drawLine(Offset(tc.x, tc.y), Offset(tc.x, rotY), blue);
      canvas.drawCircle(Offset(tc.x, rotY), 6 / z, Paint()..color = const Color(0xFF00FFFF));
      canvas.drawCircle(Offset(tc.x, rotY), 6 / z, blue);
      for (final h in hs) {
        canvas.drawCircle(Offset(h.x, h.y), 6 / z, Paint()..color = Colors.white);
        canvas.drawCircle(
            Offset(h.x, h.y),
            6 / z,
            Paint()
              ..color = const Color(0xFF007BFF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 / z);
      }
      canvas.restore();
    }

    // crop quad + 8 handles
    if (v.editorMode == 'crop' && v.pts.length == 4) {
      final path = Path()..moveTo(v.pts[0].x - sw / 2, v.pts[0].y - sh / 2);
      for (var i = 1; i < 4; i++) {
        path.lineTo(v.pts[i].x - sw / 2, v.pts[i].y - sh / 2);
      }
      path.close();
      // soft dim outside the crop for a modern look
      final dim = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Rect.fromLTWH(-sw / 2, -sh / 2, sw, sh))
        ..addPath(path, Offset.zero);
      canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.28));
      canvas.drawPath(
          path,
          Paint()
            ..color = _crop
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 / z);
      for (final hp in crop8Points(v.pts)) {
        final o = Offset(hp.$1 - sw / 2, hp.$2 - sh / 2);
        if (hp.$3) {
          canvas.drawCircle(o, 10 / z, Paint()..color = _crop);
          canvas.drawCircle(
              o,
              10 / z,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2 / z);
        } else {
          final r = Rect.fromCenter(center: o, width: 12 / z, height: 12 / z);
          canvas.drawRect(r, Paint()..color = Colors.white);
          canvas.drawRect(
              r,
              Paint()
                ..color = _crop
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.5 / z);
        }
      }
    }
    canvas.restore();

    if (magCenter != null) {
      // white reticle square in the centre of the loupe (mctx.strokeRect(65,65,10,10))
      canvas.drawRect(
          Rect.fromCenter(center: magCenter!, width: 5, height: 5),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
  }

  static void _dashedRect(Canvas c, Rect r, Paint p, double dash) {
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      var t = 0.0;
      while (t < len) {
        final e = math.min(t + dash, len);
        c.drawLine(a + dir * t, a + dir * e, p);
        t += dash * 2;
      }
    }

    if (r.width <= 0 && r.height <= 0) return;
    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(covariant ScanPainter old) => true;
}

/// getCrop8Points(): (x, y, isCorner, cornerIdx | edgeIdx)
List<(double, double, bool, int)> crop8Points(List<Pt> p) {
  if (p.length < 4) return const [];
  return [
    (p[0].x, p[0].y, true, 0),
    ((p[0].x + p[1].x) / 2, (p[0].y + p[1].y) / 2, false, 0),
    (p[1].x, p[1].y, true, 1),
    ((p[1].x + p[2].x) / 2, (p[1].y + p[2].y) / 2, false, 1),
    (p[2].x, p[2].y, true, 2),
    ((p[2].x + p[3].x) / 2, (p[2].y + p[3].y) / 2, false, 2),
    (p[3].x, p[3].y, true, 3),
    ((p[3].x + p[0].x) / 2, (p[3].y + p[0].y) / 2, false, 3),
  ];
}
