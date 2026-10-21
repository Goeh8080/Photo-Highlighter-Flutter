import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'image_ops.dart';

/// Pure-Dart replacement for the OpenCV.js pipeline in
/// `runAutoEdgeDetection()`: gray → GaussianBlur(5x5) → Canny(75,200) →
/// largest contour → 4-corner polygon. Works on a ≤480px proxy for speed.
class EdgeDetector {
  /// Returns TL, TR, BR, BL in [img] pixel coordinates, or null when the
  /// largest edge contour is not quadrilateral (same "approx.rows === 4" rule).
  static Future<List<Offset>?> detect(ui.Image img) async {
    const maxDim = 480;
    final k = math.min(1.0, maxDim / math.max(img.width, img.height));
    final w = math.max(8, (img.width * k).round()), h = math.max(8, (img.height * k).round());
    final small = await ImageOps.render(w, h, (c) => ImageOps.drawImageTo(c, img, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())));
    final px = await ImageOps.rgba(small);
    small.dispose();

    final n = w * h;
    var gray = Float32List(n);
    for (var i = 0, j = 0; i < n; i++, j += 4) {
      gray[i] = 0.299 * px[j] + 0.587 * px[j + 1] + 0.114 * px[j + 2];
    }
    gray = _blur(gray, w, h);

    // Sobel (L1 magnitude like OpenCV's default Canny)
    final mag = Float32List(n);
    final dir = Uint8List(n);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final gx = -gray[i - w - 1] - 2 * gray[i - 1] - gray[i + w - 1] + gray[i - w + 1] + 2 * gray[i + 1] + gray[i + w + 1];
        final gy = -gray[i - w - 1] - 2 * gray[i - w] - gray[i - w + 1] + gray[i + w - 1] + 2 * gray[i + w] + gray[i + w + 1];
        mag[i] = gx.abs() + gy.abs();
        final a = math.atan2(gy, gx) * 180 / math.pi;
        final aa = a < 0 ? a + 180 : a;
        dir[i] = aa < 22.5 || aa >= 157.5 ? 0 : (aa < 67.5 ? 1 : (aa < 112.5 ? 2 : 3));
      }
    }
    // Non-maximum suppression + double threshold + hysteresis
    const lo = 75.0, hi = 200.0;
    final edge = Uint8List(n); // 0 none, 1 weak, 2 strong
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final m = mag[i];
        if (m < lo) continue;
        double a, b;
        switch (dir[i]) {
          case 0:
            a = mag[i - 1];
            b = mag[i + 1];
            break;
          case 1:
            a = mag[i - w - 1];
            b = mag[i + w + 1];
            break;
          case 2:
            a = mag[i - w];
            b = mag[i + w];
            break;
          default:
            a = mag[i - w + 1];
            b = mag[i + w - 1];
        }
        if (m >= a && m >= b) edge[i] = m >= hi ? 2 : 1;
      }
    }
    final stack = <int>[];
    for (var i = 0; i < n; i++) {
      if (edge[i] == 2) stack.add(i);
    }
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w, y = i ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          final j = yy * w + xx;
          if (edge[j] == 1) {
            edge[j] = 2;
            stack.add(j);
          }
        }
      }
    }

    // Connected components of strong edges → largest enclosed (hull) area.
    final seen = Uint8List(n);
    List<math.Point<int>>? bestHull;
    var bestArea = 0.0;
    for (var s = 0; s < n; s++) {
      if (edge[s] != 2 || seen[s] == 1) continue;
      final comp = <math.Point<int>>[];
      final st = <int>[s];
      seen[s] = 1;
      while (st.isNotEmpty) {
        final i = st.removeLast();
        final x = i % w, y = i ~/ w;
        comp.add(math.Point(x, y));
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            final j = yy * w + xx;
            if (edge[j] == 2 && seen[j] == 0) {
              seen[j] = 1;
              st.add(j);
            }
          }
        }
      }
      if (comp.length < 20) continue;
      final hull = _hull(comp);
      final area = _polyArea(hull);
      if (area > bestArea) {
        bestArea = area;
        bestHull = hull;
      }
    }
    if (bestHull == null || bestHull.length < 4) return null;

    // Best quadrilateral from hull extremes (approxPolyDP stand-in).
    math.Point<int> pick(double Function(math.Point<int>) score) =>
        bestHull!.reduce((a, b) => score(a) >= score(b) ? a : b);
    final tl = pick((p) => -(p.x + p.y).toDouble());
    final br = pick((p) => (p.x + p.y).toDouble());
    final tr = pick((p) => (p.x - p.y).toDouble());
    final bl = pick((p) => (p.y - p.x).toDouble());
    final quad = [tl, tr, br, bl];
    final qArea = _polyArea(quad);
    // Require the contour to really be quad-like and non-trivial.
    if (qArea < bestArea * 0.85 || qArea < w * h * 0.08) return null;

    // Same ordering the original applies (sort by x, then y within pairs).
    final fp = quad.map((p) => Offset(p.x / k, p.y / k)).toList()..sort((a, b) => a.dx.compareTo(b.dx));
    final left = [fp[0], fp[1]]..sort((a, b) => a.dy.compareTo(b.dy));
    final right = [fp[2], fp[3]]..sort((a, b) => a.dy.compareTo(b.dy));
    return [left[0], right[0], right[1], left[1]];
  }

  static Float32List _blur(Float32List src, int w, int h) {
    const kk = [1.0, 4.0, 6.0, 4.0, 1.0];
    final tmp = Float32List(src.length), out = Float32List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var t = -2; t <= 2; t++) {
          final xx = (x + t).clamp(0, w - 1);
          s += src[y * w + xx] * kk[t + 2];
        }
        tmp[y * w + x] = s / 16;
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var t = -2; t <= 2; t++) {
          final yy = (y + t).clamp(0, h - 1);
          s += tmp[yy * w + x] * kk[t + 2];
        }
        out[y * w + x] = s / 16;
      }
    }
    return out;
  }

  static List<math.Point<int>> _hull(List<math.Point<int>> pts) {
    final p = [...pts]..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    int cross(math.Point<int> o, math.Point<int> a, math.Point<int> b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    final lower = <math.Point<int>>[];
    for (final q in p) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
        lower.removeLast();
      }
      lower.add(q);
    }
    final upper = <math.Point<int>>[];
    for (final q in p.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
        upper.removeLast();
      }
      upper.add(q);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static double _polyArea(List<math.Point<int>> p) {
    var a = 0.0;
    for (var i = 0; i < p.length; i++) {
      final j = (i + 1) % p.length;
      a += p[i].x * p[j].y - p[j].x * p[i].y;
    }
    return a.abs() / 2;
  }
}
