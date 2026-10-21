import 'dart:math' as math;

/// Mutable 2D point (JS `{x, y}`), kept mutable so the editor logic can be
/// ported 1:1 from the original pointer handlers.
class Pt {
  double x, y;
  Pt(this.x, this.y);
  Pt copy() => Pt(x, y);
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  static Pt fromJson(dynamic j) => Pt((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
  @override
  String toString() => 'Pt($x,$y)';
}

/// One highlight layer (rect / oval / free / free_straight / text).
class HlShape {
  String type;
  int color; // ARGB
  Pt? start;
  Pt? current;
  List<Pt>? pts;
  double thickness;
  double angle;
  String blendMode; // 'multiply' | 'source-over'
  String? textValue;
  double fontSize;
  bool isOCR;
  int? ocrIdx;

  HlShape({
    required this.type,
    required this.color,
    this.start,
    this.current,
    this.pts,
    this.thickness = 8,
    this.angle = 0,
    this.blendMode = 'multiply',
    this.textValue,
    this.fontSize = 16,
    this.isOCR = false,
    this.ocrIdx,
  });

  HlShape clone() => HlShape.fromJson(toJson());

  String get typeLabel {
    if (isOCR) return 'OCR Highlight';
    switch (type) {
      case 'rect':
        return 'Rectangle';
      case 'oval':
        return 'Oval';
      case 'free_straight':
        return 'Straight Line';
      case 'text':
        return 'Text Layer';
      default:
        return 'Freehand';
    }
  }

  /// getShapeCenter()
  Pt center() {
    if (type == 'free' && pts != null && pts!.isNotEmpty) {
      final b = bounds();
      return Pt((b[0] + b[2]) / 2, (b[1] + b[3]) / 2);
    }
    if (start == null || current == null) return Pt(0, 0);
    return Pt((start!.x + current!.x) / 2, (start!.y + current!.y) / 2);
  }

  /// [minX, minY, maxX, maxY]
  List<double> bounds() {
    if (type == 'free' && pts != null && pts!.isNotEmpty) {
      var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
      for (final p in pts!) {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
      return [minX, minY, maxX, maxY];
    }
    if (start != null && current != null) {
      return [
        math.min(start!.x, current!.x),
        math.min(start!.y, current!.y),
        math.max(start!.x, current!.x),
        math.max(start!.y, current!.y),
      ];
    }
    return [0, 0, 0, 0];
  }

  /// getShapeBoundingPoints(): 8 handles clockwise from top-left.
  List<Pt> handles() {
    final b = bounds();
    final minX = b[0], minY = b[1], maxX = b[2], maxY = b[3];
    return [
      Pt(minX, minY),
      Pt((minX + maxX) / 2, minY),
      Pt(maxX, minY),
      Pt(maxX, (minY + maxY) / 2),
      Pt(maxX, maxY),
      Pt((minX + maxX) / 2, maxY),
      Pt(minX, maxY),
      Pt(minX, (minY + maxY) / 2),
    ];
  }

  void translate(double dx, double dy) {
    start?.x += dx;
    start?.y += dy;
    current?.x += dx;
    current?.y += dy;
    if (type == 'free' && pts != null) {
      for (final p in pts!) {
        p.x += dx;
        p.y += dy;
      }
    }
  }

  void scaleBy(double s) {
    for (final p in [start, current, ...?pts]) {
      if (p == null) continue;
      p.x *= s;
      p.y *= s;
    }
    thickness *= s;
    fontSize *= s;
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'color': color,
        if (start != null) 'start': start!.toJson(),
        if (current != null) 'current': current!.toJson(),
        if (pts != null) 'pts': pts!.map((e) => e.toJson()).toList(),
        'thickness': thickness,
        'angle': angle,
        'blendMode': blendMode,
        if (textValue != null) 'textValue': textValue,
        'fontSize': fontSize,
        'isOCR': isOCR,
        if (ocrIdx != null) 'ocrIdx': ocrIdx,
      };

  static HlShape fromJson(Map<String, dynamic> j) => HlShape(
        type: j['type'] as String,
        color: j['color'] as int,
        start: j['start'] != null ? Pt.fromJson(j['start']) : null,
        current: j['current'] != null ? Pt.fromJson(j['current']) : null,
        pts: j['pts'] != null ? (j['pts'] as List).map(Pt.fromJson).toList() : null,
        thickness: (j['thickness'] as num?)?.toDouble() ?? 8,
        angle: (j['angle'] as num?)?.toDouble() ?? 0,
        blendMode: j['blendMode'] as String? ?? 'multiply',
        textValue: j['textValue'] as String?,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 16,
        isOCR: j['isOCR'] as bool? ?? false,
        ocrIdx: j['ocrIdx'] as int?,
      );
}

/// Entry of the (unusual, but faithfully ported) `hlRedoStack`.
class HistoryEntry {
  final String action; // add | edit | delete | insert
  final int? index;
  final HlShape? shape;
  HistoryEntry(this.action, {this.index, this.shape});

  Map<String, dynamic> toJson() => {
        'action': action,
        if (index != null) 'index': index,
        if (shape != null) 'shape': shape!.toJson(),
      };
  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
        j['action'] as String,
        index: j['index'] as int?,
        shape: j['shape'] != null ? HlShape.fromJson(Map<String, dynamic>.from(j['shape'])) : null,
      );
}

/// Tesseract word box in view space (relative to canvas centre).
class OcrWord {
  final String text;
  final double x, y, w, h;
  bool highlighted;
  OcrWord({required this.text, required this.x, required this.y, required this.w, required this.h, this.highlighted = false});

  Map<String, dynamic> toJson() => {'text': text, 'x': x, 'y': y, 'w': w, 'h': h, 'highlighted': highlighted};
  static OcrWord fromJson(Map<String, dynamic> j) => OcrWord(
        text: j['text'] as String? ?? '',
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        highlighted: j['highlighted'] as bool? ?? false,
      );
  OcrWord scaled(double s) => OcrWord(text: text, x: x * s, y: y * s, w: w * s, h: h * s, highlighted: highlighted);
}

class AdjSettings {
  int hue, sat, bright, contrast, colorScan, bwScan;
  AdjSettings({this.hue = 0, this.sat = 0, this.bright = 0, this.contrast = 0, this.colorScan = 0, this.bwScan = 0});
  AdjSettings copy() => AdjSettings(hue: hue, sat: sat, bright: bright, contrast: contrast, colorScan: colorScan, bwScan: bwScan);
  bool get isIdentity => hue == 0 && sat == 0 && bright == 0 && contrast == 0 && colorScan == 0 && bwScan == 0;
  Map<String, dynamic> toJson() =>
      {'hue': hue, 'sat': sat, 'bright': bright, 'contrast': contrast, 'colorScan': colorScan, 'bwScan': bwScan};
  static AdjSettings fromJson(Map<String, dynamic>? j) => j == null
      ? AdjSettings()
      : AdjSettings(
          hue: (j['hue'] as num?)?.toInt() ?? 0,
          sat: (j['sat'] as num?)?.toInt() ?? 0,
          bright: (j['bright'] as num?)?.toInt() ?? 0,
          contrast: (j['contrast'] as num?)?.toInt() ?? 0,
          colorScan: (j['colorScan'] as num?)?.toInt() ?? 0,
          bwScan: (j['bwScan'] as num?)?.toInt() ?? 0,
        );
}
