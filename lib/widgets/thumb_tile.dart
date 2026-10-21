import 'package:flutter/material.dart';

import '../models/photo_item.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Port of a `.thumb` block: image, × badge, ←/→ reorder, Scan / Highlight /
/// Scan Photo actions.
class ThumbTile extends StatelessWidget {
  final PhotoItem item;
  final VoidCallback onRemove, onLeft, onRight, onScan, onHighlight, onScanPhoto;
  const ThumbTile({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onLeft,
    required this.onRight,
    required this.onScan,
    required this.onHighlight,
    required this.onScanPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    Widget chip(String t, Color bg, VoidCallback f) => LiquidGlassButton(
          onTap: f,
          tint: bg,
          radius: 9,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(t, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.glassBorder),
              boxShadow: [BoxShadow(color: p.shadow, blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: RawImage(image: item.image, height: 90, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            ),
          ),
          const SizedBox(height: 5),
          Row(mainAxisSize: MainAxisSize.min, children: [
            GlassButton.small(label: '←', fontSize: 10, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), onTap: onLeft),
            const SizedBox(width: 4),
            GlassButton.small(label: '→', fontSize: 10, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), onTap: onRight),
          ]),
          const SizedBox(height: 4),
          chip('Scan', AppColors.lightBlue, onScan),
          const SizedBox(height: 3),
          chip('Highlight', AppColors.yellow, onHighlight),
          const SizedBox(height: 3),
          chip('Scan Photo', AppColors.cyan, onScanPhoto),
        ]),
        Positioned(
          top: -8,
          right: -8,
          child: LiquidGlassButton(
            onTap: onRemove,
            tint: AppColors.redBright,
            circle: true,
            glow: true,
            padding: EdgeInsets.zero,
            pressedScale: 0.85,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: Center(child: Text('×', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, height: 1))),
            ),
          ),
        ),
      ]),
    );
  }
}
