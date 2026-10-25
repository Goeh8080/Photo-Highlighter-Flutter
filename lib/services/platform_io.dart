// Mobile / desktop implementations.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

bool get isWebPlatform => false;

Uint8List _encode((Uint8List, int, int, int) a) {
  final im = img.Image.fromBytes(width: a.$2, height: a.$3, bytes: a.$1.buffer, numChannels: 4);
  return img.encodeJpg(im, quality: a.$4);
}

Future<Uint8List> encodeJpegPlatform(Uint8List rgba, int w, int h, double quality) =>
    compute(_encode, (rgba, w, h, (quality * 100).round().clamp(1, 100)));

/// Saves into the app documents folder, then opens the native share sheet so
/// the user can put it in Photos / Files (mobile equivalent of a download).
Future<void> saveBytesPlatform(Uint8List bytes, String filename, String mime) async {
  final dir = await getApplicationDocumentsDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], title: filename));
}

bool _hasDevanagari(String t) {
  var dev = 0, letters = 0;
  for (final r in t.runes) {
    if (r >= 0x0900 && r <= 0x097F) {
      dev++;
      letters++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      letters++;
    }
  }
  return letters > 0 && dev / letters >= 0.2;
}

Future<RecognizedText> _recognize(String path, TextRecognitionScript script) async {
  final rec = TextRecognizer(script: script);
  try {
    return await rec.processImage(InputImage.fromFilePath(path));
  } finally {
    await rec.close();
  }
}

/// On-device OCR (Google ML Kit, no network): Latin first, then the
/// Devanagari/Hindi model; the Devanagari result is used when the page really
/// contains Devanagari text, otherwise the Latin result wins.
Future<List<Map<String, dynamic>>> runOcrPlatform(Uint8List imageBytes) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
  await f.writeAsBytes(imageBytes, flush: true);
  try {
    final latin = await _recognize(f.path, TextRecognitionScript.latin);
    RecognizedText? dev;
    try {
      dev = await _recognize(f.path, TextRecognitionScript.devanagiri);
    } catch (e) {
      debugPrint('Devanagari OCR unavailable: $e');
    }
    final use = (dev != null && _hasDevanagari(dev.text)) ? dev : latin;
    final out = <Map<String, dynamic>>[];
    var lineNo = 0;
    for (final b in use.blocks) {
      for (final l in b.lines) {
        lineNo++;
        final els = l.elements.isEmpty ? <TextElement>[] : l.elements;
        if (els.isEmpty) {
          final r = l.boundingBox;
          out.add({'text': l.text, 'x0': r.left, 'y0': r.top, 'x1': r.right, 'y1': r.bottom, 'line': lineNo});
        }
        for (final e in els) {
          final r = e.boundingBox;
          out.add({'text': e.text, 'x0': r.left, 'y0': r.top, 'x1': r.right, 'y1': r.bottom, 'line': lineNo});
        }
      }
    }
    return out;
  } finally {
    try {
      await f.delete();
    } catch (_) {}
  }
}

void reloadAppPlatform() {}
