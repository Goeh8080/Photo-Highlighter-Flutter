import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/hl_shape.dart';
import '../models/photo_item.dart';
import 'platform.dart';

/// Pixel/canvas operations that replace the original HTML <canvas> code
/// (and OpenCV's warpPerspective) with dart:ui.
class ImageOps {
  static Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final f = await codec.getNextFrame();
    return f.image;
  }

  static Future<Uint8List> rgba(ui.Image img) async {
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bd!.buffer.asUint8List();
  }

  static Future<ui.Image> fromRgba(Uint8List px, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  static Future<Uint8List> encodeJpeg(ui.Image img, double q) async =>
      encodeJpegPlatform(await rgba(img), img.width, img.height, q);

  static Future<ui.Image> render(int w, int h, void Function(Canvas c) paint) async {
    try {
      return await _renderScaled(w, h, 1, paint);
    } catch (_) {
      // GPU surfaces have a max texture size (8192 on many WebGL/mobile GPUs).
      // The HTML canvas would silently fail/blank here; we retry scaled down
      // so very wide merges (e.g. many PDF pages side by side) still work.
      for (final cap in const [8192, 4096]) {
        final k = cap / math.max(w, h);
        if (k >= 1) continue;
        try {
          return await _renderScaled(math.max(1, (w * k).floor()), math.max(1, (h * k).floor()), k, paint);
        } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<ui.Image> _renderScaled(int w, int h, double k, void Function(Canvas c) paint) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    if (k != 1) c.scale(k);
    paint(c);
    final pic = rec.endRecording();
    try {
      return await pic.toImage(w, h);
    } finally {
      pic.dispose();
    }
  }

  static final _hq = Paint()
    ..filterQuality = FilterQuality.high
    ..isAntiAlias = true;

  static void drawImageTo(Canvas c, ui.Image img, Rect dst, [Paint? p]) => c.drawImageRect(
      img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, p ?? _hq);

  /// `load(f)`: images larger than 3200px are downscaled to 2800px JPEG 0.92.
  static Future<(Uint8List, ui.Image)> loadUpload(Uint8List bytes) async {
    final im = await decode(bytes);
    if (im.width > 3200 || im.height > 3200) {
      final scale = 2800 / math.max(im.width, im.height);
      final w = (im.width * scale).round(), h = (im.height * scale).round();
      final out = await render(w, h, (c) => drawImageTo(c, im, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())));
      final jpg = await encodeJpeg(out, 0.92);
      im.dispose();
      return (jpg, out);
    }
    return (bytes, im);
  }

  /// Port of `merge()`. Returns the merged image.
  static Future<ui.Image> merge({
    required List<PhotoItem> images,
    required String mode,
    required String gridType,
    required int bw,
    required double resScale,
  }) async {
    var effRes = resScale;
    if (images.length == 2) {
      effRes = math.min(effRes, 0.7);
    } else if (images.length == 4) {
      effRes = math.min(effRes, 0.9);
    }
    final targetDim = 1800 * effRes;
    final black = Paint()..color = const Color(0xFF000000);

    if (mode == 'horizontal') {
      final baseH = math.min(targetDim, images.map((i) => i.height).reduce(math.max).toDouble());
      var w = 0.0;
      for (final i in images) {
        w += i.width * baseH / i.height;
      }
      final cw = (w + bw * (images.length + 1)).toInt(), ch = (baseH + bw * 2).toInt();
      return render(cw, ch, (c) {
        c.drawRect(Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()), black);
        var x = bw.toDouble();
        for (final i in images) {
          final iw = i.width * baseH / i.height;
          drawImageTo(c, i.image, Rect.fromLTWH(x, bw.toDouble(), iw, baseH));
          x += iw + bw;
        }
      });
    } else if (mode == 'vertical') {
      final baseW = math.min(targetDim, images.map((i) => i.width).reduce(math.max).toDouble());
      var h = 0.0;
      for (final i in images) {
        h += i.height * baseW / i.width;
      }
      final cw = (baseW + bw * 2).toInt(), ch = (h + bw * (images.length + 1)).toInt();
      return render(cw, ch, (c) {
        c.drawRect(Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()), black);
        var y = bw.toDouble();
        for (final i in images) {
          final ih = i.height * baseW / i.width;
          drawImageTo(c, i.image, Rect.fromLTWH(bw.toDouble(), y, baseW, ih));
          y += ih + bw;
        }
      });
    }

    // Grid layout
    final count = images.length;
    List<int> layout;
    if (gridType != 'auto' && gridType.contains('+')) {
      layout = gridType.split('+').map(int.parse).toList();
    } else if (gridType != 'auto' && gridType.contains('x')) {
      final parts = gridType.split('x');
      layout = List.filled(int.parse(parts[1]), int.parse(parts[0]));
    } else {
      const auto = {3: [1, 2], 5: [3, 2], 7: [4, 3], 1: [1], 2: [2], 4: [2, 2], 6: [3, 3], 8: [4, 4], 9: [3, 3, 3]};
      if (auto.containsKey(count)) {
        layout = auto[count]!;
      } else {
        final cols = math.sqrt(count).ceil();
        final rows = (count / cols).ceil();
        layout = List.filled(rows, cols);
      }
    }
    final rowHeights = <double>[];
    var idx = 0;
    for (final cols in layout) {
      final cellW = targetDim / cols;
      var maxH = 0.0;
      for (var c = 0; c < cols; c++) {
        if (idx < count) {
          final h = cellW * images[idx].height / images[idx].width;
          if (h > maxH) maxH = h;
          idx++;
        }
      }
      rowHeights.add(maxH == 0 ? cellW : maxH);
    }
    final cw = (targetDim + bw * 2).toInt();
    final ch = (rowHeights.fold<double>(0, (a, b) => a + b) + (layout.length + 1) * bw).toInt();
    return render(cw, ch, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()), black);
      var curY = bw.toDouble();
      var i = 0;
      for (var r = 0; r < layout.length; r++) {
        final cols = layout[r];
        final cellW = (targetDim - (cols - 1) * bw) / cols;
        var curX = bw.toDouble();
        for (var k = 0; k < cols; k++) {
          if (i < count) {
            drawImageTo(c, images[i].image, Rect.fromLTWH(curX, curY, cellW, rowHeights[r]));
            curX += cellW + bw;
            i++;
          }
        }
        curY += rowHeights[r] + bw;
      }
    });
  }

  /// `applyPhotoCopyScan()` pixel filter (photocopy look).
  static Future<ui.Image> photocopyScan(ui.Image src) async {
    final d = await rgba(src);
    for (var i = 0; i < d.length; i += 4) {
      final avg = d[i] * 0.3 + d[i + 1] * 0.59 + d[i + 2] * 0.11;
      final v = (avg < 120 ? math.max(0, avg - 30) : math.min(255, avg + 40)).toInt();
      d[i] = v;
      d[i + 1] = v;
      d[i + 2] = v;
    }
    return fromRgba(d, src.width, src.height);
  }

  // ---------- CSS filter() equivalents as 4x5 colour matrices ----------

  /// Returns a∘b (apply b first, then a).
  static List<double> _mul(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var s = c == 4 ? a[r * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          s += a[r * 5 + k] * b[k * 5 + c];
        }
        out[r * 5 + c] = s;
      }
    }
    return out;
  }

  static List<double> _hueRotate(double deg) {
    final a = deg * math.pi / 180, c = math.cos(a), s = math.sin(a);
    return [
      0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
      0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
      0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _saturate(double s) => [
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
        0, 0, 0, 1, 0,
      ];

  static List<double> _brightness(double b) => [b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];

  static List<double> _contrast(double c) {
    final o = (0.5 - 0.5 * c) * 255;
    return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0];
  }

  static List<double> _grayscale(double g) {
    final a = 1 - g;
    return [
      0.2126 + 0.7874 * a, 0.7152 - 0.7152 * a, 0.0722 - 0.0722 * a, 0, 0,
      0.2126 - 0.2126 * a, 0.7152 + 0.2848 * a, 0.0722 - 0.0722 * a, 0, 0,
      0.2126 - 0.2126 * a, 0.7152 - 0.7152 * a, 0.0722 + 0.9278 * a, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  /// filter: hue-rotate() saturate() brightness() contrast() [grayscale()]
  static List<double> adjustMatrix(AdjSettings s) {
    var effSat = s.sat, effBright = s.bright, effContrast = s.contrast;
    if (s.colorScan != 0) {
      effSat += (s.colorScan * 0.8).round();
      effBright += (s.colorScan * 0.3).round();
      effContrast += (s.colorScan * 0.6).round();
    }
    var m = _hueRotate(s.hue.toDouble());
    m = _mul(_saturate(math.max(0, 100 + effSat) / 100), m);
    m = _mul(_brightness(math.max(0, 100 + effBright) / 100), m);
    m = _mul(_contrast(math.max(0, 100 + effContrast) / 100), m);
    if (s.bwScan != 0) {
      var gr = math.min(100, math.max(0, 50 + s.bwScan * 0.5)).toDouble();
      if (s.bwScan > 0) gr = 100;
      m = _mul(_grayscale(gr / 100), m);
    }
    return m;
  }

  /// `previewLiveAdjustments()` / apply: colour matrix + B&W threshold pass.
  static Future<ui.Image> adjust(ui.Image base, AdjSettings s, {int? maxDim}) async {
    var w = base.width, h = base.height;
    if (maxDim != null && math.max(w, h) > maxDim) {
      final k = maxDim / math.max(w, h);
      w = (w * k).round();
      h = (h * k).round();
    }
    final p = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.matrix(adjustMatrix(s));
    var out = await render(w, h, (c) => drawImageTo(c, base, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), p));
    if (s.bwScan != 0) {
      final d = await rgba(out);
      final thr = 128 - s.bwScan * 0.5;
      for (var i = 0; i < d.length; i += 4) {
        final avg = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
        double v;
        if (s.bwScan > 0) {
          v = avg > thr ? math.min(255, avg * (1 + s.bwScan * 0.005)) : math.max(0, avg * (1 - s.bwScan * 0.005));
        } else {
          v = avg;
        }
        final iv = v.toInt().clamp(0, 255);
        d[i] = iv;
        d[i + 1] = iv;
        d[i + 2] = iv;
      }
      out.dispose();
      out = await fromRgba(d, w, h);
    }
    return out;
  }

  /// Draws [img] rotated by [rotation] degrees into a (possibly swapped) frame.
  static Future<ui.Image> rotated(ui.Image img, int rotation) async {
    if (rotation % 360 == 0) return img;
    final isRot = (rotation ~/ 90) % 2 != 0;
    final w = isRot ? img.height : img.width;
    final h = isRot ? img.width : img.height;
    return render(w, h, (c) {
      c.translate(w / 2, h / 2);
      c.rotate(rotation * math.pi / 180);
      drawImageTo(c, img, Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(), img.height.toDouble()));
    });
  }

  /// `applyCanvasSizeChange()`: expand/shrink canvas with a white fill.
  static Future<ui.Image> resizeCanvas(ui.Image img, double dw, double dh) {
    final newW = math.max(10, (img.width + dw).round());
    final newH = math.max(10, (img.height + dh).round());
    return render(newW, newH, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
      c.drawImage(img, Offset((newW - img.width) / 2, (newH - img.height) / 2), _hq);
    });
  }

  /// Perspective crop (OpenCV getPerspectiveTransform + warpPerspective).
  /// Implemented as a GPU textured mesh: a 32×32 grid of triangles whose
  /// texture coordinates come from the exact homography.
  static Future<ui.Image> perspectiveWarp(ui.Image src, List<Offset> quad, int newW, int newH) async {
    final hm = _homography(
      [const Offset(0, 0), Offset(newW.toDouble(), 0), Offset(newW.toDouble(), newH.toDouble()), Offset(0, newH.toDouble())],
      quad,
    );
    Offset map(double x, double y) {
      final d = hm[6] * x + hm[7] * y + 1;
      return Offset((hm[0] * x + hm[1] * y + hm[2]) / d, (hm[3] * x + hm[4] * y + hm[5]) / d);
    }

    const n = 32;
    final pos = <Offset>[], tex = <Offset>[];
    final idx = <int>[];
    for (var j = 0; j <= n; j++) {
      for (var i = 0; i <= n; i++) {
        final x = newW * i / n, y = newH * j / n;
        pos.add(Offset(x, y));
        tex.add(map(x, y));
      }
    }
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final a = j * (n + 1) + i, b = a + 1, c = a + n + 1, d = c + 1;
        idx.addAll([a, b, d, a, d, c]);
      }
    }
    final verts = ui.Vertices(ui.VertexMode.triangles, pos, textureCoordinates: tex, indices: idx);
    final shader = ImageShader(src, TileMode.clamp, TileMode.clamp, Float64List.fromList(const [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]), filterQuality: FilterQuality.high);
    final out = await render(newW, newH, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()), Paint()..color = const Color(0xFF000000));
      c.drawVertices(verts, BlendMode.srcOver, Paint()..shader = shader);
    });
    verts.dispose();
    return out;
  }

  /// Solve the 3x3 homography mapping [from] → [to] (h33 = 1).
  static List<double> _homography(List<Offset> from, List<Offset> to) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = from[i].dx, y = from[i].dy, u = to[i].dx, v = to[i].dy;
      a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }
    for (var c = 0; c < 8; c++) {
      var piv = c;
      for (var r = c + 1; r < 8; r++) {
        if (a[r][c].abs() > a[piv][c].abs()) piv = r;
      }
      final t = a[c];
      a[c] = a[piv];
      a[piv] = t;
      final pv = a[c][c];
      if (pv.abs() < 1e-12) continue;
      for (var k = c; k < 9; k++) {
        a[c][k] /= pv;
      }
      for (var r = 0; r < 8; r++) {
        if (r == c) continue;
        final f = a[r][c];
        if (f == 0) continue;
        for (var k = c; k < 9; k++) {
          a[r][k] -= f * a[c][k];
        }
      }
    }
    return [for (var i = 0; i < 8; i++) a[i][8]];
  }
}

