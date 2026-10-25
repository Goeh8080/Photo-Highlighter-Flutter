import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/constants.dart';
import '../../models/hl_shape.dart';
import '../../models/photo_item.dart';
import '../../services/edge_detector.dart';
import '../../services/image_ops.dart';
import '../../services/ocr_text.dart';
import '../../services/platform.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';
import '../../widgets/glass_dialog.dart';
import '../../widgets/glass_toast.dart';
import 'editor_windows.dart';
import 'layer_drag.dart';
import 'scan_painter.dart';

/// Port of `#scanModal`: perspective crop ("Scan") and highlight editor
/// ("Highlight"), with zoom/pan, layers, transform pad, OCR, effects…
/// Pops with an updated [PhotoItem] on Apply, or null on Cancel.
class ScanEditorScreen extends StatefulWidget {
  final PhotoItem item;
  final String entryMode; // 'crop' | 'highlight'
  const ScanEditorScreen({super.key, required this.item, required this.entryMode});

  @override
  State<ScanEditorScreen> createState() => _ScanEditorScreenState();
}

class _Bounds {
  Pt start, current;
  List<Pt>? pts;
  double angle;
  Pt center;
  _Bounds({required this.start, required this.current, this.pts, this.angle = 0, required this.center});
}

/// Everything the editor can change on the item while open, so Cancel (or the
/// system back gesture) really discards it.
class _ItemSnapshot {
  final Uint8List orig, display;
  final Uint8List? croppedBase, adjBase;
  final List<Pt>? savedPts;
  final int rotation;
  final double? viewW;
  final AdjSettings adj;
  final List<HlShape> shapes;
  final List<HistoryEntry> history;
  final List<OcrWord> ocr;
  _ItemSnapshot(PhotoItem o)
      : orig = o.orig,
        display = o.display,
        croppedBase = o.croppedBase,
        adjBase = o.adjBase,
        savedPts = o.savedPts?.map((p) => Pt(p.x, p.y)).toList(),
        rotation = o.rotation,
        viewW = o.viewW,
        adj = o.adj.copy(),
        shapes = o.hlShapes.map((e) => e.clone()).toList(),
        history = o.hlRedoStack.map((e) => HistoryEntry.fromJson(e.toJson())).toList(),
        ocr = o.ocrWords.map((w) => OcrWord.fromJson(w.toJson())).toList();

  void restore(PhotoItem o) {
    o
      ..orig = orig
      ..display = display
      ..croppedBase = croppedBase
      ..adjBase = adjBase
      ..savedPts = savedPts
      ..rotation = rotation
      ..viewW = viewW
      ..adj = adj
      ..hlShapes = shapes
      ..hlRedoStack = history
      ..ocrWords = ocr;
  }
}

class _ScanEditorScreenState extends State<ScanEditorScreen> {
  PhotoItem get o => widget.item;
  late final String modalEntryMode = widget.entryMode;
  late String editorMode = widget.entryMode;

  ui.Image? scanImg;
  ui.Image? previewImg; // adjustments preview with B&W pass
  ColorFilter? previewFilter;
  /// `tick` repaints the canvas painter; `overlayTick` rebuilds the (widget)
  /// overlays – OCR boxes, magnifier, text input. A layer drag only bumps
  /// `tick` ([redrawCanvas]) so no widget is rebuilt per pointer move.
  final tick = ValueNotifier<int>(0);
  final overlayTick = ValueNotifier<int>(0);
  void redraw() {
    tick.value++;
    overlayTick.value++;
  }

  void redrawCanvas() => tick.value++;

  // view
  int rotation = 0;
  double sw = 0, sh = 0;
  bool needsReset = true, firstLayout = true;
  bool autoDetectPending = false;
  List<Pt> pts = [];
  double zoom = 1, panX = 0, panY = 0;

  // crop dragging
  int drag = -1, dragEdgeMidIdx = -1;
  List<Pt>? initialDragPts;
  Offset? magPos;

  // touches / pan / pinch
  final Map<int, Offset> touches = {};
  bool isPanning = false;
  double initialPinchDist = 0, initialScale = 1, startX = 0, startY = 0;

  // highlight drawing
  String shapeType = 'rect';
  String prevDrawingType = 'rect';
  String blendMode = 'multiply';
  double thickness = 8;
  int selectedColor = computedColorsList[0].value.toARGB32();
  bool isDrawing = false;
  Pt? shapeStart, shapeCurrent;
  List<Pt> currentLine = [];
  int selected = -1;
  String? hlDragMode;
  int hlResizeHandle = -1;
  Pt? hlDragStart;
  _Bounds? orig;
  bool snapping = false; // off by default: drag follows the finger 1:1
  bool moveTool = false; // explicit liquid-glass "Select/Move" tool
  LayerDrag? _layerDrag; // move drag in progress
  HlShape? _dragBefore; // pre-drag snapshot (history entry on pointer up)
  int _dragIdx = -1;
  bool _dragDirty = false;
  ShapeCache? _dragCache; // pictures of every other layer while dragging
  /// Test/diagnostic counter: number of canvas repaints requested by drags.
  int dragRepaints = 0;
  final _ignoredPointers = <int>{};
  final dupDist = TextEditingController(text: '15');
  double? alignV, alignH;

  // text overlay
  int activeText = -1;
  final textCtl = TextEditingController();
  final textFocus = FocusNode();

  // panels
  bool collapsed = false;
  bool _collapseInit = false;
  late final _ItemSnapshot _snap = _ItemSnapshot(widget.item);
  bool _committed = false;
  String ocrText = '';
  String? _pendingOcrText; // OCR text the user chose to add; burnt in on Done
  bool layersOpen = false;
  final layerLink = LayerLink();
  final _layersBtnKey = GlobalKey();
  bool dpadOpen = false;
  String dpadTab = 'move';
  int nudgeStep = 4;
  bool csOpen = false;
  bool adjOpen = false;
  Map<String, int> adjVals = {};
  ui.Image? adjBaseImg;
  Timer? _adjDebounce;
  bool cpOpen = false;
  bool ocrBusy = false;
  String? busy;

  List<HlShape> get shapes => o.hlShapes;

