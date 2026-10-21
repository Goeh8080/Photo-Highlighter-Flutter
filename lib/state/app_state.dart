import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/constants.dart';
import '../models/hl_shape.dart';
import '../models/photo_item.dart';
import '../services/album_repository.dart';
import '../services/image_ops.dart';
import '../services/pdf_service.dart';
import '../services/platform.dart';

/// Home-screen state: everything the original kept in globals
/// (`images`, `mode`, `qVal`, `resScale`, border inputs, PDF doc…).
class AppState extends ChangeNotifier {
  final AlbumRepository album;
  AppState(this.album);

  final List<PhotoItem> images = [];
  String mode = 'horizontal';
  String gridType = 'auto';
  QualityPreset quality = qualityPresets[2]; // High
  bool borderOn = false;
  int borderSize = 2;
  String fileName = '';
  bool busy = false;
  String? busyText;

  // merged output
  ui.Image? merged;
  Uint8List? mergedPreviewJpeg;
  String sizeInfo = 'Size: 0 KB';
  int _mergeGen = 0;

  // PDF import
  Uint8List? pdfBytes;
  int pdfPages = 0;
  String pdfPageInput = '';

  /// Callbacks wired by the UI (toast / alert / confirm).
  void Function(String msg) toast = (_) {};
  Future<void> Function(String msg) alert = (_) async {};

  List<GridOption> get gridOptions =>
      allGridOptions.where((o) => o.value == 'auto' || o.count == images.length).toList();

  void _setBusy(bool b, [String? text]) {
    busy = b;
    busyText = text;
    notifyListeners();
  }

  void _countChanged() {
    // The HTML forced border on for ≥2 photos / off for 1 (size 2) on *every*
    // merge, which made the checkbox unusable; we apply it when the count changes.
    borderOn = images.length >= 2;
    borderSize = 2;
    if (!gridOptions.any((o) => o.value == gridType)) gridType = 'auto';
  }

  PhotoItem _newItem(Uint8List bytes, ui.Image img) =>
      PhotoItem(src: bytes, orig: bytes, display: bytes, image: img);

  Future<void> addFiles(List<Uint8List> files) async {
    if (files.isEmpty) return;
    _setBusy(true, 'Loading photos…');
    try {
      final loaded = await Future.wait(files.map((f) async {
        try {
          return await ImageOps.loadUpload(f);
        } catch (_) {
          return null;
        }
      }));
      for (final l in loaded) {
        if (l != null) images.add(_newItem(l.$1, l.$2));
      }
      _countChanged();
    } finally {
      _setBusy(false);
    }
    await merge();
  }

