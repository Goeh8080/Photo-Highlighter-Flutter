import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// Frosted replacements for window.alert()/confirm() with a spring pop-in.
Future<bool> showGlassConfirm(BuildContext context, String message, {String ok = 'OK', String cancel = 'Cancel', bool alertOnly = false}) async {
  final r = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dialog',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (ctx, _, _) {
      final p = AppThemeScope.of(ctx);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: GlassContainer(
            radius: 24,
            blur: 30,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            fill: [p.popBg.withValues(alpha: 0.7), p.popBg.withValues(alpha: 0.5)],
            child: Material(
              type: MaterialType.transparency,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: p.textMain, fontSize: 15, fontWeight: FontWeight.w600, height: 1.35)),
                const SizedBox(height: 18),
                Row(children: [
                  if (!alertOnly) ...[
                    Expanded(child: GlassButton(label: cancel, expand: true, onTap: () => Navigator.pop(ctx, false))),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: GlassButton(label: ok, color: AppColors.blue, bold: true, expand: true, onTap: () => Navigator.pop(ctx, true))),
                ]),
              ]),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
      return FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(c), child: child));
    },
  );
  return r ?? false;
}

Future<void> showGlassAlert(BuildContext context, String message) => showGlassConfirm(context, message, alertOnly: true);
