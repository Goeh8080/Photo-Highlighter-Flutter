import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'hl_shape.dart';

/// Port of the augmented `Image` objects kept in the JS `images[]` array.
///
/// * [src]        – bytes actually used by merge (may include burnt-in highlights)
/// * [orig]       – original upload (used by Scan/crop)
/// * [display]    – base for highlight editing (cropped/adjusted/scanned)
/// * [croppedBase]– last perspective-cropped base
class PhotoItem {
  Uint8List src;
  Uint8List orig;
  Uint8List display;
  Uint8List? croppedBase;
  ui.Image image; // decoded [src]
  List<Pt>? savedPts; // normalised 0..1 crop quad
  int rotation;
  List<HlShape> hlShapes;
  List<HistoryEntry> hlRedoStack;
  List<OcrWord> ocrWords;
  int scanPhotoCount;
  AdjSettings adj;

  /// Width of the editor view the shapes/OCR boxes were authored in. The HTML
  /// stored them in raw CSS px (breaking on resize); we rescale on reopen.
  double? viewW;

  /// Pre-adjustment base for Photo Effects so re-opening the panel does not
  /// compound filters (the HTML re-applied them on the already-filtered image).
  Uint8List? adjBase;

  PhotoItem({
    required this.src,
    required this.orig,
    required this.display,
    required this.image,
    this.croppedBase,
    this.savedPts,
    this.rotation = 0,
    List<HlShape>? hlShapes,
    List<HistoryEntry>? hlRedoStack,
    List<OcrWord>? ocrWords,
    this.scanPhotoCount = 0,
    AdjSettings? adj,
    this.viewW,
    this.adjBase,
  })  : hlShapes = hlShapes ?? [],
        hlRedoStack = hlRedoStack ?? [],
        ocrWords = ocrWords ?? [],
        adj = adj ?? AdjSettings();

  int get width => image.width;
  int get height => image.height;

  Map<String, dynamic> toMeta() => {
        'orig': base64Encode(orig),
        if (croppedBase != null) 'croppedBaseSrc': base64Encode(croppedBase!),
        'displaySrc': identical(display, orig) ? null : base64Encode(display),
        'src': identical(src, display) ? null : base64Encode(src),
        'savedPts': savedPts?.map((e) => e.toJson()).toList(),
        'rotation': rotation,
        'hlShapes': hlShapes.map((e) => e.toJson()).toList(),
        'hlRedoStack': hlRedoStack.map((e) => e.toJson()).toList(),
        'ocrWords': ocrWords.map((e) => e.toJson()).toList(),
        'scanPhotoCount': scanPhotoCount,
        'adjSettings': adj.toJson(),
        'viewW': viewW,
        if (adjBase != null) 'adjBase': base64Encode(adjBase!),
      };
}