  Future<void> loadPdf(Uint8List bytes) async {
    _setBusy(true, 'Reading PDF…');
    try {
      final n = await PdfService.pageCount(bytes);
      pdfBytes = bytes;
      pdfPages = n;
      pdfPageInput = '1-$n';
    } catch (_) {
      await alert('PDF load karne me error aayi!');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> loadSelectedPdfPages() async {
    if (pdfBytes == null) return;
    final pages = PdfService.parsePageInput(pdfPageInput, pdfPages);
    if (pages.isEmpty) {
      await alert('Kripya sahi page numbers dalein!');
      return;
    }
    _setBusy(true, 'Rendering PDF pages…');
    try {
      await for (final img in PdfService.renderPages(pdfBytes!, pages)) {
        final jpg = await ImageOps.encodeJpeg(img, 0.95);
        images.add(_newItem(jpg, img));
        notifyListeners();
      }
      _countChanged();
    } finally {
      _setBusy(false);
    }
    await merge();
  }

  void setMode(String m) {
    mode = m;
    merge();
  }

  void setGridType(String g) {
    gridType = g;
    merge();
  }

  void setQuality(QualityPreset q) {
    quality = q;
    if (images.isNotEmpty) merge();
    notifyListeners();
  }

  void setBorder(bool on) {
    borderOn = on;
    merge();
  }

  void setBorderSize(int v) {
    borderSize = v.clamp(0, 100);
    merge();
  }

  void removeImage(int i) {
    images.removeAt(i);
    _countChanged();
    if (images.isNotEmpty) {
      merge();
    } else {
      merged = null;
      mergedPreviewJpeg = null;
      notifyListeners();
    }
  }

  void moveImage(int i, int dir) {
    final n = i + dir;
    if (n >= 0 && n < images.length) {
      final t = images[i];
      images[i] = images[n];
      images[n] = t;
      notifyListeners();
      merge();
    }
  }

  Future<void> replaceImage(int i, PhotoItem item) async {
    images[i] = item;
    await merge();
  }

  /// `applyPhotoCopyScan()`: cycles 3 photocopy passes, the 4th restores.
  Future<void> applyPhotoCopyScan(int index) async {
    final t = images[index];
    t.scanPhotoCount++;
    if (t.scanPhotoCount > 3) {
      t.scanPhotoCount = 0;
      final base = t.croppedBase ?? t.orig;
      final img = await ImageOps.decode(base);
      t
        ..display = base
        ..src = base
        ..adjBase = null
        ..image = img;
      await merge();
      return;
    }
    _setBusy(true, 'Scanning…');
    try {
      final out = await ImageOps.photocopyScan(await ImageOps.decode(t.display));
      final jpg = await ImageOps.encodeJpeg(out, 0.95);
      t
        ..display = jpg
        ..src = jpg
        ..adjBase = null
        ..image = out;
    } finally {
      _setBusy(false);
    }
    await merge();
  }

  Future<void> merge() async {
    notifyListeners();
    if (images.isEmpty) return;
    final gen = ++_mergeGen;
    final bw = borderOn ? borderSize : 0;
    final ui.Image img;
    try {
      img = await ImageOps.merge(
        images: List.of(images),
        mode: mode,
        gridType: gridType,
        bw: bw,
        resScale: quality.res,
      );
    } catch (e) {
      debugPrint('merge failed: $e');
      if (gen == _mergeGen) {
        sizeInfo = 'Size: — (merge failed: image too large)';
        notifyListeners();
      }
      return;
    }
    if (gen != _mergeGen) return;
    var effQ = quality.q;
    if (images.length == 2) {
      effQ = effQ < 0.85 ? effQ : 0.85;
    } else if (images.length == 4) {
      effQ = effQ < 0.90 ? effQ : 0.90;
    }
    final jpg = await ImageOps.encodeJpeg(img, effQ);
    if (gen != _mergeGen) return;
    merged = img;
    mergedPreviewJpeg = jpg;
    final kb = (jpg.length / 1024).round();
    sizeInfo = 'Size: ${kb >= 1024 ? '${(kb / 1024).toStringAsFixed(2)} MB' : '$kb KB'} | ${img.width}×${img.height} px';
    notifyListeners();
  }

  String _fname(String prefix) =>
      fileName.trim().isNotEmpty ? fileName.trim() : '${prefix}_${DateTime.now().millisecondsSinceEpoch}';

  String _metaState() => jsonEncode({'mode': mode, 'images': images.map((e) => e.toMeta()).toList()});

  /// "Save & Album": store in the in-app album and download the JPEG.
  Future<void> saveAndAlbum() async {
    if (images.isEmpty || merged == null) {
      await alert('Kripya pahle photo add karein!');
      return;
    }
    final name = _fname('Photo_Merged');
    _setBusy(true, 'Saving…');
    try {
      final jpg = await ImageOps.encodeJpeg(merged!, quality.q);
      await album.add(name: name, bytes: jpg, metaState: _metaState());
      toast('💾 App Album में सेव हो गया!');
      await saveBytesPlatform(jpg, '$name.jpg', 'image/jpeg');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> downloadMergedPdf() async {
    if (images.isEmpty || merged == null) {
      await alert('Kripya pahle photo add karein!');
      return;
    }
    final name = _fname('Photo_Merged');
    _setBusy(true, 'Building PDF…');
    try {
      final jpg = await ImageOps.encodeJpeg(merged!, quality.q);
      final pdf = await PdfService.buildImagePdf([(jpg, merged!.width, merged!.height)]);
      await saveBytesPlatform(pdf, '$name.pdf', 'application/pdf');
      toast('📄 Merged PDF Save Ho Gayi!');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> downloadSeparatePagesPdf() async {
    if (images.isEmpty) {
      await alert('Kripya pahle photo add karein!');
      return;
    }
    toast('⏳ Separate Page PDF Generate ho rahi hai...');
    final name = _fname('Photos_Pages');
    _setBusy(true, 'Building PDF…');
    try {
      final pages = <(Uint8List, int, int)>[];
      for (final it in images) {
        final img = await ImageOps.decode(it.display);
        final jpg = await ImageOps.encodeJpeg(img, 0.95);
        pages.add((jpg, img.width, img.height));
      }
      final pdf = await PdfService.buildImagePdf(pages);
      await saveBytesPlatform(pdf, '$name.pdf', 'application/pdf');
      toast('📄 Multi-Page PDF Save Ho Gayi!');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> exportAllAlbumToPdf() async {
    final photos = album.all();
    if (photos.isEmpty) {
      await alert('Album me koi photo save nahi hai!');
      return;
    }
    toast('⏳ PDF Generate ho rahi hai...');
    _setBusy(true, 'Building PDF…');
    try {
      final pages = <(Uint8List, int, int)>[];
      for (final p in photos) {
        final img = await ImageOps.decode(p.bytes);
        pages.add((p.bytes, img.width, img.height));
        img.dispose();
      }
      final pdf = await PdfService.buildImagePdf(pages);
      await saveBytesPlatform(pdf, 'Album_Export_${DateTime.now().millisecondsSinceEpoch}.pdf', 'application/pdf');
      toast('📄 Album PDF Export Ho Gayi!');
    } finally {
      _setBusy(false);
    }
  }

  /// `editGalleryImage()`: restore an editable project or load the plain image.
  Future<void> editFromAlbum(AlbumItem item) async {
    _setBusy(true, 'Loading…');
    try {
      Map<String, dynamic>? state;
      if (item.metaState != null) {
        try {
          state = jsonDecode(item.metaState!) as Map<String, dynamic>;
        } catch (_) {}
      }
      final subs = (state?['images'] as List?) ?? const [];
      if (subs.isNotEmpty) {
        images.clear();
        for (final raw in subs) {
          final m = Map<String, dynamic>.from(raw as Map);
          final orig = base64Decode(m['orig'] as String);
          final display = m['displaySrc'] != null ? base64Decode(m['displaySrc'] as String) : orig;
          final src = m['src'] != null ? base64Decode(m['src'] as String) : display;
          images.add(PhotoItem(
            src: src,
            orig: orig,
            display: display,
            croppedBase: m['croppedBaseSrc'] != null ? base64Decode(m['croppedBaseSrc'] as String) : null,
            image: await ImageOps.decode(src),
            savedPts: (m['savedPts'] as List?)?.map(Pt.fromJson).toList(),
            rotation: (m['rotation'] as num?)?.toInt() ?? 0,
            hlShapes: ((m['hlShapes'] as List?) ?? []).map((e) => HlShape.fromJson(Map<String, dynamic>.from(e))).toList(),
            hlRedoStack:
                ((m['hlRedoStack'] as List?) ?? []).map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e))).toList(),
            ocrWords: ((m['ocrWords'] as List?) ?? []).map((e) => OcrWord.fromJson(Map<String, dynamic>.from(e))).toList(),
            scanPhotoCount: (m['scanPhotoCount'] as num?)?.toInt() ?? 0,
            adj: AdjSettings.fromJson(m['adjSettings'] != null ? Map<String, dynamic>.from(m['adjSettings']) : null),
            viewW: (m['viewW'] as num?)?.toDouble(),
            adjBase: m['adjBase'] != null ? base64Decode(m['adjBase'] as String) : null,
          ));
        }
        if (state?['mode'] is String) mode = state!['mode'] as String;
        _countChanged();
        toast('Editable Project Loaded into Canvas!');
      } else {
        images.add(_newItem(item.bytes, await ImageOps.decode(item.bytes)));
        _countChanged();
        toast('Image loaded in Editor!');
      }
    } finally {
      _setBusy(false);
    }
    await merge();
  }

  /// "Reset / Reload": clears the session (web build also reloads the page).
  void resetAll() {
    images.clear();
    merged = null;
    mergedPreviewJpeg = null;
    pdfBytes = null;
    pdfPages = 0;
    fileName = '';
    mode = 'horizontal';
    gridType = 'auto';
    quality = qualityPresets[2];
    sizeInfo = 'Size: 0 KB';
    notifyListeners();
    reloadAppPlatform();
  }
}
