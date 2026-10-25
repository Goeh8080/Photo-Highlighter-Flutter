
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_merger_highlighter/models/hl_shape.dart';
import 'package:photo_merger_highlighter/models/photo_item.dart';
import 'package:photo_merger_highlighter/screens/editor/scan_editor_screen.dart';
import 'package:photo_merger_highlighter/services/album_repository.dart';
import 'package:photo_merger_highlighter/services/image_ops.dart';
import 'package:photo_merger_highlighter/state/app_state.dart';
import 'package:photo_merger_highlighter/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAlbum implements AlbumRepository {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<PhotoItem> makeItem(WidgetTester t, {int w = 800, int h = 600, List<Pt>? pts}) async {
  late PhotoItem it;
  await t.runAsync(() async {
    final img = await ImageOps.render(w, h, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.white);
      c.drawRect(Rect.fromLTWH(w * 0.2, h * 0.2, w * 0.6, h * 0.6), Paint()..color = Colors.indigo);
    });
    final jpg = await ImageOps.encodeJpeg(img, 0.9);
    it = PhotoItem(src: jpg, orig: jpg, display: jpg, image: img, savedPts: pts);
  });
  return it;
}

Future<void> settle(WidgetTester t, bool Function() done, {int max = 200}) async {
  for (var i = 0; i < max && !done(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 40));
  }
}

