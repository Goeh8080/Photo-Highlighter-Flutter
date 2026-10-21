// Web implementations (browser canvas JPEG encode, anchor download,
// tesseract.js OCR via JS interop).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get isWebPlatform => true;

/// Encode RGBA pixels to JPEG using the browser's native canvas encoder
/// (same as `canvas.toDataURL("image/jpeg", q)` in the original page).
Future<Uint8List> encodeJpegPlatform(Uint8List rgba, int w, int h, double quality) async {
  final canvas = web.HTMLCanvasElement()
    ..width = w
    ..height = h;
  final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
  final data = web.ImageData(Uint8ClampedList.view(rgba.buffer, rgba.offsetInBytes, rgba.lengthInBytes).toJS, w, h.toJS);
  ctx.putImageData(data, 0, 0);
  final url = canvas.toDataURL('image/jpeg', quality.toJS);
  return base64Decode(url.substring(url.indexOf(',') + 1));
}

/// Browser download through a temporary blob URL + <a download>.
Future<void> saveBytesPlatform(Uint8List bytes, String filename, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Timer(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
}

Future<void>? _tessLoading;

Future<void> _ensureTesseract() {
  if (globalContext.has('Tesseract')) return Future.value();
  return _tessLoading ??= () {
    final c = Completer<void>();
    final s = web.HTMLScriptElement()
      ..src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js'
      ..async = true;
    s.onload = ((web.Event _) => c.complete()).toJS;
    s.onerror = ((web.Event _) {
      _tessLoading = null;
      c.completeError(StateError('tesseract.js failed to load'));
    }).toJS;
    web.document.head!.append(s);
    return c.future;
  }();
}

/// Runs `Tesseract.createWorker('eng+hin')` → `recognize()` exactly like the
/// HTML and returns words as `{text, x0, y0, x1, y1}` maps.
Future<List<Map<String, dynamic>>> runOcrPlatform(Uint8List imageBytes) async {
  await _ensureTesseract();
  final tess = globalContext.getProperty<JSObject>('Tesseract'.toJS);
  final worker = await (tess.callMethod<JSPromise<JSObject>>('createWorker'.toJS, 'eng+hin'.toJS)).toDart;
  final dataUrl = 'data:image/jpeg;base64,${base64Encode(imageBytes)}';
  final ret = await (worker.callMethod<JSPromise<JSObject>>('recognize'.toJS, dataUrl.toJS)).toDart;
  await (worker.callMethod<JSPromise<JSAny?>>('terminate'.toJS)).toDart;
  final data = ret.getProperty<JSObject>('data'.toJS);
  final words = data.getProperty<JSArray<JSObject>?>('words'.toJS)?.toDart ?? const <JSObject>[];
  return [
    for (final w in words)
      () {
        final b = w.getProperty<JSObject>('bbox'.toJS);
        double n(String k) => (b.getProperty<JSNumber>(k.toJS)).toDartDouble;
        return {
          'text': (w.getProperty<JSString?>('text'.toJS))?.toDart ?? '',
          'x0': n('x0'),
          'y0': n('y0'),
          'x1': n('x1'),
          'y1': n('y1'),
        };
      }(),
  ];
}

void reloadAppPlatform() => web.window.location.reload();
