import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_merger_highlighter/models/hl_shape.dart';
import 'package:photo_merger_highlighter/screens/editor/layer_drag.dart';
import 'package:photo_merger_highlighter/screens/editor/scan_painter.dart';
import 'package:photo_merger_highlighter/services/image_ops.dart';
import 'package:photo_merger_highlighter/services/ocr_text.dart';

List<HlShape> threeShapes() => [
      HlShape(type: 'rect', color: 0xFFFFFF00, start: Pt(-120, -60), current: Pt(-60, 0), thickness: 1),
      HlShape(type: 'oval', color: 0xFF00FF00, start: Pt(-30, -30), current: Pt(40, 30), thickness: 1),
      HlShape(type: 'free', color: 0xFFFF0000, thickness: 6, pts: [for (var i = 0; i < 50; i++) Pt(60 + i * 1.0, 40 + math.sin(i / 5) * 10)]),
    ];

List<Map<String, dynamic>> snap(List<HlShape> s) => s.map((e) => e.toJson()).toList();

void main() {
  group('LayerDrag: 1:1 move of one layer', () {
    test('position equals the pointer delta exactly, others untouched', () {
      final shapes = threeShapes();
      final before = snap(shapes);
      final d = LayerDrag(1, shapes[1], Pt(0, 0));
      var x = 0.0, y = 0.0;
      final rnd = math.Random(7);
      for (var i = 0; i < 500; i++) {
        x += rnd.nextDouble() * 6 - 3;
        y += rnd.nextDouble() * 6 - 3;
        d.update(Pt(x, y));
      }
      expect(shapes[1].start!.x, before[1]['start']['x'] + x);
      expect(shapes[1].start!.y, before[1]['start']['y'] + y);
      expect(shapes[1].current!.x, before[1]['current']['x'] + x);
      expect(shapes[1].current!.y, before[1]['current']['y'] + y);
      expect(snap(shapes)[0], before[0]);
      expect(snap(shapes)[2], before[2]);
      expect(d.moved, isTrue);
      // size unchanged (pure translation)
      expect(shapes[1].current!.x - shapes[1].start!.x, 70);
    });

    test('freehand moves every point by the same delta', () {
      final shapes = threeShapes();
      final orig = shapes[2].pts!.map((p) => Pt(p.x, p.y)).toList();
      final d = LayerDrag(2, shapes[2], Pt(100, 100));
      d.update(Pt(113.5, 92.25));
      for (var i = 0; i < orig.length; i++) {
        expect(shapes[2].pts![i].x, orig[i].x + 13.5);
        expect(shapes[2].pts![i].y, orig[i].y - 7.75);
      }
    });

    test('a tap (no movement) is not a move; undo snapshot restores the layer', () {
      final shapes = threeShapes();
      final d = LayerDrag(0, shapes[0], Pt(5, 5));
      d.update(Pt(5, 5));
      expect(d.moved, isFalse);
      d.update(Pt(50, 20));
      expect(d.moved, isTrue);
      // history entry = clone at pointer-down; undo replaces the layer with it
      final entry = HistoryEntry('edit', index: 0, shape: d.before);
      shapes[entry.index!] = entry.shape!.clone();
      expect(shapes[0].start!.x, -120);
      expect(shapes[0].current!.y, 0);
    });

    test('dragging back to the start returns the exact original position', () {
      final shapes = threeShapes();
      final b = snap(shapes);
      final d = LayerDrag(2, shapes[2], Pt(0, 0));
      d.update(Pt(33.3, -12.7));
      d.update(Pt(0, 0));
      expect(snap(shapes), b);
    });
  });

  group('hit test', () {
    test('thin free line is hit within the 24px slop only', () {
      final s = HlShape(type: 'free_straight', color: 0xFF000000, thickness: 2, start: Pt(0, 0), current: Pt(200, 0));
      expect(s.hitTest(Pt(100, 20), 24), isTrue);
      expect(s.hitTest(Pt(100, 40), 24), isFalse);
      expect(s.hitTest(Pt(230, 0), 24), isFalse);
    });
    test('top-most layer wins; empty space is -1', () {
      final shapes = [
        HlShape(type: 'rect', color: 1, start: Pt(0, 0), current: Pt(100, 100), thickness: 1),
        HlShape(type: 'rect', color: 2, start: Pt(50, 50), current: Pt(150, 150), thickness: 1),
      ];
      expect(hitTopLayer(shapes, Pt(75, 75), 8), 1);
      expect(hitTopLayer(shapes, Pt(10, 10), 8), 0);
      expect(hitTopLayer(shapes, Pt(400, 400), 8), -1);
    });
    test('diagonal freehand does not steal taps through its bounding box', () {
      final s = HlShape(type: 'free', color: 1, thickness: 4, pts: [Pt(0, 0), Pt(100, 100)]);
      expect(s.hitTest(Pt(10, 90), 24), isFalse);
      expect(s.hitTest(Pt(52, 48), 24), isTrue);
    });
    test('rotated text is hit in its own frame', () {
      final s = HlShape(type: 'text', color: 1, start: Pt(0, 0), current: Pt(100, 30), textValue: 'Hello', fontSize: 16, angle: 90);
      expect(s.hitTest(s.center(), 4), isTrue);
    });
  });

  group('OCR text helpers', () {
    test('words are grouped into ordered lines (tesseract style)', () {
      final w = [
        {'text': 'world', 'x0': 60.0, 'y0': 10.0, 'x1': 100.0, 'y1': 30.0},
        {'text': 'Hello', 'x0': 0.0, 'y0': 12.0, 'x1': 50.0, 'y1': 32.0},
        {'text': 'नमस्ते', 'x0': 0.0, 'y0': 60.0, 'x1': 50.0, 'y1': 80.0},
      ];
      expect(ocrTextFromWords(w), 'Hello world\nनमस्ते');
    });
    test('ML Kit line indices are honoured', () {
      final w = [
        {'text': 'b', 'x0': 20.0, 'y0': 0.0, 'x1': 30.0, 'y1': 10.0, 'line': 1},
        {'text': 'a', 'x0': 0.0, 'y0': 0.0, 'x1': 10.0, 'y1': 10.0, 'line': 1},
        {'text': 'c', 'x0': 0.0, 'y0': 40.0, 'x1': 10.0, 'y1': 50.0, 'line': 2},
      ];
      expect(ocrTextFromWords(w), 'a b\nc');
      expect(ocrTextFromWords([]), '');
    });
    test('text layer fits inside the canvas', () {
      final l = ocrTextLayer('lorem ipsum ' * 40, 360, 480, 0xFF000000);
      expect(l.type, 'text');
      expect(l.start!.x, greaterThanOrEqualTo(-180));
      expect(l.current!.y, lessThanOrEqualTo(240));
      expect(l.textValue!.split('\n').every((s) => s.length <= 44), isTrue);
    });
  });

  group('renderer', () {
    testWidgets('cached drag render is pixel-identical to a full render', (t) async {
      await t.runAsync(() async {
        Future<Uint8List> render(ShapeCache? c, List<HlShape> sh) async {
          final img = await ImageOps.render(300, 200, (cv) {
            cv.drawRect(const Rect.fromLTWH(0, 0, 300, 200), Paint()..color = Colors.white);
            cv.translate(150, 100);
            HighlightRenderer.paintAll(cv, sh, cache: c);
          });
          return ImageOps.rgba(img);
        }

        final shapes = threeShapes();
        final cache = ShapeCache(shapes, 1);
        final d = LayerDrag(1, shapes[1], Pt(0, 0));
        d.update(Pt(17, -9));
        final a = await render(cache, shapes);
        final b = await render(null, shapes);
        expect(a, b);
        cache.dispose();
      });
    });

    test('perf: per-frame cost of repainting while dragging (cached vs uncached)', () {
      // ~30 layers incl. 4 freehand strokes of 2000 points and text.
      final shapes = <HlShape>[
        for (var i = 0; i < 22; i++)
          HlShape(type: i.isEven ? 'rect' : 'oval', color: 0xFFFFFF00, thickness: 1, start: Pt(-150 + i * 5.0, -200 + i * 9.0), current: Pt(-50 + i * 5.0, -120 + i * 9.0)),
        for (var k = 0; k < 4; k++) HlShape(type: 'free', color: 0xFFFF0000, thickness: 6, pts: [for (var i = 0; i < 2000; i++) Pt(-150 + i * 0.15, k * 40 + math.sin(i / 20) * 30)]),
        for (var k = 0; k < 4; k++) HlShape(type: 'text', color: 0xFF000000, start: Pt(-140, -220 + k * 50.0), current: Pt(140, -190 + k * 50.0), textValue: 'Layer text line $k\nsecond line', fontSize: 18),
      ];
      const moving = 10;
      const frames = 300;
      double run(bool cached) {
        final cache = cached ? ShapeCache(shapes, moving) : null;
        final sw = Stopwatch()..start();
        for (var f = 0; f < frames; f++) {
          // what a drag frame does: move one layer, then record the scene
          shapes[moving].start!.x += 0.5;
          shapes[moving].current!.x += 0.5;
          final rec = ui.PictureRecorder();
          final c = Canvas(rec);
          HighlightRenderer.paintAll(c, shapes, cache: cache);
          rec.endRecording().dispose();
        }
        sw.stop();
        cache?.dispose();
        return sw.elapsedMicroseconds / frames / 1000;
      }

      run(false); // warm-up
      run(true);
      final full = run(false);
      final cached = run(true);
      // ignore: avoid_print
      print('PERF record+paint per frame (30 layers, 8000 stroke pts): full=${full.toStringAsFixed(3)} ms, cached=${cached.toStringAsFixed(3)} ms, speedup=${(full / cached).toStringAsFixed(1)}x');
      expect(cached, lessThan(full));
    });
  });

  group('raster', () {
    testWidgets('perf: rasterised frame time while dragging (software rasteriser, 720x960)', (t) async {
      await t.runAsync(() async {
        final shapes = <HlShape>[
          for (var i = 0; i < 22; i++)
            HlShape(type: i.isEven ? 'rect' : 'oval', color: 0xFFFFFF00, thickness: 1, start: Pt(-150 + i * 5.0, -200 + i * 9.0), current: Pt(-50 + i * 5.0, -120 + i * 9.0)),
          for (var k = 0; k < 4; k++) HlShape(type: 'free', color: 0xFFFF0000, thickness: 6, pts: [for (var i = 0; i < 2000; i++) Pt(-150 + i * 0.15, k * 40 + math.sin(i / 20) * 30)]),
          for (var k = 0; k < 4; k++) HlShape(type: 'text', color: 0xFF000000, start: Pt(-140, -220 + k * 50.0), current: Pt(140, -190 + k * 50.0), textValue: 'Layer text line $k\nsecond line', fontSize: 18),
        ];
        Future<double> run(bool cached) async {
          final cache = cached ? ShapeCache(shapes, 10) : null;
          final sw = Stopwatch()..start();
          const n = 20;
          for (var f = 0; f < n; f++) {
            shapes[10].start!.x += 0.5;
            shapes[10].current!.x += 0.5;
            final rec = ui.PictureRecorder();
            final c = Canvas(rec);
            c.translate(360, 480);
            c.scale(2);
            HighlightRenderer.paintAll(c, shapes, cache: cache);
            final pic = rec.endRecording();
            final im = await pic.toImage(720, 960);
            im.dispose();
            pic.dispose();
          }
          cache?.dispose();
          return sw.elapsedMicroseconds / n / 1000;
        }

        await run(false);
        final full = await run(false);
        final cached = await run(true);
        // ignore: avoid_print
        print('PERF rasterised frame (software): full=${full.toStringAsFixed(2)} ms, cached=${cached.toStringAsFixed(2)} ms');
      });
    });
  });

  group('CPU perspective warp', () {
    testWidgets('identity quad reproduces the image; arbitrary quad gives requested size', (t) async {
      await t.runAsync(() async {
        final src = await ImageOps.render(120, 80, (c) {
          c.drawRect(const Rect.fromLTWH(0, 0, 120, 80), Paint()..color = Colors.blue);
          c.drawRect(const Rect.fromLTWH(10, 10, 40, 30), Paint()..color = Colors.red);
        });
        final id = await ImageOps.perspectiveWarpCpu(src, const [Offset(0, 0), Offset(120, 0), Offset(120, 80), Offset(0, 80)], 120, 80);
        final a = await ImageOps.rgba(src), b = await ImageOps.rgba(id);
        var maxDiff = 0;
        for (var i = 0; i < a.length; i++) {
          maxDiff = math.max(maxDiff, (a[i] - b[i]).abs());
        }
        expect(maxDiff, lessThanOrEqualTo(2));
        final crop = await ImageOps.perspectiveWarpCpu(src, const [Offset(10, 10), Offset(50, 10), Offset(50, 40), Offset(10, 40)], 40, 30);
        expect([crop.width, crop.height], [40, 30]);
        final px = await ImageOps.rgba(crop);
        expect(px[0], greaterThan(200)); // red region only
        expect(px[2], lessThan(60));
      });
    });
  });
}
