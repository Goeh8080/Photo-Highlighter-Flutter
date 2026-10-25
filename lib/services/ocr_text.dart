import 'dart:math' as math;

import '../models/hl_shape.dart';

/// Builds readable, line-ordered text from OCR word boxes
/// (`{text,x0,y0,x1,y1[,line]}`). ML Kit supplies a `line` index; tesseract.js
/// words are grouped into lines by vertical proximity.
String ocrTextFromWords(List<Map<String, dynamic>> words) {
  final ws = words.where((w) => ((w['text'] as String?) ?? '').trim().isNotEmpty).toList();
  if (ws.isEmpty) return '';
  final hasLines = ws.every((w) => w['line'] != null);
  final lines = <List<Map<String, dynamic>>>[];
  if (hasLines) {
    final by = <int, List<Map<String, dynamic>>>{};
    for (final w in ws) {
      by.putIfAbsent((w['line'] as num).toInt(), () => []).add(w);
    }
    for (final k in by.keys.toList()..sort()) {
      lines.add(by[k]!);
    }
  } else {
    final sorted = [...ws]..sort((a, b) => ((a['y0'] as num) + (a['y1'] as num)).compareTo((b['y0'] as num) + (b['y1'] as num)));
    List<Map<String, dynamic>>? cur;
    double curMid = 0, curH = 0;
    for (final w in sorted) {
      final y0 = (w['y0'] as num).toDouble(), y1 = (w['y1'] as num).toDouble();
      final mid = (y0 + y1) / 2, h = math.max(1.0, y1 - y0);
      if (cur != null && (mid - curMid).abs() <= math.max(curH, h) * 0.6) {
        cur.add(w);
        curMid = (curMid * (cur.length - 1) + mid) / cur.length;
      } else {
        cur = [w];
        lines.add(cur);
        curMid = mid;
        curH = h;
      }
    }
  }
  final out = <String>[];
  for (final l in lines) {
    l.sort((a, b) => (a['x0'] as num).compareTo(b['x0'] as num));
    out.add(l.map((w) => (w['text'] as String).trim()).join(' '));
  }
  return out.join('\n');
}

/// Greedy word wrap to at most [cols] characters per line.
List<String> wrapText(String text, int cols) {
  final res = <String>[];
  for (final para in text.split('\n')) {
    var cur = '';
    for (final w in para.split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
      if (cur.isEmpty) {
        cur = w;
      } else if (cur.length + 1 + w.length <= cols) {
        cur = '$cur $w';
      } else {
        res.add(cur);
        cur = w;
      }
    }
    res.add(cur);
  }
  return res;
}

/// A text layer holding [text], laid out to fit a canvas of [sw]×[sh]
/// (coordinates are relative to the canvas centre, like all layers).
HlShape ocrTextLayer(String text, double sw, double sh, int color) {
  final fs = math.max(10.0, (sw / 28).roundToDouble());
  final cols = math.max(8, ((sw - 24) / (fs * 0.6)).floor());
  final lines = wrapText(text, cols);
  final wrapped = lines.join('\n');
  final top = -sh / 2 + 8;
  final h = math.min(sh - 16, lines.length * fs * 1.25 + 8);
  return HlShape(
    type: 'text',
    color: color,
    start: Pt(-sw / 2 + 8, top),
    current: Pt(sw / 2 - 8, top + h),
    thickness: 0,
    blendMode: 'source-over',
    textValue: wrapped,
    fontSize: fs,
  );
}
