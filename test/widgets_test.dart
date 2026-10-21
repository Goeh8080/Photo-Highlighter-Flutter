import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_merger_highlighter/theme/app_theme.dart';
import 'package:photo_merger_highlighter/widgets/glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ThemeController> ctrl() async {
  SharedPreferences.setMockInitialValues({});
  return ThemeController(await SharedPreferences.getInstance());
}

Widget host(ThemeController c, Widget child) => AppThemeScope(
      controller: c,
      builder: (context, p) => MaterialApp(
        builder: (context, ch) => BackdropGroup(child: ch!),
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('GlassButton fires onTap and springs back', (t) async {
    final c = await ctrl();
    var taps = 0;
    await t.pumpWidget(host(c, GlassButton(label: 'Merge', color: AppColors.green, onTap: () => taps++)));
    final g = await t.startGesture(t.getCenter(find.text('Merge')));
    await t.pump(const Duration(milliseconds: 120));
    await t.pump(const Duration(milliseconds: 60));
    final tr = t.widget<Transform>(find.ancestor(of: find.text('Merge'), matching: find.byType(Transform)).first);
    expect(tr.transform.entry(1, 1), lessThan(1.0)); // squished while held
    await g.up();
    await t.pumpAndSettle();
    expect(taps, 1);
    final tr2 = t.widget<Transform>(find.ancestor(of: find.text('Merge'), matching: find.byType(Transform)).first);
    expect(tr2.transform.entry(1, 1), closeTo(1.0, 0.01)); // settled
  });

  testWidgets('GlassSegmented switches value and slides indicator', (t) async {
    final c = await ctrl();
    var v = 'horizontal';
    await t.pumpWidget(host(
        c,
        StatefulBuilder(
          builder: (ctx, set) => SizedBox(
            width: 300,
            child: GlassSegmented<String>(values: const ['horizontal', 'vertical', 'grid'], selected: v, labelOf: (e) => e, onChanged: (e) => set(() => v = e)),
          ),
        )));
    double left() => t.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left!;
    expect(left(), 0);
    await t.tap(find.text('grid'));
    await t.pumpAndSettle();
    expect(v, 'grid');
    expect(left(), greaterThan(150));
  });

  testWidgets('theme toggle persists and cross-fades', (t) async {
    final c = await ctrl();
    await t.pumpWidget(host(c, Builder(builder: (ctx) => Text('x', style: TextStyle(color: AppThemeScope.of(ctx).textMain)))));
    expect(t.widget<Text>(find.text('x')).style!.color, AppPalette.dark.textMain);
    await c.toggle();
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    final mid = t.widget<Text>(find.text('x')).style!.color!;
    expect(mid, isNot(AppPalette.dark.textMain));
    expect(mid, isNot(AppPalette.light.textMain));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.text('x')).style!.color, AppPalette.light.textMain);
    expect(c.prefs.getString('app_theme_mode'), 'light');
  });

  testWidgets('GlassCheck toggles', (t) async {
    final c = await ctrl();
    var on = true;
    await t.pumpWidget(host(c, StatefulBuilder(builder: (ctx, set) => GlassCheck(value: on, label: 'Border', onChanged: (b) => set(() => on = b)))));
    await t.tap(find.text('Border'));
    await t.pumpAndSettle();
    expect(on, isFalse);
  });
}
