import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';

import '../models/constants.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/transitions.dart';
import '../widgets/glass.dart';
import '../widgets/glass_dialog.dart';
import '../widgets/glass_toast.dart';
import '../widgets/flip_slot.dart';
import '../widgets/thumb_tile.dart';
import 'editor/scan_editor_screen.dart';
import 'gallery_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState get s => widget.state;
  final _wrapKey = GlobalKey();
  final _fileName = TextEditingController();
  final _borderSize = TextEditingController(text: '2');
  final _pdfPages = TextEditingController();
  final _picker = ImagePicker();
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    s.toast = (m) => GlassToast.show(context, m);
    s.alert = (m) => showGlassAlert(context, m);
    s.addListener(_sync);
  }

  void _sync() {
    if (_borderSize.text != '${s.borderSize}') _borderSize.text = '${s.borderSize}';
    if (_pdfPages.text != s.pdfPageInput) _pdfPages.text = s.pdfPageInput;
  }

  @override
  void dispose() {
    s.removeListener(_sync);
    super.dispose();
  }

  Future<void> _pickCamera() async {
    try {
      final f = await _picker.pickImage(source: ImageSource.camera);
      if (f != null) await s.addFiles([await f.readAsBytes()]);
    } catch (_) {}
  }

  Future<void> _pickGallery() async {
    try {
      final fs = await _picker.pickMultiImage();
      final bytes = <Uint8List>[];
      for (final f in fs) {
        bytes.add(await f.readAsBytes());
      }
      await s.addFiles(bytes);
    } catch (_) {}
  }

  Future<void> _pickPdf() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (f != null) await s.loadPdf(await f.readAsBytes());
  }

  void _toggleTheme() {
    final t = AppThemeScope.controllerOf(context);
    t.toggle();
    GlassToast.show(context, t.isLight ? '☀️ Light Blue Theme On' : '🌙 Dark Theme On');
    setState(() => _menuOpen = false);
  }

  Future<void> _openGallery() async {
    setState(() => _menuOpen = false);
    await Navigator.of(context).push(GlassPageRoute(builder: (_) => GalleryScreen(state: s)));
  }

  Future<void> _reload() async {
    setState(() => _menuOpen = false);
    if (await showGlassConfirm(context, 'App ko Restart Kare?')) s.resetAll();
  }

  Future<void> _openScan(int i, String type) async {
    final res = await Navigator.of(context).push(SlideUpRoute(builder: (_) => ScanEditorScreen(item: s.images[i], entryMode: type)));
    if (res != null && mounted) await s.replaceImage(i, res);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LiquidBackground(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _menuOpen ? () => setState(() => _menuOpen = false) : null,
                child: ListView(
                  padding: EdgeInsets.only(top: top + 66, bottom: 40),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(children: [
                          _controlsCard(p).animate().fadeIn(duration: 450.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic),
                          _previewCard(p).animate().fadeIn(delay: 120.ms, duration: 450.ms).slideY(begin: 0.08, curve: Curves.easeOutCubic),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(top: 0, left: 0, right: 0, child: _header(p)),
            if (_menuOpen) _menu(p),
            _busyOverlay(p),
          ]),
        ),
      ),
    );
  }

  Widget _header(AppPalette p) => GlassBar(
        child: Row(children: [
          Expanded(
            child: Text('📷 Photo Merger & Highlighter',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.textMain, letterSpacing: 0.2)),
          ),
          GlassButton.small(label: 'Theme', emoji: '🌓', fontSize: 13, onTap: _toggleTheme),
          const SizedBox(width: 8),
          LiquidGlassButton(
            onTap: () => setState(() => _menuOpen = !_menuOpen),
            radius: 11,
            glow: _menuOpen,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: AnimatedRotation(
                turns: _menuOpen ? 0.25 : 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: Text('⋮', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: p.textMain)),
              ),
          ),
        ]),
      );

  Widget _menu(AppPalette p) {
    final top = MediaQuery.paddingOf(context).top;
    Widget item(String e, String t, VoidCallback f) => Pressable(
          pressedScale: 0.97,
          onTap: f,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Text(e, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
              Text(t, style: TextStyle(fontSize: 13, color: p.textMain)),
            ]),
          ),
        );
    return Positioned(
      top: top + 56,
      right: 12,
      width: 220,
      child: GlassContainer(
        radius: 16,
        blur: 30,
        fill: [p.popBg.withValues(alpha: 0.72), p.popBg.withValues(alpha: 0.55)],
        child: Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            item('🖼️', 'In-App Album / Gallery', _openGallery),
            Divider(height: 1, color: p.glassBorder.withValues(alpha: 0.3)),
            item('🌓', 'Switch Theme', _toggleTheme),
            Divider(height: 1, color: p.glassBorder.withValues(alpha: 0.3)),
            item('🔄', 'Reset / Reload', _reload),
          ]),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.08, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _controlsCard(AppPalette p) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          GlassButton(label: 'Camera', emoji: '📸', color: AppColors.orange, onTap: _pickCamera),
          GlassButton(label: 'Gallery', emoji: '📁', onTap: _pickGallery),
          GlassButton(label: 'PDF Select', emoji: '📄', color: AppColors.purple, onTap: _pickPdf),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: s.pdfBytes == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: p.glassInput,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.purple.withValues(alpha: 0.8), style: BorderStyle.solid),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PDF Loaded (Total Pages: ${s.pdfPages})',
                        style: TextStyle(fontSize: 12, color: p.accentLight, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: GlassTextField(
                          controller: _pdfPages,
                          hint: 'Page Nos (jaise: 1, 5, 9 ya 1-5)',
                          fontSize: 13,
                          onChanged: (v) => s.pdfPageInput = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GlassButton(label: 'Load Pages', color: AppColors.purple, fontSize: 13, bold: true, onTap: s.loadSelectedPdfPages),
                    ]),
                  ]),
                ),
        ),
        const SizedBox(height: 12),
        GlassSegmented<String>(
          values: const ['horizontal', 'vertical', 'grid'],
          selected: s.mode,
          labelOf: (v) => const {'horizontal': 'Horizontal', 'vertical': 'Vertical', 'grid': 'Grid Layout'}[v]!,
          onChanged: s.setMode,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: s.mode != 'grid'
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: p.glassInput, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Text('Grid Style:', style: TextStyle(fontSize: 12, color: p.textMain)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GlassSelect<String>(
                        expand: true,
                        value: s.gridType,
                        items: s.gridOptions.map((e) => e.value).toList(),
                        labelOf: (v) => allGridOptions.firstWhere((o) => o.value == v).text,
                        onChanged: s.setGridType,
                      ),
                    ),
                  ]),
                ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.glassInput.withValues(alpha: p.isDark ? 0.05 : 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.glassBorder.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GlassSegmented<QualityPreset>(
              height: 34,
              fontSize: 11,
              values: qualityPresets,
              selected: s.quality,
              labelOf: (q) => q.label,
              onChanged: s.setQuality,
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, child: c)),
              child: Text(s.sizeInfo,
                  key: ValueKey(s.sizeInfo), style: const TextStyle(color: AppColors.emerald, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: p.glassInput,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.glassBorder.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              GlassCheck(value: s.borderOn, label: 'Border', onChanged: s.setBorder),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: GlassTextField(
                  controller: _borderSize,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                  onChanged: (v) => s.setBorderSize(int.tryParse(v) ?? 0),
                ),
              ),
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 520),
            child: IntrinsicWidth(
              child: GlassTextField(
                controller: _fileName,
                hint: 'File Name (Khali chhodne par auto name le lega)...',
                onChanged: (v) => s.fileName = v,
              ),
            ),
          ),
          GlassButton(label: 'Merge', color: AppColors.green, bold: true, onTap: s.merge),
          GlassButton(label: 'Save & Album', color: AppColors.blue, bold: true, onTap: s.saveAndAlbum),
          GlassButton(label: 'Merged PDF', emoji: '📄', color: AppColors.purple, bold: true, onTap: s.downloadMergedPdf),
          GlassButton(label: 'Separate Pages PDF', emoji: '📄', color: AppColors.violet, bold: true, onTap: s.downloadSeparatePagesPdf),
        ]),
      ]),
    );
  }

  Widget _previewCard(AppPalette p) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s.images.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(children: [
              Text('🖼️', style: const TextStyle(fontSize: 34))
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .moveY(begin: 0, end: -6, duration: 1600.ms, curve: Curves.easeInOut),
              const SizedBox(height: 8),
              Text('Photos add karein — Camera, Gallery ya PDF se',
                  textAlign: TextAlign.center, style: TextStyle(color: p.textSub, fontSize: 13)),
            ]),
          )
        else
          Wrap(
            key: _wrapKey,
            spacing: 15,
            runSpacing: 10,
            children: [
              for (var i = 0; i < s.images.length; i++)
                FlipSlot(
                  key: ObjectKey(s.images[i]),
                  spaceKey: _wrapKey,
                  builder: (context, animateOut) {
                    final item = s.images[i];
                    int idx() => s.images.indexOf(item);
                    return ThumbTile(
                      item: item,
                      onRemove: () async {
                        await animateOut();
                        final j = idx();
                        if (j >= 0) s.removeImage(j);
                      },
                      onLeft: () => s.moveImage(idx(), -1),
                      onRight: () => s.moveImage(idx(), 1),
                      onScan: () => _openScan(idx(), 'crop'),
                      onHighlight: () => _openScan(idx(), 'highlight'),
                      onScanPhoto: () => s.applyPhotoCopyScan(idx()),
                    );
                  },
                ),
            ],
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          child: s.mergedPreviewJpeg == null || s.images.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: ClipRRect(
                      key: ValueKey(s.mergedPreviewJpeg.hashCode),
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(s.mergedPreviewJpeg!, gaplessPlayback: true, fit: BoxFit.fitWidth),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _busyOverlay(AppPalette p) => IgnorePointer(
        ignoring: !s.busy,
        child: AnimatedOpacity(
          opacity: s.busy ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Container(
            color: Colors.black.withValues(alpha: 0.18),
            alignment: Alignment.center,
            child: GlassContainer(
              radius: 30,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: p.accent)),
                const SizedBox(width: 12),
                Text(s.busyText ?? 'Working…', style: TextStyle(color: p.textMain, fontWeight: FontWeight.w600, decoration: TextDecoration.none, fontSize: 14)),
              ]),
            ),
          ),
        ),
      );
}
