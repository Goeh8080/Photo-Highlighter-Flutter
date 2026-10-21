import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';

import '../services/album_repository.dart';
import '../services/platform.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/transitions.dart';
import '../widgets/glass.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/glass_toast.dart';
import 'image_viewer_screen.dart';

/// Port of `#galleryModal` — "App Memory Album".
class GalleryScreen extends StatefulWidget {
  final AppState state;
  const GalleryScreen({super.key, required this.state});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late List<AlbumItem> _photos = widget.state.album.all();

  void _reload() => setState(() => _photos = widget.state.album.all());

  Future<void> _delete(AlbumItem it) async {
    if (!await showGlassConfirm(context, 'Is photo ko App Album se delete karein?')) return;
    await widget.state.album.delete(it.id);
    if (!mounted) return;
    GlassToast.show(context, '🗑️ Photo deleted!');
    _reload();
  }

  Future<void> _share(AlbumItem it) async {
    final name = it.name.isEmpty ? 'photo' : it.name;
    try {
      final r = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(it.bytes, mimeType: 'image/jpeg', name: '$name.jpg')],
        fileNameOverrides: ['$name.jpg'],
        title: name,
      ));
      if (r.status == ShareResultStatus.unavailable) throw StateError('unavailable');
    } catch (_) {
      await saveBytesPlatform(it.bytes, '$name.jpg', 'image/jpeg');
      if (mounted) GlassToast.show(context, 'Photo Downloaded!');
    }
  }

  Future<void> _edit(AlbumItem it) async {
    Navigator.of(context).pop();
    await widget.state.editFromAlbum(it);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LiquidBackground(
        child: Stack(children: [
          Positioned.fill(
            child: _photos.isEmpty
                ? Center(
                    child: GlassContainer(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🖼️', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 10),
                        Text('Koi Photo save nahi hai!', style: TextStyle(fontWeight: FontWeight.bold, color: p.textMain, fontSize: 15)),
                        const SizedBox(height: 6),
                        Text('Merge & Save karne par photos automatic yahan add ho jayengi.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.textSub)),
                      ]),
                    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
                  )
                : LayoutBuilder(builder: (context, c) {
                    final cols = ((c.maxWidth - 28 + 14) / (180 + 14)).floor().clamp(1, 8);
                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(14, top + 74, 14, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        mainAxisExtent: 246,
                      ),
                      itemCount: _photos.length,
                      itemBuilder: (_, i) => _card(p, _photos[i])
                          .animate()
                          .fadeIn(delay: (70 * i).clamp(0, 700).ms, duration: 380.ms)
                          .slideY(begin: 0.15, curve: Curves.easeOutCubic, duration: 480.ms),
                    );
                  }),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassBar(
              child: Row(children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('🖼️ App Memory Album (${_photos.length})',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: p.textMain)),
                  ),
                ),
                GlassButton.small(label: 'Export All PDF', emoji: '📄', color: AppColors.purple, onTap: widget.state.exportAllAlbumToPdf),
                const SizedBox(width: 8),
                GlassButton.small(label: '✕ Close', color: AppColors.red, fontSize: 13, onTap: () => Navigator.of(context).pop()),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card(AppPalette p, AlbumItem it) => GlassContainer(
        radius: 16,
        blur: 14,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Pressable(
            pressedScale: 0.97,
            onTap: () => Navigator.of(context).push(GlassPageRoute(builder: (_) => ImageViewerScreen(bytes: it.bytes, heroTag: 'album_${it.id}'))),
            child: Container(
              height: 120,
              color: Colors.black,
              child: Hero(tag: 'album_${it.id}', child: Image.memory(it.bytes, fit: BoxFit.contain, gaplessPlayback: true, cacheWidth: 600)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: p.textMain)),
                const SizedBox(height: 2),
                Text('${it.sizeLabel} • ${it.date}', style: TextStyle(fontSize: 10, color: p.textSub)),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.glassInput,
              border: Border(top: BorderSide(color: p.glassBorder.withValues(alpha: 0.35))),
            ),
            child: Row(children: [
              Expanded(child: GlassButton.small(label: '✏️ Edit', fontSize: 11, color: AppColors.blue, expand: true, padding: const EdgeInsets.symmetric(vertical: 7), onTap: () => _edit(it))),
              const SizedBox(width: 6),
              Expanded(child: GlassButton.small(label: '📤 Share', fontSize: 11, color: AppColors.emerald, expand: true, padding: const EdgeInsets.symmetric(vertical: 7), onTap: () => _share(it))),
              const SizedBox(width: 6),
              Expanded(child: GlassButton.small(label: '🗑️ Delete', fontSize: 11, color: AppColors.redBright, expand: true, padding: const EdgeInsets.symmetric(vertical: 7), onTap: () => _delete(it))),
            ]),
          ),
        ]),
      );
}
