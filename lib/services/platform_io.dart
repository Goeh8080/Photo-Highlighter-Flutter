// Mobile / desktop implementations.
import 'dart:io';

import 'package:flutter/foundation.dart';
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

Future<List<Map<String, dynamic>>> runOcrPlatform(Uint8List imageBytes) async =>
    throw UnsupportedError('OCR (tesseract.js) is only available in the web build');

void reloadAppPlatform() {}
