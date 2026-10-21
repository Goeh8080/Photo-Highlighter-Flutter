import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/glass.dart';

/// Port of `#imgViewerModal`: full-screen viewer (tap outside closes),
/// with Hero flight from the album card and pinch-zoom.
class ImageViewerScreen extends StatelessWidget {
  final Uint8List bytes;
  final String heroTag;
  const ImageViewerScreen({super.key, required this.bytes, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.black.withValues(alpha: 0.88)),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.95,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: InteractiveViewer(
              maxScale: 6,
              child: Hero(
                tag: heroTag,
                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, fit: BoxFit.contain)),
              ),
            ),
          ),
        ),
        Positioned(
          top: top + 20,
          right: 20,
          child: GlassButton(label: '✕ Close', color: AppColors.redBright, bold: true, radius: 20, onTap: () => Navigator.of(context).pop()),
        ),
      ]),
    );
  }
}