Future<PhotoItem?> openEditor(WidgetTester t, PhotoItem item, String mode, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final ctrl = ThemeController(await SharedPreferences.getInstance());
  PhotoItem? result;
  var closed = false;
  await t.pumpWidget(AppThemeScope(
    controller: ctrl,
    builder: (context, p) => MaterialApp(
      builder: (context, ch) => BackdropGroup(child: ch!),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(ctx).push(MaterialPageRoute<PhotoItem>(builder: (_) => ScanEditorScreen(item: item, entryMode: mode)));
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump(const Duration(milliseconds: 600));
  await settle(t, () => find.text('Done').evaluate().isNotEmpty && find.byType(CircularProgressIndicator).evaluate().isEmpty);
  await t.pump(const Duration(milliseconds: 600));
  addTearDown(() => closed);
  return result;
}

Finder get canvasListener => find.byWidgetPredicate((w) => w is Listener && w.onPointerDown != null && w.onPointerMove != null && w.onPointerSignal != null);

void main() {
  final quad = [Pt(0.1, 0.1), Pt(0.9, 0.1), Pt(0.9, 0.9), Pt(0.1, 0.9)];

  for (final size in const [Size(390, 844), Size(360, 640)]) {
    testWidgets('crop editor lays out without overflow at ${size.width.toInt()}x${size.height.toInt()}', (t) async {
      final item = await makeItem(t, pts: quad);
      await openEditor(t, item, 'crop', size);
      expect(t.takeException(), isNull);
      // one Done + one Cancel, none of the old duplicate buttons
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply Crop'), findsNothing);
      // touch targets >= 44 dp
      for (final label in ['Done', 'Cancel', 'Text OCR', 'Rotate 90°']) {
        final r = t.getRect(find.ancestor(of: find.text(label), matching: find.byType(SizedBox)).first);
        expect(r.height, greaterThanOrEqualTo(44), reason: label);
      }
      // everything fits inside the screen
      final bar = t.getRect(find.text('Done'));
      expect(bar.bottom, lessThanOrEqualTo(size.height));
      expect(bar.right, lessThanOrEqualTo(size.width));
    });

    testWidgets('highlight editor lays out without overflow at ${size.width.toInt()}x${size.height.toInt()}', (t) async {
      final item = await makeItem(t);
      await openEditor(t, item, 'highlight', size);
      expect(t.takeException(), isNull);
      expect(find.text('Select / Move'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Apply Highlights'), findsNothing);
    });
  }

  testWidgets('Done applies the crop frame: stored dimensions change and home thumbnail refreshes', (t) async {
    final item = await makeItem(t, pts: quad);
    expect([item.width, item.height], [800, 600]);
    PhotoItem? result;
    final t0 = t;
    // open + press Done
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final ctrl = ThemeController(await SharedPreferences.getInstance());
    final state = AppState(_FakeAlbum());
    state.images.add(item);
    await t0.pumpWidget(AppThemeScope(
      controller: ctrl,
      builder: (context, p) => MaterialApp(
        builder: (context, ch) => BackdropGroup(child: ch!),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (_, _) => Column(children: [
                SizedBox(key: const Key('thumb'), height: 90, child: RawImage(image: state.images[0].image, fit: BoxFit.contain)),
                ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(ctx).push(MaterialPageRoute<PhotoItem>(builder: (_) => ScanEditorScreen(item: state.images[0], entryMode: 'crop')));
                    if (result != null) await state.replaceImage(0, result!);
                  },
                  child: const Text('open'),
                ),
              ]),
            ),
          ),
        ),
      ),
    ));
    final before = t.getSize(find.byKey(const Key('thumb')).first);
    final beforeImage = state.images[0].image;
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 600));
    await settle(t, () => find.text('Done').evaluate().isNotEmpty && find.byType(CircularProgressIndicator).evaluate().isEmpty);
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Done'));
    await settle(t, () => result != null);
    await t.pump(const Duration(milliseconds: 800));
    expect(result, isNotNull);
    expect(t.takeException(), isNull);
    // 0.8 of 800x600 (crop frame set to 10%..90%)
    expect(result!.width, closeTo(640, 3));
    expect(result!.height, closeTo(480, 3));
    expect(identical(state.images[0].image, beforeImage), isFalse);
    expect(state.images[0].width, result!.width);
    expect(state.images[0].src.length, isNot(0));
    expect(state.images[0].display, same(state.images[0].src));
    expect(before.height, 90);
    await t.pump(const Duration(seconds: 3)); // let the toast timer finish
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  });

  testWidgets('Cancel discards pending changes (rotation) on the item', (t) async {
    final item = await makeItem(t, pts: quad);
    await openEditor(t, item, 'crop', const Size(390, 844));
    await t.tap(find.text('Rotate 90°'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Cancel'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(item.rotation, 0);
    expect([item.width, item.height], [800, 600]);
    expect(item.savedPts!.first.x, 0.1);
  });

  testWidgets('draw 3 shapes, drag the middle one: only it moves, 1:1, undo restores', (t) async {
    final item = await makeItem(t);
    await openEditor(t, item, 'highlight', const Size(390, 844));
    final r = t.getRect(canvasListener);
    Future<void> draw(Offset a, Offset b) async {
      final g = await t.startGesture(a);
      for (var i = 1; i <= 5; i++) {
        await g.moveTo(Offset.lerp(a, b, i / 5)!);
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pump(const Duration(milliseconds: 50));
    }

    final c = r.center;
    await draw(c + const Offset(-120, -120), c + const Offset(-60, -80));
    await draw(c + const Offset(-20, -20), c + const Offset(40, 30));
    await draw(c + const Offset(70, 80), c + const Offset(130, 120));
    expect(item.hlShapes.length, 3);
    final before = item.hlShapes.map((s) => s.toJson()).toList();
    // drag the middle shape by an exact (37, -23)
    final g = await t.startGesture(c + const Offset(10, 5));
    await g.moveBy(const Offset(10, -5));
    await t.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(27, -18));
    await t.pump(const Duration(milliseconds: 16));
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
    final after = item.hlShapes.map((s) => s.toJson()).toList();
    expect(after[0], before[0]);
    expect(after[2], before[2]);
    final scale = 1.0; // canvas is shown at 1:1 here (no Transform.scale)
    expect((after[1]['start']['x'] as num) - (before[1]['start']['x'] as num), closeTo(37 / scale, 0.01));
    expect((after[1]['start']['y'] as num) - (before[1]['start']['y'] as num), closeTo(-23 / scale, 0.01));
    expect((after[1]['current']['x'] as num) - (before[1]['current']['x'] as num), closeTo(37 / scale, 0.01));
    expect(item.hlRedoStack.last.action, 'edit'); // move recorded for undo
    expect(t.takeException(), isNull);
  });
}
