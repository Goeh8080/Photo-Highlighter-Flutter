import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_merger_highlighter/models/constants.dart';
import 'package:photo_merger_highlighter/models/hl_shape.dart';
import 'package:photo_merger_highlighter/models/photo_item.dart';
import 'package:photo_merger_highlighter/services/edge_detector.dart';
import 'package:photo_merger_highlighter/services/image_ops.dart';
import 'package:photo_merger_highlighter/theme/app_theme.dart';

Future<ui.Image> solid(int w, int h, Color c) => ImageOps.render(w, h, (cv) => cv.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = c));

PhotoItem item(ui.Image img) => PhotoItem(src: Uint8List(0), orig: Uint8List(0), display: Uint8List(0), image: img);

void main() {
  group('constants', () {
    test('all 77 grid layouts of the HTML are ported', () => expect(allGridOptions.length, 77));
    test('quality presets match HTML', () => expect(qualityPresets.length, 5));
    test('white detection', () {
      expect(isWhiteColor(0xFFFFFFFF), isTrue);
      expect(isWhiteColor(0xFFFFFF00), isFalse);
    });
  });

  group('HlShape', () {
    test('translate, scale and json round-trip', () {
      final s = HlShape(type: 'rect', color: 0xFFFFFF00, start: Pt(10, 10), current: Pt(30, 20), thickness: 8);
      s.translate(5, 5);
      expect(s.bounds().take(2).toList(), [15, 15]);
      s.scaleBy(2);
      expect(s.start!.x, 30);
      expect(s.thickness, 16);
      final c = HlShape.fromJson(s.toJson());
      expect(c.toJson(), s.toJson());
      expect(s.handles().length, 8);
    });
    test('freehand translate moves all points', () {
      final s = HlShape(type: 'free', color: 0xFF000000, pts: [Pt(0, 0), Pt(10, 10)]);
      s.translate(1, 2);
      expect(s.pts!.last.x, 11);
      expect(s.pts!.last.y, 12);
    });
  });

  test('palette lerp end-points equal the CSS themes', () {
    expect(AppPalette.lerp(AppPalette.light, AppPalette.dark, 1).bgMain, AppPalette.dark.bgMain);
    expect(AppPalette.lerp(AppPalette.light, AppPalette.dark, 0).bgMain, AppPalette.light.bgMain);
    expect(AppPalette.lerp(AppPalette.light, AppPalette.dark, 0.5).darkness, 0.5);
  });

  testWidgets('merge sizes follow the HTML formulae', (t) async {
    await t.runAsync(() async {
      final a = await solid(400, 200, Colors.red), b = await solid(200, 200, Colors.blue);
      final h = await ImageOps.merge(images: [item(a), item(b)], mode: 'horizontal', gridType: 'auto', bw: 2, resScale: 1);
      // baseH=min(1800*0.7,200)=200 → w=400+200, + 3 borders
      expect(h.width, 606);
      expect(h.height, 204);
      final v = await ImageOps.merge(images: [item(a), item(b)], mode: 'vertical', gridType: 'auto', bw: 0, resScale: 1);
      expect(v.width, 400);
      expect(v.height, 200 + 400);
      final g = await ImageOps.merge(images: [item(a), item(b), item(b)], mode: 'grid', gridType: '1+2', bw: 0, resScale: 1);
      expect(g.width > 0 && g.height > 0, isTrue);
    });
  });

  testWidgets('perspective warp + rotate + canvas resize', (t) async {
    await t.runAsync(() async {
      final a = await solid(300, 200, Colors.green);
      final w = await ImageOps.perspectiveWarp(a, const [Offset(10, 10), Offset(290, 20), Offset(280, 190), Offset(20, 180)], 260, 160);
      expect([w.width, w.height], [260, 160]);
      final r = await ImageOps.rotated(a, 90);
      expect([r.width, r.height], [200, 300]);
      final c = await ImageOps.resizeCanvas(a, 200, 200);
      expect([c.width, c.height], [500, 400]);
      final px = await ImageOps.rgba(c);
      // corner is white fill (as in the HTML canvas-size tool)
      expect(px.sublist(0, 3), [255, 255, 255]);
    });
  });

  testWidgets('edge detector finds a paper quad on a dark background', (t) async {
    await t.runAsync(() async {
      final img = await ImageOps.render(400, 500, (c) {
        c.drawRect(const Rect.fromLTWH(0, 0, 400, 500), Paint()..color = const Color(0xFF3A2A1E));
        c.drawPath(Path()..moveTo(60, 70)..lineTo(340, 50)..lineTo(350, 450)..lineTo(50, 460)..close(), Paint()..color = const Color(0xFFF5F3EE));
      });
      final q = await EdgeDetector.detect(img);
      expect(q, isNotNull);
      expect(q!.length, 4);
      final xs = q.map((o) => o.dx).toList()..sort();
      expect(xs.first, closeTo(55, 20));
      expect(xs.last, closeTo(345, 20));
    });
  });

  testWidgets('photocopy scan + adjustments keep size', (t) async {
    await t.runAsync(() async {
      final a = await solid(120, 80, Colors.orange);
      final s = await ImageOps.photocopyScan(a);
      expect([s.width, s.height], [120, 80]);
      final adj = await ImageOps.adjust(a, AdjSettings()..bwScan = 1);
      final px = await ImageOps.rgba(adj);
      expect(px[0], px[1]); // grayscale / threshold
    });
  });
}
