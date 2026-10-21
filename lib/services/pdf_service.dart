import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// jsPDF / pdf.js replacements.
class PdfService {
  /// Number of pages in a PDF (rasterises every page at a token 1 dpi).
  static Future<int> pageCount(Uint8List pdf) async {
    var n = 0;
    await for (final _ in Printing.raster(pdf, dpi: 1)) {
      n++;
    }
    return n;
  }

  /// `parsePageInput()` – "1, 5, 9" / "1-5" → sorted unique pages.
  static List<int> parsePageInput(String input, int maxPages) {
    final pages = <int>{};
    for (var part in input.split(',')) {
      part = part.trim();
      if (part.contains('-')) {
        final r = part.split('-');
        final s = int.tryParse(r[0].trim()), e = int.tryParse(r.length > 1 ? r[1].trim() : '');
        if (s != null && e != null) {
          for (var i = math.min(s, e); i <= math.max(s, e); i++) {
            if (i >= 1 && i <= maxPages) pages.add(i);
          }
        }
      } else {
        final p = int.tryParse(part);
        if (p != null && p >= 1 && p <= maxPages) pages.add(p);
      }
    }
    return pages.toList()..sort();
  }

  /// Render selected 1-based pages to images.
  static Stream<ui.Image> renderPages(Uint8List pdf, List<int> pages, {double dpi = 288}) async* {
    await for (final r in Printing.raster(pdf, pages: pages.map((p) => p - 1).toList(), dpi: dpi)) {
      yield await r.toImage();
    }
  }

  /// Build a PDF where each JPEG gets its own page sized to the image
  /// (jsPDF(orientation, 'px', [w, h]) + addImage at 0,0,w,h).
  static Future<Uint8List> buildImagePdf(List<(Uint8List jpeg, int w, int h)> pages) async {
    final doc = pw.Document();
    for (final p in pages) {
      final fmt = PdfPageFormat(p.$2.toDouble(), p.$3.toDouble());
      doc.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(p.$1), fit: pw.BoxFit.fill, width: fmt.width, height: fmt.height),
      ));
    }
    return doc.save();
  }
}