  @override
  void initState() {
    super.initState();
    _snap; // capture the pre-edit state
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_collapseInit) {
      _collapseInit = true;
      // Small phones start with the compact option set so the photo stays big.
      collapsed = MediaQuery.sizeOf(context).height < 700;
    }
  }

  Future<void> _load() async {
    final bytes = modalEntryMode == 'highlight' ? o.display : o.orig;
    final img = await ImageOps.decode(bytes);
    if (!mounted) return;
    setState(() {
      scanImg = img;
      rotation = modalEntryMode == 'crop' ? o.rotation : 0;
      autoDetectPending = modalEntryMode == 'crop' && (o.savedPts == null || o.savedPts!.length < 4);
      needsReset = true;
    });
  }

  @override
  void dispose() {
    if (!_committed) _snap.restore(widget.item);
    _adjDebounce?.cancel();
    _dragCache?.dispose();
    tick.dispose();
    overlayTick.dispose();
    textCtl.dispose();
    textFocus.dispose();
    super.dispose();
  }

  void toast(String m) => GlassToast.show(context, m);

  // ---------------------------------------------------------------- view
  void _resetView(double maxW, double maxH) {
    final img = scanImg!;
    final isRot = (rotation ~/ 90) % 2 != 0;
    final w = (isRot ? img.height : img.width).toDouble();
    final h = (isRot ? img.width : img.height).toDouble();
    final ratio = math.min(maxW * 0.96 / w, maxH * 0.96 / h);
    sw = w * ratio;
    sh = h * ratio;
    if (modalEntryMode == 'highlight') {
      if (o.viewW != null && (o.viewW! - sw).abs() > 0.5) {
        final k = sw / o.viewW!;
        for (final s in shapes) {
          s.scaleBy(k);
        }
        for (final e in o.hlRedoStack) {
          e.shape?.scaleBy(k);
        }
        o.ocrWords = o.ocrWords.map((w) => w.scaled(k)).toList();
      }
      o.viewW = sw;
    }
    if (o.savedPts != null && o.savedPts!.length == 4) {
      pts = o.savedPts!.map((p) => Pt(p.x * sw, p.y * sh)).toList();
    } else {
      pts = [Pt(0, 0), Pt(sw, 0), Pt(sw, sh), Pt(0, sh)];
      o.savedPts = pts.map((p) => Pt(p.x / sw, p.y / sh)).toList();
    }
    if (modalEntryMode == 'crop') o.rotation = rotation;
    needsReset = false;
    if (autoDetectPending) {
      autoDetectPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => runAutoEdgeDetection(silent: true));
    }
  }

  /// Unclamped canvas coordinates – used for layer drags so the layer follows
  /// the finger 1:1 even when the finger leaves the image area.
  Pt rawCoords(Offset l) => Pt((l.dx - (sw / 2 + panX)) / zoom, (l.dy - (sh / 2 + panY)) / zoom);

  Pt canvasCoords(Offset l) {
    var x = (l.dx - (sw / 2 + panX)) / zoom;
    var y = (l.dy - (sh / 2 + panY)) / zoom;
    x = x.clamp(-sw / 2, sw / 2);
    y = y.clamp(-sh / 2, sh / 2);
    return Pt(x, y);
  }

  static Pt applyRotation(Pt p, Pt c, double angle) {
    final r = angle * math.pi / 180;
    final dx = p.x - c.x, dy = p.y - c.y;
    return Pt(c.x + dx * math.cos(r) - dy * math.sin(r), c.y + dx * math.sin(r) + dy * math.cos(r));
  }

  HlShape? get _drawingPreview {
    if (editorMode != 'highlight' || !isDrawing || shapeStart == null || shapeCurrent == null || shapeType == 'select') return null;
    return HlShape(
      type: shapeType,
      color: shapeType == 'text' ? 0xFF000000 : selectedColor,
      start: shapeStart,
      current: shapeCurrent,
      pts: shapeType == 'free' ? currentLine : null,
      thickness: thickness,
      blendMode: blendMode,
    );
  }

  ScanViewState _view() => ScanViewState(
        image: previewImg ?? scanImg!,
        previewFilter: previewImg != null ? null : previewFilter,
        rotation: rotation,
        sw: sw,
        sh: sh,
        zoom: zoom,
        panX: panX,
        panY: panY,
        shapes: shapes,
        drawing: _drawingPreview,
        editorMode: editorMode,
        selectedIndex: selected,
        dpadOpen: dpadOpen,
        pts: pts,
        cache: _dragCache,
      );

  // ---------------------------------------------------------------- helpers
  void hideTextInput() {
    if (activeText >= 0 && activeText < shapes.length) shapes[activeText].textValue = textCtl.text;
    if (activeText != -1) {
      activeText = -1;
      textCtl.clear();
      textFocus.unfocus();
    }
  }

  void showTextInputForShape(int i) {
    final s = shapes[i];
    if (s.type != 'text') return;
    activeText = i;
    textCtl.text = s.textValue ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => textFocus.requestFocus());
  }

  void handleShapeTypeChange() {
    hideTextInput();
    if (shapeType != 'select') prevDrawingType = shapeType;
    setState(() {});
    redraw();
  }

  void _syncSliderFromShape(HlShape s) {
    if (s.thickness > 0) {
      thickness = s.thickness.clamp(2, 100);
    } else if (s.type == 'text') {
      thickness = s.fontSize.clamp(2, 100);
    }
    blendMode = s.blendMode;
  }

  void _pushEdit(int idx) => o.hlRedoStack.add(HistoryEntry('edit', index: idx, shape: shapes[idx].clone()));

  void setEditorMode(String m) {
    hideTextInput();
    editorMode = modalEntryMode == 'crop' ? 'crop' : m;
    dpadOpen = false;
    setState(() {});
    redraw();
  }

  // ---------------------------------------------------------------- layer drag
  /// Finger slop (canvas units) for selecting a layer. Thin strokes and text
  /// always get the full 24 px; filled shapes get a tighter slop while a
  /// drawing tool is active so they do not swallow the start of a new shape.
  double _hitTol(HlShape s) {
    final full = 24 / zoom;
    if (moveTool || s.type == 'free' || s.type == 'free_straight' || s.type == 'text') return full;
    return 8 / zoom;
  }

  int _hitLayer(Pt world) {
    for (var i = shapes.length - 1; i >= 0; i--) {
      if (shapes[i].hitTest(world, _hitTol(shapes[i]))) return i;
    }
    return -1;
  }

  void _beginDrag(String mode, int idx, Pt pt, Pt raw) {
    hideTextInput();
    selected = idx;
    hlDragMode = mode;
    hlDragStart = pt;
    _dragIdx = idx;
    _dragDirty = false;
    final s = shapes[idx];
    _dragBefore = s.clone();
    _dragCache?.dispose();
    _dragCache = ShapeCache(shapes, idx);
    if (mode == 'move') {
      _layerDrag = LayerDrag(idx, s, raw);
    }
  }

  /// Pointer up / second finger: commit ONE history entry (only if the layer
  /// really changed), release the picture cache.
  void _endDrag() {
    if (_dragBefore != null && _dragDirty && _dragIdx >= 0 && _dragIdx < shapes.length) {
      o.hlRedoStack.add(HistoryEntry('edit', index: _dragIdx, shape: _dragBefore));
    }
    _dragBefore = null;
    _layerDrag = null;
    _dragIdx = -1;
    _dragCache?.dispose();
    _dragCache = null;
    hlDragMode = null;
  }

  // ---------------------------------------------------------------- pointer
  void _onDown(PointerDownEvent e) {
    if (scanImg == null) return;
    if (layersOpen) setState(() => layersOpen = false);
    touches[e.pointer] = e.localPosition;
    if (touches.length == 2 && hlDragMode != null) {
      // Zoom & pan are disabled while a layer is being dragged: a stray second
      // finger is ignored instead of hijacking the drag.
      touches.remove(e.pointer);
      _ignoredPointers.add(e.pointer);
      return;
    }
    if (touches.length == 2) {
      hideTextInput();
      isPanning = false;
      drag = -1;
      dragEdgeMidIdx = -1;
      isDrawing = false;
      _endDrag();
      final a = touches.values.first, b = touches.values.last;
      initialPinchDist = (a - b).distance;
      initialScale = zoom;
      final mid = (a + b) / 2;
      startX = mid.dx - panX;
      startY = mid.dy - panY;
      return;
    }
    final l = e.localPosition;
    final pt = canvasCoords(l);
    final raw = rawCoords(l);
    var type = shapeType;

    if (editorMode == 'zoom') {
      hideTextInput();
      isPanning = true;
      startX = l.dx - panX;
      startY = l.dy - panY;
    } else if (editorMode == 'highlight') {
      if (selected >= 0 && selected < shapes.length) {
        final s = shapes[selected];
        final c = s.center();
        final angle = s.angle;
        final tc = s.handles()[1];
        final rp = applyRotation(Pt(tc.x, tc.y - 25 / zoom), c, angle);
        final sx = rp.x * zoom + (sw / 2 + panX), sy = rp.y * zoom + (sh / 2 + panY);
        if ((Offset(sx, sy) - l).distance < 25) {
          _beginDrag('rotate', selected, pt, raw);
          orig = _Bounds(start: Pt(0, 0), current: Pt(0, 0), angle: angle, center: c);
          return;
        }
        var found = -1;
        final hs = s.handles();
        for (var i = 0; i < hs.length; i++) {
          final rh = applyRotation(hs[i], c, angle);
          if ((Offset(rh.x * zoom + sw / 2 + panX, rh.y * zoom + sh / 2 + panY) - l).distance < 25) found = i;
        }
        if (found >= 0) {
          _beginDrag('resize', selected, pt, raw);
          hlResizeHandle = found;
          orig = _Bounds(
            start: s.start?.copy() ?? Pt(0, 0),
            current: s.current?.copy() ?? Pt(0, 0),
            pts: s.pts?.map((p) => p.copy()).toList(),
            angle: angle,
            center: c,
          );
          return;
        }
      }
      // Top-most layer under the finger (precise geometry + finger slop).
      var tapped = _hitLayer(raw);
      if (tapped < 0 && selected >= 0 && selected < shapes.length) {
        // Fallback: inside the selected layer's (rotated) bounds ±slop.
        final s = shapes[selected];
        final up = applyRotation(raw, s.center(), -s.angle);
        final b = s.bounds();
        final t = 10 / zoom;
        if (up.x >= b[0] - t && up.x <= b[2] + t && up.y >= b[1] - t && up.y <= b[3] + t) tapped = selected;
      }
      if (tapped >= 0) {
        // Start moving IMMEDIATELY on pointer-down (raw Listener events, no
        // gesture arena). No setState here: only the canvas repaints; the
        // toolbar/layer-list refresh once on pointer-up.
        shapeType = 'select';
        _syncSliderFromShape(shapes[tapped]);
        _beginDrag('move', tapped, pt, raw);
        redrawCanvas();
        return;
      } else if (type == 'select') {
        hideTextInput();
        selected = -1;
        if (moveTool) {
          // Select/Move tool: an empty tap only deselects, never draws.
          setState(() {});
          redraw();
          return;
        }
        shapeType = prevDrawingType;
        type = shapeType;
        handleShapeTypeChange();
      }
      if (type != 'select') {
        hideTextInput();
        selected = -1;
        isDrawing = true;
        shapeStart = pt;
        shapeCurrent = pt;
        currentLine = [pt];
        handleShapeTypeChange();
      }
    } else if (editorMode == 'crop') {
      var hit = -1;
      final c8 = crop8Points(pts);
      for (var i = 0; i < c8.length; i++) {
        final sx = (c8[i].$1 - sw / 2) * zoom + (sw / 2 + panX);
        final sy = (c8[i].$2 - sh / 2) * zoom + (sh / 2 + panY);
        if ((Offset(sx, sy) - l).distance < 36) hit = i; // 72 px grab area
      }
      if (hit >= 0) {
        initialDragPts = pts.map((p) => p.copy()).toList();
        startX = l.dx;
        startY = l.dy;
        if (c8[hit].$3) {
          drag = c8[hit].$4;
          dragEdgeMidIdx = -1;
        } else {
          drag = -1;
          dragEdgeMidIdx = c8[hit].$4;
        }
        magPos = l;
        setState(() {});
      }
    }
    redraw();
  }

  void _onMove(PointerMoveEvent e) {
    if (!touches.containsKey(e.pointer)) return;
    touches[e.pointer] = e.localPosition;
    if (touches.length >= 2) {
      hideTextInput();
      final a = touches.values.elementAt(0), b = touches.values.elementAt(1);
      final d = (a - b).distance;
      if (initialPinchDist > 0) zoom = (initialScale * (d / initialPinchDist)).clamp(0.4, 8);
      final mid = (a + b) / 2;
      panX = mid.dx - startX;
      panY = mid.dy - startY;
      redraw();
      return;
    }
    final l = e.localPosition;
    final pt = canvasCoords(l);
    if (isPanning && touches.length == 1) {
      panX = l.dx - startX;
      panY = l.dy - startY;
      redraw();
    } else if (editorMode == 'highlight' && hlDragMode == 'move' && _layerDrag != null && _dragIdx >= 0 && _dragIdx < shapes.length) {
      // 1:1 direct manipulation: position = original + (pointer - pointerAtDown)
      final d = _layerDrag!;
      d.update(rawCoords(l));
      alignV = null;
      alignH = null;
      if (snapping) {
        // optional *soft* snap (6 px) to other layers' centres
        final th = 6 / zoom;
        final s = d.shape;
        final cc = s.center();
        double sx = 0, sy = 0;
        for (var t = 0; t < shapes.length; t++) {
          if (t == _dragIdx) continue;
          final tc = shapes[t].center();
          if ((cc.x - tc.x).abs() < th) {
            sx = tc.x - cc.x;
            alignV = sw / 2 + panX + tc.x * zoom;
          }
          if ((cc.y - tc.y).abs() < th) {
            sy = tc.y - cc.y;
            alignH = sh / 2 + panY + tc.y * zoom;
          }
        }
        if (sx != 0 || sy != 0) d.update(rawCoords(l), snapX: sx, snapY: sy);
      }
      _dragDirty = d.moved;
      dragRepaints++;
      if (alignV != null || alignH != null) {
        redraw();
      } else {
        redrawCanvas();
      }
    } else if (editorMode == 'highlight' && hlDragMode != null && selected >= 0 && orig != null) {
      final s = shapes[selected];
      _dragDirty = true;
      if (hlDragMode == 'rotate') {
        final c = orig!.center;
        final a0 = math.atan2(hlDragStart!.y - c.y, hlDragStart!.x - c.x);
        final a1 = math.atan2(pt.y - c.y, pt.x - c.x);
        s.angle = (orig!.angle + (a1 - a0) * 180 / math.pi) % 360;
      } else if (hlDragMode == 'resize') {
        final c = orig!.center, angle = orig!.angle;
        final up = applyRotation(pt, c, -angle), us = applyRotation(hlDragStart!, c, -angle);
        var minX = math.min(orig!.start.x, orig!.current.x), maxX = math.max(orig!.start.x, orig!.current.x);
        var minY = math.min(orig!.start.y, orig!.current.y), maxY = math.max(orig!.start.y, orig!.current.y);
        final dx = up.x - us.x, dy = up.y - us.y;
        final h = hlResizeHandle;
        if ([0, 6, 7].contains(h)) minX += dx;
        if ([2, 3, 4].contains(h)) maxX += dx;
        if ([0, 1, 2].contains(h)) minY += dy;
        if ([4, 5, 6].contains(h)) maxY += dy;
        if (s.type == 'free' && s.pts != null && orig!.pts != null && orig!.pts!.isNotEmpty) {
          final op = orig!.pts!;
          final oMinX = op.map((p) => p.x).reduce(math.min), oMaxX = op.map((p) => p.x).reduce(math.max);
          final oMinY = op.map((p) => p.y).reduce(math.min), oMaxY = op.map((p) => p.y).reduce(math.max);
          var nMinX = oMinX, nMaxX = oMaxX, nMinY = oMinY, nMaxY = oMaxY;
          if ([0, 6, 7].contains(h)) nMinX += dx;
          if ([2, 3, 4].contains(h)) nMaxX += dx;
          if ([0, 1, 2].contains(h)) nMinY += dy;
          if ([4, 5, 6].contains(h)) nMaxY += dy;
          final ow = math.max(1.0, oMaxX - oMinX), oh = math.max(1.0, oMaxY - oMinY);
          final cw = math.max(5.0, nMaxX - nMinX), ch = math.max(5.0, nMaxY - nMinY);
          s.pts = op.map((p) => Pt(nMinX + (p.x - oMinX) / ow * cw, nMinY + (p.y - oMinY) / oh * ch)).toList();
          s.start = Pt(nMinX, nMinY);
          s.current = Pt(nMaxX, nMaxY);
        } else {
          s.start = Pt(minX, minY);
          s.current = Pt(maxX, maxY);
        }
      }
      dragRepaints++;
      redrawCanvas();
    } else if (isDrawing && shapeType != 'select') {
      shapeCurrent = pt;
      if (editorMode == 'highlight' && shapeType == 'free') currentLine.add(pt);
      if (editorMode == 'highlight' && shapeType == 'free_straight') currentLine = [shapeStart!, pt];
      redraw();
    } else if (editorMode == 'crop') {
      if (drag >= 0) {
        var px = (l.dx - (sw / 2 + panX)) / zoom + sw / 2;
        var py = (l.dy - (sh / 2 + panY)) / zoom + sh / 2;
        px = px.clamp(0, sw);
        py = py.clamp(0, sh);
        pts[drag] = Pt(px, py);
        o.savedPts = pts.map((p) => Pt(p.x / sw, p.y / sh)).toList();
        magPos = l;
        redraw();
      } else if (dragEdgeMidIdx >= 0 && initialDragPts != null) {
        final ddx = (l.dx - startX) / zoom, ddy = (l.dy - startY) / zoom;
        final i1 = dragEdgeMidIdx, i2 = (dragEdgeMidIdx + 1) % 4;
        pts[i1] = Pt((initialDragPts![i1].x + ddx).clamp(0, sw), (initialDragPts![i1].y + ddy).clamp(0, sh));
        pts[i2] = Pt((initialDragPts![i2].x + ddx).clamp(0, sw), (initialDragPts![i2].y + ddy).clamp(0, sh));
        o.savedPts = pts.map((p) => Pt(p.x / sw, p.y / sh)).toList();
        magPos = l;
        redraw();
      }
    }
  }

  void _onUp(PointerEvent e) {
    if (_ignoredPointers.remove(e.pointer)) return;
    alignV = null;
    alignH = null;
    if (isDrawing && shapeType != 'select') {
      if (editorMode == 'highlight') {
        final t = shapeType;
        final ns = HlShape(
          type: t,
          color: t == 'text' ? 0xFF000000 : selectedColor,
          start: shapeStart,
          current: shapeCurrent,
          pts: t == 'free' ? currentLine : null,
          thickness: thickness,
          angle: 0,
          blendMode: blendMode,
          textValue: t == 'text' ? '' : null,
          fontSize: t == 'text' ? thickness : 16,
        );
        shapes.add(ns);
        o.hlRedoStack = [];
        selected = shapes.length - 1;
        shapeType = 'select';
        handleShapeTypeChange();
        if (t == 'text') showTextInputForShape(selected);
      }
    } else if (editorMode == 'highlight' && hlDragMode != null && selected >= 0 && selected < shapes.length) {
      // A tap on a text layer (no movement) opens the keyboard; dragging it doesn't.
      if (shapes[selected].type == 'text' && !_dragDirty) showTextInputForShape(selected);
    }
    if (hlDragMode != null) _endDrag();
    touches.remove(e.pointer);
    if (touches.length == 1) {
      final r = touches.values.first;
      startX = r.dx - panX;
      startY = r.dy - panY;
    } else if (touches.isEmpty) {
      isPanning = false;
      initialPinchDist = 0;
    }
    drag = -1;
    dragEdgeMidIdx = -1;
    initialDragPts = null;
    isDrawing = false;
    hlDragMode = null;
    magPos = null;
    setState(() {});
    redraw();
  }

  void _onSignal(PointerSignalEvent e) {
    // Desktop nicety (not in the HTML): mouse-wheel zoom around the cursor.
    if (e is PointerScrollEvent) {
      final f = e.scrollDelta.dy > 0 ? 0.9 : 1.1;
      final nz = (zoom * f).clamp(0.4, 8.0);
      final l = e.localPosition;
      final cx = (l.dx - (sw / 2 + panX)) / zoom, cy = (l.dy - (sh / 2 + panY)) / zoom;
      zoom = nz;
      panX = l.dx - sw / 2 - cx * zoom;
      panY = l.dy - sh / 2 - cy * zoom;
      hideTextInput();
      redraw();
    }
  }

  // ---------------------------------------------------------------- actions
  void applyColorLogic(int argb) {
    selectedColor = argb;
    blendMode = 'multiply';
    if (selected >= 0 && selected < shapes.length) {
      _pushEdit(selected);
      shapes[selected].color = selectedColor;
      shapes[selected].blendMode = blendMode;
    }
    setState(() {});
    redraw();
  }

  void changeLayerBlendMode(String m) {
    blendMode = m;
    if (selected >= 0 && selected < shapes.length) shapes[selected].blendMode = m;
    setState(() {});
    redraw();
  }

  void onThickness(double v) {
    thickness = v.roundToDouble();
    if (selected >= 0 && selected < shapes.length) {
      final s = shapes[selected];
      if (s.type == 'text') {
        s.fontSize = thickness;
      } else {
        s.thickness = thickness;
      }
    }
    setState(() {});
    redraw();
  }

  void nudgeShape(double dx, double dy) {
    if (selected < 0 || selected >= shapes.length) return;
    _pushEdit(selected);
    final s = shapes[selected];
    s.start?.x += dx;
    s.start?.y += dy;
    s.current?.x += dx;
    s.current?.y += dy;
    if (s.type == 'free' && s.pts != null) {
      for (final p in s.pts!) {
        p.x += dx;
        p.y += dy;
      }
    }
    redraw();
  }

  void singleEdgeResize(String edge, double delta) {
    if (selected < 0 || selected >= shapes.length) return;
    final s = shapes[selected];
    _pushEdit(selected);
    if (!(s.type == 'free' && s.pts != null && s.pts!.isNotEmpty) && (s.start == null || s.current == null)) return;
    final b = s.bounds();
    var minX = b[0], minY = b[1], maxX = b[2], maxY = b[3];
    final oldW = math.max(1.0, maxX - minX), oldH = math.max(1.0, maxY - minY), oMinX = minX, oMinY = minY;
    if (edge == 'left') {
      minX += delta;
      if (minX >= maxX - 2) minX = maxX - 2;
    } else if (edge == 'right') {
      maxX += delta;
      if (maxX <= minX + 2) maxX = minX + 2;
    } else if (edge == 'top') {
      minY += delta;
      if (minY >= maxY - 2) minY = maxY - 2;
    } else if (edge == 'bottom') {
      maxY += delta;
      if (maxY <= minY + 2) maxY = minY + 2;
    }
    final nw = math.max(2.0, maxX - minX), nh = math.max(2.0, maxY - minY);
    if (s.type == 'free' && s.pts != null && s.pts!.isNotEmpty) {
      s.pts = s.pts!.map((p) => Pt(minX + (p.x - oMinX) / oldW * nw, minY + (p.y - oMinY) / oldH * nh)).toList();
    }
    s.start = Pt(minX, minY);
    s.current = Pt(maxX, maxY);
    redraw();
  }

  void centerSelectedShape() {
    if (selected < 0 || selected >= shapes.length) return;
    final c = shapes[selected].center();
    nudgeShape(-c.x, -c.y);
  }

  void deleteLayer(int idx) {
    hideTextInput();
    final d = shapes.removeAt(idx);
    o.hlRedoStack.add(HistoryEntry('delete', index: idx, shape: d));
    if (selected == idx) {
      selected = -1;
      dpadOpen = false;
    } else if (selected > idx) {
      selected--;
    }
    if (selected == -1) shapeType = prevDrawingType;
    handleShapeTypeChange();
  }

  Future<void> duplicateSelectedLayer() async {
    if (selected < 0 || selected >= shapes.length) {
      await showGlassAlert(context, 'Please select a layer first to duplicate!');
      return;
    }
    hideTextInput();
    final dist = double.tryParse(dupDist.text) ?? 15;
    final d = shapes[selected].clone();
    d.start?.y += dist;
    d.current?.y += dist;
    if (d.type == 'free' && d.pts != null) d.pts = d.pts!.map((p) => Pt(p.x + dist, p.y + dist)).toList();
    shapes.add(d);
    o.hlRedoStack.add(HistoryEntry('add', shape: d));
    selected = shapes.length - 1;
    setState(() {});
    redraw();
  }

  void undoHighlight() {
    hideTextInput();
    final st = o.hlRedoStack;
    if (st.isNotEmpty && st.last.action == 'edit') {
      final e = st.removeLast();
      if (e.index! < shapes.length) {
        st.add(HistoryEntry('edit', index: e.index, shape: shapes[e.index!].clone()));
        shapes[e.index!] = e.shape!;
        selected = e.index!;
      }
      setState(() {});
      redraw();
      return;
    }
    if (shapes.isEmpty && st.isNotEmpty && st.last.action == 'delete') {
      final e = st.removeLast();
      shapes.insert(e.index!.clamp(0, shapes.length), e.shape!);
      st.add(HistoryEntry('insert', index: e.index));
      selected = e.index!.clamp(0, shapes.length - 1);
      handleShapeTypeChange();
      return;
    }
    if (shapes.isNotEmpty) {
      final p = shapes.removeLast();
      st.add(HistoryEntry('add', shape: p));
      selected = -1;
      dpadOpen = false;
      handleShapeTypeChange();
    }
  }

  void redoHighlight() {
    hideTextInput();
    final st = o.hlRedoStack;
    if (st.isEmpty) return;
    final e = st.removeLast();
    switch (e.action) {
      case 'add':
        shapes.add(e.shape!);
        break;
      case 'delete':
      case 'insert':
        if (e.index! < shapes.length) shapes.removeAt(e.index!);
        selected = -1;
        dpadOpen = false;
        break;
      case 'edit':
        if (e.index! < shapes.length) {
          final cur = shapes[e.index!];
          shapes[e.index!] = e.shape!;
          st.add(HistoryEntry('edit', index: e.index, shape: cur.clone()));
          selected = e.index!;
        }
        break;
    }
    handleShapeTypeChange();
  }

  void openDPad() {
    if (selected < 0 && shapes.isNotEmpty) {
      selected = shapes.length - 1;
      shapeType = 'select';
      handleShapeTypeChange();
    }
    setState(() => dpadOpen = true);
    redraw();
  }

  void selectLayer(int idx) {
    hideTextInput();
    selected = idx;
    shapeType = 'select';
    layersOpen = false;
    _syncSliderFromShape(shapes[idx]);
    handleShapeTypeChange();
    if (shapes[idx].type == 'text') showTextInputForShape(idx);
  }

  void noCrop() {
    pts = [Pt(0, 0), Pt(sw, 0), Pt(sw, sh), Pt(0, sh)];
    o.savedPts = pts.map((p) => Pt(p.x / sw, p.y / sh)).toList();
    redraw();
  }

  void rotateScan() {
    hideTextInput();
    setState(() {
      rotation = (rotation + 90) % 360;
      zoom = 1;
      panX = 0;
      panY = 0;
      selected = -1;
      dpadOpen = false;
      needsReset = true;
    });
  }

  Future<void> runAutoEdgeDetection({bool silent = false}) async {
    if (scanImg == null) return;
    setState(() => busy = '✨ Detecting edges…');
    try {
      final rot = await ImageOps.rotated(scanImg!, rotation);
      final q = await EdgeDetector.detect(rot);
      if (q != null) {
        final rx = sw / rot.width, ry = sh / rot.height;
        pts = q.map((p) => Pt(p.dx * rx, p.dy * ry)).toList();
        o.savedPts = pts.map((p) => Pt(p.x / sw, p.y / sh)).toList();
      } else if (!silent && mounted) {
        toast('No clear document edges found');
      }
    } finally {
      if (mounted) setState(() => busy = null);
      redraw();
    }
  }

  Future<void> applyCanvasSize(double rw, double rh, String unit) async {
    if (rw == 0 && rh == 0) {
      setState(() => csOpen = false);
      return;
    }
    final k = unitScale(unit);
    setState(() => busy = 'Resizing canvas…');
    final out = await ImageOps.resizeCanvas(scanImg!, rw * k, rh * k);
    final jpg = await ImageOps.encodeJpeg(out, 0.95);
    if (!mounted) return;
    o.orig = jpg;
    if (modalEntryMode == 'crop') {
      o.display = jpg;
      o.adjBase = null;
    }
    setState(() {
      scanImg = out;
      csOpen = false;
      needsReset = true;
      busy = null;
    });
    toast('Photo Canvas Resized!');
  }

  // ---- adjustments
  Future<void> openAdjustments() async {
    final base = o.adjBase != null ? await ImageOps.decode(o.adjBase!) : scanImg!;
    setState(() {
      adjBaseImg = base;
      adjVals = Map.of(o.adj.toJson().cast<String, int>());
      adjOpen = true;
    });
  }

  AdjSettings get _adjFromVals => AdjSettings.fromJson(adjVals);

  void onAdjChanged(String key, int v) {
    adjVals[key] = v;
    if (key == 'colorScan') adjVals['bwScan'] = 0;
    if (key == 'bwScan') adjVals['colorScan'] = 0;
    setState(() {});
    _previewAdjustments();
  }

  void _previewAdjustments() {
    final s = _adjFromVals;
    final base = adjBaseImg ?? scanImg!;
    if (s.bwScan == 0) {
      previewImg = identical(base, scanImg) ? null : base;
      previewFilter = s.isIdentity ? null : ColorFilter.matrix(ImageOps.adjustMatrix(s));
      redraw();
      return;
    }
    _adjDebounce?.cancel();
    _adjDebounce = Timer(const Duration(milliseconds: 90), () async {
      final img = await ImageOps.adjust(base, s, maxDim: 1400);
      if (!mounted || !adjOpen) return;
      previewImg = img;
      previewFilter = null;
      redraw();
    });
  }

  void closeAdjustments() {
    _adjDebounce?.cancel();
    setState(() {
      adjOpen = false;
      previewImg = null;
      previewFilter = null;
      adjBaseImg = null;
    });
    redraw();
  }

  Future<void> applyAdjustments() async {
    final s = _adjFromVals;
    final base = adjBaseImg ?? scanImg!;
    setState(() => busy = 'Applying effects…');
    final full = await ImageOps.adjust(base, s);
    final jpg = await ImageOps.encodeJpeg(full, 0.95);
    o.adjBase ??= o.display;
    o.display = jpg;
    o.adj = s;
    scanImg = full;
    closeAdjustments();
    setState(() => busy = null);
  }

  // ---- OCR
  Future<void> runOCRScan() async {
    if (ocrBusy) return;
    setState(() => ocrBusy = true);
    try {
      final rot = await ImageOps.rotated(scanImg!, rotation);
      // For crop mode OCR the *cropped* region (what Done will produce) is read.
      var src = rot;
      if (modalEntryMode == 'crop' && pts.length == 4) {
        final rx = rot.width / sw, ry = rot.height / sh;
        final q = pts.map((p) => Offset(p.x * rx, p.y * ry)).toList();
        final w = math.max(1, math.max((q[1] - q[0]).distance, (q[2] - q[3]).distance).floor());
        final h = math.max(1, math.max((q[1] - q[2]).distance, (q[0] - q[3]).distance).floor());
        if (w > 16 && h > 16) src = await ImageOps.perspectiveWarp(rot, q, w, h);
      }
      final bytes = await ImageOps.encodeJpeg(src, 0.92);
      final words = await runOcrPlatform(bytes);
      ocrText = ocrTextFromWords(words);
      if (modalEntryMode != 'crop') {
        final sx = sw / src.width, sy = sh / src.height;
        o.ocrWords = [
          for (final w in words)
            OcrWord(
              text: w['text'] as String,
              x: (w['x0'] as double) * sx - sw / 2,
              y: (w['y1'] as double) * sy - sh / 2,
              w: ((w['x1'] as double) - (w['x0'] as double)) * sx,
              h: ((w['y1'] as double) - (w['y0'] as double)) * sy,
            ),
        ];
      }
      if (mounted) {
        setState(() => ocrBusy = false);
        redraw();
        if (ocrText.trim().isEmpty) {
          toast('No text found in this image');
        } else {
          await _showOcrSheet();
        }
      }
    } catch (e, st) {
      debugPrint('OCR failed: $e\n$st');
      if (mounted) await showGlassAlert(context, 'OCR karne me error aayi!\n$e');
    } finally {
      if (mounted) setState(() => ocrBusy = false);
      redraw();
    }
  }

  /// Liquid-glass result sheet: Copy / Share / add as a text layer.
  Future<void> _showOcrSheet() async {
    final p = AppThemeScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GlassContainer(
            radius: 22,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Material(
              type: MaterialType.transparency,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('📄 Recognized Text', style: TextStyle(color: p.textMain, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.4),
                  child: SingleChildScrollView(
                    child: SelectableText(ocrText, key: const Key('ocrResultText'), style: TextStyle(color: p.textMain, fontSize: 14, height: 1.35)),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  SizedBox(
                    height: 44,
                    child: GlassButton(
                      label: 'Copy',
                      emoji: '📋',
                      color: AppColors.blue,
                      bold: true,
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: ocrText));
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        toast('Text copied');
                      },
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: GlassButton(
                      label: 'Share',
                      emoji: '📤',
                      color: AppColors.teal,
                      bold: true,
                      onTap: () async {
                        try {
                          await SharePlus.instance.share(ShareParams(text: ocrText));
                        } catch (e) {
                          toast('Share failed');
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: GlassButton(
                      label: modalEntryMode == 'crop' ? 'Add to photo on Done' : 'Add as text layer',
                      emoji: '🔤',
                      color: AppColors.green,
                      bold: true,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _applyOcrText();
                      },
                    ),
                  ),
                  SizedBox(height: 44, child: GlassButton(label: 'Close', color: AppColors.darkGrey, onTap: () => Navigator.of(ctx).pop())),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Highlight editor: add the text as a normal movable layer. Crop editor:
  /// remember it and burn it into the photo when Done is pressed.
  void _applyOcrText() {
    if (ocrText.trim().isEmpty) return;
    if (modalEntryMode == 'highlight') {
      final sh0 = ocrTextLayer(ocrText, sw, sh, 0xFF000000);
      shapes.add(sh0);
      o.hlRedoStack = [];
      selected = shapes.length - 1;
      setState(() {});
      redraw();
      toast('Text layer added');
    } else {
      _pendingOcrText = ocrText;
      toast('Text will be added to the photo when you press Done');
    }
  }

  void toggleOcrWord(int idx) {
    final w = o.ocrWords[idx];
    w.highlighted = !w.highlighted;
    if (w.highlighted) {
      shapes.add(HlShape(
        type: 'rect',
        color: selectedColor,
        start: Pt(w.x, w.y - w.h),
        current: Pt(w.x + w.w, w.y),
        thickness: 1,
        blendMode: 'multiply',
        isOCR: true,
        ocrIdx: idx,
      ));
    } else {
      final si = shapes.indexWhere((s) => s.isOCR && s.ocrIdx == idx);
      if (si >= 0) shapes.removeAt(si);
    }
    setState(() {});
    redraw();
  }

  void clearOCRHighlights() {
    for (final w in o.ocrWords) {
      w.highlighted = false;
    }
    o.hlShapes = shapes.where((s) => !s.isOCR).toList();
    setState(() {});
    redraw();
  }

  // ---- apply / close
  Future<void> applyScan() async {
    if (busy != null || scanImg == null) return;
    hideTextInput();
    dpadOpen = false;
    if (adjOpen) closeAdjustments();
    final img = scanImg!;
    setState(() => busy = 'Applying…');
    try {
      PhotoItem result;
      if (modalEntryMode == 'highlight') {
        final w = img.width, h = img.height;
        final sf = w / sw;
        final all = [...shapes];
        final out = await ImageOps.render(w, h, (c) {
          ImageOps.drawImageTo(c, img, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
          if (all.isNotEmpty) {
            c.save();
            c.translate(w / 2, h / 2);
            c.scale(sf);
            HighlightRenderer.paintAll(c, all, layerBounds: Rect.fromLTWH(-sw / 2, -sh / 2, sw, sh));
            c.restore();
          }
        });
        final jpg = await ImageOps.encodeJpeg(out, 0.95);
        result = PhotoItem(
          src: jpg,
          image: out,
          orig: o.orig,
          display: o.display,
          croppedBase: o.croppedBase,
          savedPts: o.savedPts,
          rotation: o.rotation,
          hlShapes: shapes.map((s) => s.clone()).toList(),
          hlRedoStack: List.of(o.hlRedoStack),
          ocrWords: o.ocrWords.map((w) => OcrWord.fromJson(w.toJson())).toList(),
          scanPhotoCount: o.scanPhotoCount,
          adj: o.adj.copy(),
          viewW: o.viewW,
          adjBase: o.adjBase,
        );
      } else {
        final rot = await ImageOps.rotated(img, rotation);
        final w = rot.width.toDouble(), h = rot.height.toDouble();
        final rx = w / sw, ry = h / sh;
        final q = pts.map((p) => Offset(p.x * rx, p.y * ry)).toList();
        final newW = math.max(1, math.max((q[1] - q[0]).distance, (q[2] - q[3]).distance).floor());
        final newH = math.max(1, math.max((q[1] - q[2]).distance, (q[0] - q[3]).distance).floor());
        var out = await ImageOps.perspectiveWarp(rot, q, newW, newH);
        final pending = _pendingOcrText;
        if (pending != null && pending.trim().isNotEmpty) {
          // Burn the OCR text onto the cropped photo (same renderer as layers).
          final cw = out.width, ch = out.height;
          final vw = 360.0, vh = 360.0 * ch / cw;
          final layer = ocrTextLayer(pending, vw, vh, 0xFF000000);
          final base = out;
          out = await ImageOps.render(cw, ch, (c) {
            ImageOps.drawImageTo(c, base, Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()));
            c.save();
            c.translate(cw / 2, ch / 2);
            c.scale(cw / vw);
            HighlightRenderer.paintAll(c, [layer], layerBounds: Rect.fromLTWH(-vw / 2, -vh / 2, vw, vh));
            c.restore();
          });
        }
        final jpg = await ImageOps.encodeJpeg(out, 0.95);
        result = PhotoItem(
          src: jpg,
          image: out,
          orig: o.orig,
          display: jpg,
          croppedBase: jpg,
          savedPts: pts.map((p) => Pt(p.x / sw, p.y / sh)).toList(),
          rotation: rotation,
          scanPhotoCount: o.scanPhotoCount,
          adj: o.adj.copy(),
        );
        if (mounted) toast('Applied • ${out.width}×${out.height}px${_cropIsFullFrame && rotation % 360 == 0 ? ' (full photo – drag the corner handles to crop)' : ''}');
      }
      if (!mounted) return;
      _committed = true;
      Navigator.of(context).pop(result);
    } catch (e, st) {
      debugPrint('applyScan failed: $e\n$st');
      if (mounted) {
        setState(() => busy = null);
        await showGlassAlert(context, 'Photo apply nahi ho paayi.\n$e');
      }
    } finally {
      if (mounted && busy != null) setState(() => busy = null);
    }
  }

  /// Cancel: discard every pending change (restored in [dispose]).
  void closeScan() {
    hideTextInput();
    Navigator.of(context).pop();
  }

  bool get _cropIsFullFrame {
    if (pts.length < 4 || sw == 0 || sh == 0) return false;
    final e = 4.0;
    return pts[0].x.abs() < e && pts[0].y.abs() < e && (pts[2].x - sw).abs() < e && (pts[2].y - sh).abs() < e;
  }

  // ================================================================= UI
  @override
  Widget build(BuildContext context) {
    final p = AppThemeScope.of(context);
    final hl = modalEntryMode == 'highlight';
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(
          child: Column(children: [
            SizedBox(height: MediaQuery.paddingOf(context).top),
            Expanded(child: _canvasArea(p)),
            if (hl && editorMode != 'zoom') _hlToolbar(p),
            _bottomBar(p),
          ]),
        ),
        if (ocrBusy)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 0,
            right: 0,
            child: Center(
              child: GlassContainer(
                radius: 20,
                fill: [AppColors.blue.withValues(alpha: 0.9), AppColors.blue.withValues(alpha: 0.75)],
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: const Text('🔍 Recognizing Text...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.75, end: 1, duration: 700.ms),
            ),
          ),
        if (busy != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 0,
            right: 0,
            child: Center(
              child: GlassContainer(
                radius: 20,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 10),
                  Text(busy!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ]),
              ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.4, curve: Curves.easeOutBack),
            ),
          ),
        if (layersOpen) _layerPanel(p),
        if (dpadOpen)
          DPadWindow(
            title: selected >= 0 && selected < shapes.length ? 'Editing layer ${selected + 1}' : 'Transform Pad',
            tab: dpadTab,
            onTab: (t) => setState(() => dpadTab = t),
            step: nudgeStep,
            onStep: (v) => setState(() => nudgeStep = v),
            onNudge: (dx, dy) => setState(() => nudgeShape(dx, dy)),
            onCenter: () => setState(centerSelectedShape),
            onEdge: (e, d) => setState(() => singleEdgeResize(e, d)),
            onClose: () {
              setState(() => dpadOpen = false);
              redraw();
            },
          ),
        if (csOpen) CanvasSizeWindow(onApply: applyCanvasSize, onClose: () => setState(() => csOpen = false)),
        if (adjOpen)
          AdjustmentsWindow(
            values: adjVals,
            onChanged: onAdjChanged,
            onReset: () {
              adjVals.updateAll((k, v) => 0);
              setState(() {});
              _previewAdjustments();
            },
            onCancel: closeAdjustments,
            onApply: applyAdjustments,
          ),
        if (cpOpen)
          ColorPickerWindow(
            initial: Color(selectedColor),
            onLivePick: (c) {
              if (selected >= 0 && selected < shapes.length) {
                shapes[selected].color = c.toARGB32();
                redraw();
              }
            },
            onInputChange: (c) => applyColorLogic(c.toARGB32()),
            onOk: (c) {
              applyColorLogic(c.toARGB32());
              setState(() => cpOpen = false);
            },
            onCancel: () => setState(() => cpOpen = false),
          ),
      ]),
    );
  }

  Widget _canvasArea(AppPalette p) {
    return Container(
      color: const Color(0xFF111111),
      child: LayoutBuilder(builder: (context, c) {
        if (scanImg == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (needsReset) _resetView(c.maxWidth, c.maxHeight);
        final scale = math.min(1.0, math.min(c.maxWidth / sw, c.maxHeight / sh));
        return Center(
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: sw,
              height: sh,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: Listener(
                    onPointerDown: _onDown,
                    onPointerMove: _onMove,
                    onPointerUp: _onUp,
                    onPointerCancel: _onUp,
                    onPointerSignal: _onSignal,
                    child: MouseRegion(
                      cursor: editorMode == 'zoom' ? SystemMouseCursors.grab : SystemMouseCursors.precise,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0xB3000000), blurRadius: 15)]),
                        child: RepaintBoundary(child: CustomPaint(painter: ScanPainter(_view, tick), size: Size(sw, sh))),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(child: ValueListenableBuilder<int>(valueListenable: overlayTick, builder: (_, _, _) => _overlays())),
              ]),
            ),
          ),
        ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.96, 0.96), curve: Curves.easeOutCubic);
      }),
    );
  }

  Widget _overlays() {
    final kids = <Widget>[];
    final ocr = <Widget>[];
    // OCR word boxes (clipped to the canvas so zoomed/panned boxes don't spill)
    for (var i = 0; i < o.ocrWords.length; i++) {
      final w = o.ocrWords[i];
      ocr.add(Positioned(
        left: sw / 2 + panX + w.x * zoom,
        top: sh / 2 + panY + (w.y - w.h) * zoom,
        width: math.max(1, w.w * zoom),
        height: math.max(1, w.h * zoom),
        child: GestureDetector(
          onTap: () => toggleOcrWord(i),
          child: Tooltip(
            message: w.text,
            waitDuration: const Duration(milliseconds: 600),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: w.highlighted ? const Color(0x8CFFEB3B) : const Color(0x26FFFF00),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: w.highlighted ? const Color(0xFFF39C12) : const Color(0x80FFEB3B), width: 1),
                boxShadow: w.highlighted ? const [BoxShadow(color: Color(0xCCF1C40F), blurRadius: 5)] : null,
              ),
            ),
          ),
        ),
      ));
    }
    if (ocr.isNotEmpty) kids.add(Positioned.fill(child: ClipRect(child: Stack(children: ocr))));
    if (alignV != null) kids.add(Positioned(left: alignV, top: 0, bottom: 0, width: 1, child: const IgnorePointer(child: ColoredBox(color: Color(0xFFFF0055)))));
    if (alignH != null) kids.add(Positioned(top: alignH, left: 0, right: 0, height: 1, child: const IgnorePointer(child: ColoredBox(color: Color(0xFFFF0055)))));
    // text overlay input
    if (activeText >= 0 && activeText < shapes.length) {
      final s = shapes[activeText];
      if (s.start != null && s.current != null) {
        var w = (s.current!.x - s.start!.x).abs(), h = (s.current!.y - s.start!.y).abs();
        if (w < 60) w = 150;
        if (h < 40) h = 50;
        final fs = math.max(12.0, s.fontSize * zoom);
        kids.add(Positioned(
          left: sw / 2 + panX + math.min(s.start!.x, s.current!.x) * zoom,
          top: sh / 2 + panY + math.min(s.start!.y, s.current!.y) * zoom,
          width: w * zoom,
          height: h * zoom,
          child: Material(
            color: Colors.white,
            elevation: 8,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: AppColors.blue, width: 2), borderRadius: BorderRadius.circular(4)),
              child: TextField(
                controller: textCtl,
                focusNode: textFocus,
                maxLines: null,
                expands: true,
                onChanged: (v) {
                  if (activeText >= 0 && activeText < shapes.length) shapes[activeText].textValue = v;
                  redraw();
                },
                style: TextStyle(color: Colors.black, fontSize: fs, fontWeight: FontWeight.bold, height: 1.2),
                decoration: const InputDecoration(
                  hintText: 'Type text here...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.all(6),
                ),
              ),
            ),
          ),
        ));
      }
    }
    // magnifier loupe (140px, 2x)
    if (magPos != null) {
      final off = magPos!.dy < 200 ? 100.0 : -200.0;
      kids.add(Positioned(
        left: (magPos!.dx - 70).clamp(0.0, math.max(0.0, sw - 140)),
        top: (magPos!.dy + off).clamp(0.0, math.max(0.0, sh - 140)),
        width: 140,
        height: 140,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.blue, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 20)],
            ),
            child: ClipOval(child: CustomPaint(painter: ScanPainter(_view, tick, magCenter: magPos))),
          ),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.none, children: kids);
  }

  Widget _hlToolbar(AppPalette p) {
    final hasSel = selected >= 0 && selected < shapes.length;
    Widget lbl(String t) => Text(t, style: TextStyle(fontSize: 11, color: p.textSub));
    final colors = computedColorsList.where((c) => !collapsed || ['yellow', 'green', 'skyblue', 'white'].contains(c.key)).toList();
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.bgHeader.withValues(alpha: 0.78), p.bgHeader.withValues(alpha: 0.9)]),
            border: Border(top: BorderSide(color: p.glassBorder.withValues(alpha: 0.45))),
          ),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  LiquidGlassButton(
                    onTap: () => setState(() => collapsed = !collapsed),
                    radius: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedRotation(turns: collapsed ? 0.5 : 0, duration: const Duration(milliseconds: 300), child: Text('▼', style: TextStyle(fontSize: 12, color: p.textMain))),
                        const SizedBox(width: 6),
                        Text(collapsed ? 'Expand Options' : 'Collapse Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: p.textMain)),
                      ]),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Shape:', style: TextStyle(fontSize: 12, color: p.textSub)),
                      const SizedBox(width: 5),
                      GlassSelect<String>(
                        fontSize: 12,
                        value: shapeType,
                        items: shapeTypes.map((e) => e.$1).toList(),
                        labelOf: (v) => shapeTypes.firstWhere((e) => e.$1 == v).$2,
                        onChanged: (v) {
                          shapeType = v;
                          moveTool = v == 'select';
                          handleShapeTypeChange();
                        },
                      ),
                    ]),
                    if (!collapsed) ...[
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        lbl('Blend Mode:'),
                        const SizedBox(width: 5),
                        Flexible(child: GlassSelect<String>(
                          fontSize: 11,
                          value: blendMode,
                          items: blendModes.map((e) => e.$1).toList(),
                          labelOf: (v) => blendModes.firstWhere((e) => e.$1 == v).$2,
                          onChanged: changeLayerBlendMode,
                        )),
                      ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        lbl('Size / Brush:'),
                        SizedBox(width: 110, child: Slider(value: thickness, min: 2, max: 100, onChanged: onThickness)),
                        SizedBox(width: 34, child: Text('${thickness.round()}px', style: TextStyle(fontSize: 11, color: p.textMain))),
                      ]),
                      GlassButton.small(label: 'Transform Pad', emoji: '🕹️', fontSize: 11, color: AppColors.orange, onTap: openDPad),
                      GlassButton.small(label: 'Photo Effects', emoji: '🎨', fontSize: 11, color: AppColors.teal, onTap: openAdjustments),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        GlassButton.small(label: 'Duplicate', emoji: '📋', fontSize: 11, color: AppColors.belize, onTap: duplicateSelectedLayer),
                        const SizedBox(width: 5),
                        lbl('Dist:'),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 46,
                          child: GlassTextField(controller: dupDist, fontSize: 11, textAlign: TextAlign.center, keyboardType: TextInputType.number, contentPadding: const EdgeInsets.symmetric(vertical: 6)),
                        ),
                      ]),
                      GlassCheck(value: snapping, label: 'Snapping', fontSize: 11, onChanged: (v) => setState(() => snapping = v)),
                      CompositedTransformTarget(
                        link: layerLink,
                        child: GlassButton.small(
                            key: _layersBtnKey,label: 'Layers ${layersOpen ? '▲' : '▼'}', color: AppColors.purple, onTap: () => setState(() => layersOpen = !layersOpen)),
                      ),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                          child: editorMode == 'highlight' && hasSel
                              ? Padding(
                                  key: const ValueKey('del'),
                                  padding: const EdgeInsets.only(right: 4),
                                  child: GlassButton.small(label: 'Delete', color: AppColors.crimson, onTap: () => deleteLayer(selected)),
                                )
                              : const SizedBox(key: ValueKey('nodel')),
                        ),
                        GlassButton.small(label: 'Undo', color: AppColors.midnight, onTap: undoHighlight),
                        const SizedBox(width: 4),
                        GlassButton.small(label: 'Redo', color: AppColors.midnight, onTap: redoHighlight),
                      ]),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final c in colors) _swatch(c),
                    if (!collapsed)
                      Pressable(
                        onTap: () => setState(() => cpOpen = true),
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const SweepGradient(colors: [Colors.red, Colors.yellow, Color(0xFF00FF00), Colors.cyan, Colors.blue, Color(0xFFFF00FF), Colors.red]),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 5)],
                          ),
                          child: const Text('🎨', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _swatch(PaletteColor c) {
    final sel = selectedColor == c.value.toARGB32();
    final size = c.isPureWhite ? 26.0 : 22.0;
    return Pressable(
      onTap: () => applyColorLogic(c.value.toARGB32()),
      child: AnimatedScale(
        scale: sel ? 1.15 : 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: c.display,
            shape: c.isPureWhite ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: c.isPureWhite ? BorderRadius.circular(4) : null,
            border: Border.all(color: sel ? AppColors.blue : (c.isPureWhite ? const Color(0xFF333333) : c.border), width: 2),
            boxShadow: sel ? const [BoxShadow(color: AppColors.blue, blurRadius: 8)] : null,
          ),
        ),
      ),
    );
  }

  Widget _layerPanel(AppPalette p) {
    // Keep the 260px panel fully on-screen (right-anchored to the Layers
    // button like the HTML, but shifted right when it would overflow left).
    var dx = 0.0;
    final box = _layersBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
      final screenW = MediaQuery.sizeOf(context).width;
      final left = right - 260;
      if (left < 8) dx = 8 - left;
      if (right + dx > screenW - 8) dx = screenW - 8 - right;
    }
    return CompositedTransformFollower(
      link: layerLink,
      targetAnchor: Alignment.topRight,
      followerAnchor: Alignment.bottomRight,
      offset: Offset(dx, -6),
      child: Align(
        alignment: Alignment.bottomRight,
        child: SizedBox(
          width: 260,
          child: GlassContainer(
            radius: 14,
            blur: 26,
            padding: const EdgeInsets.all(6),
            fill: [p.popBg.withValues(alpha: 0.78), p.popBg.withValues(alpha: 0.62)],
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text('LAYERS PANEL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: p.textSub, letterSpacing: 0.6)),
                  ),
                  Divider(height: 6, color: p.glassBorder.withValues(alpha: 0.4)),
                  if (shapes.isEmpty)
                    Padding(padding: const EdgeInsets.all(8), child: Text('No Markings', style: TextStyle(fontSize: 10, color: p.textSub)))
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: shapes.length,
                        itemBuilder: (_, i) {
                          final s = shapes[i];
                          final act = i == selected;
                          return Pressable(
                            pressedScale: 0.97,
                            onTap: () => selectLayer(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: act ? AppColors.blue : p.glassInput,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: act ? AppColors.lightBlue : Colors.transparent),
                              ),
                              child: Row(children: [
                                Expanded(
                                  child: Text('Layer ${i + 1} (${s.typeLabel} [${s.blendMode}])',
                                      style: TextStyle(fontSize: 11, color: act ? Colors.white : p.textMain)),
                                ),
                                GlassButton.small(
                                  label: 'Move',
                                  fontSize: 10,
                                  color: AppColors.orange,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  onTap: () {
                                    hideTextInput();
                                    selected = i;
                                    shapeType = 'select';
                                    layersOpen = false;
                                    handleShapeTypeChange();
                                    openDPad();
                                  },
                                ),
                                Pressable(
                                  onTap: () => deleteLayer(i),
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 9, right: 4),
                                    child: Text('×', style: TextStyle(color: AppColors.redBright, fontWeight: FontWeight.bold, fontSize: 15)),
                                  ),
                                ),
                              ]),
                            ),
                          ).animate().fadeIn(delay: (30 * i).ms, duration: 220.ms).slideX(begin: 0.08);
                        },
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 180.ms).scale(begin: const Offset(0.95, 0.95), alignment: Alignment.bottomRight, curve: Curves.easeOutBack);
  }

  void toggleMoveTool() {
    hideTextInput();
    editorMode = 'highlight';
    moveTool = !moveTool;
    if (moveTool) {
      if (shapeType != 'select') prevDrawingType = shapeType;
      shapeType = 'select';
    } else {
      shapeType = prevDrawingType;
    }
    dpadOpen = false;
    setState(() {});
    redraw();
  }

  Widget _bottomBar(AppPalette p) {
    final crop = modalEntryMode == 'crop';
    final hl = modalEntryMode == 'highlight';
    final mq = MediaQuery.of(context);
    final avail = mq.size.width - 24;
    final cols = avail < 420 ? 3 : (avail < 700 ? 4 : 6);
    const gap = 8.0;
    final tileW = (avail - gap * (cols - 1)) / cols;
    Widget chip(String label, VoidCallback? onTap, {Color? color, Color? textColor, bool active = false, Color activeColor = AppColors.blue, String? emoji}) => SizedBox(
          width: tileW,
          height: 44, // >= 44 dp touch target
          child: GlassButton(
            label: label,
            emoji: emoji,
            color: color,
            textColor: textColor,
            active: active,
            activeColor: activeColor,
            fontSize: 12,
            expand: true,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            onTap: onTap,
          ),
        );
    final chips = <Widget>[
      chip('Text OCR', ocrBusy ? null : runOCRScan, color: AppColors.teal, emoji: '✨'),
      if (ocrText.trim().isNotEmpty) chip('OCR Text', _showOcrSheet, color: AppColors.teal, emoji: '📄'),
      if (hl && o.ocrWords.isNotEmpty) chip('Clear Text HL', clearOCRHighlights, color: AppColors.red),
      if (crop) ...[
        chip('Auto Detect', runAutoEdgeDetection, color: AppColors.amethyst, emoji: '✨'),
        chip('Canvas Size', () => setState(() => csOpen = true), color: AppColors.pumpkin, emoji: '📐'),
        chip('No Crop', noCrop, color: AppColors.orange),
        chip('Rotate 90°', rotateScan),
      ],
      if (hl) ...[
        chip('Zoom & Pan', () => setEditorMode('zoom'), color: editorMode == 'zoom' ? const Color(0xFF9B59B6) : AppColors.slate),
        chip(editorMode == 'highlight' ? 'Highlight: ON' : 'Highlight', () => setEditorMode('highlight'),
            color: editorMode == 'highlight' ? AppColors.yellow : AppColors.slate, textColor: editorMode == 'highlight' ? Colors.black : Colors.white),
        chip('Select / Move', toggleMoveTool,
            emoji: '✋', color: moveTool && editorMode == 'highlight' ? AppColors.blue : AppColors.slate, textColor: Colors.white),
      ],
    ];
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + mq.padding.bottom),
          decoration: BoxDecoration(
            color: p.bgHeader.withValues(alpha: 0.88),
            border: Border(top: BorderSide(color: p.glassBorder.withValues(alpha: 0.35))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(alignment: WrapAlignment.center, spacing: gap, runSpacing: gap, children: chips),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 48,
                  child: GlassButton(label: 'Cancel', color: AppColors.darkGrey, expand: true, fontSize: 14, onTap: busy == null ? closeScan : null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 48,
                  child: GlassButton(label: 'Done', emoji: '✓', color: AppColors.green, bold: true, expand: true, fontSize: 16, onTap: busy == null ? applyScan : null),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
