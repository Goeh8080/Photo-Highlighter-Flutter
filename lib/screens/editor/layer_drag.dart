import '../../models/hl_shape.dart';

/// Direct-manipulation move of ONE layer.
///
/// The shape is moved to `original + (pointer - pointerAtDown)` on every move
/// event, so after any sequence of events the layer position equals the total
/// pointer delta exactly (no drift, no threshold, no easing). The points are
/// updated in place – no allocation per frame – and no other layer is touched.
class LayerDrag {
  final int index;
  final HlShape shape;

  /// Snapshot taken at pointer-down. It is the history entry pushed on
  /// pointer-up (only if the layer actually moved).
  final HlShape before;
  final Pt _origin;
  double dx = 0, dy = 0;
  bool moved = false;

  LayerDrag(this.index, this.shape, Pt pointerDown)
      : before = shape.clone(),
        _origin = pointerDown.copy();

  /// Move to the pointer position [p] (same coordinate space as at down).
  void update(Pt p, {double snapX = 0, double snapY = 0}) {
    dx = p.x - _origin.x + snapX;
    dy = p.y - _origin.y + snapY;
    if (dx != 0 || dy != 0) moved = true;
    final b = before;
    if (b.pts != null && shape.pts != null) {
      final src = b.pts!, dst = shape.pts!;
      for (var i = 0; i < src.length; i++) {
        dst[i].x = src[i].x + dx;
        dst[i].y = src[i].y + dy;
      }
    }
    if (b.start != null && shape.start != null) {
      shape.start!.x = b.start!.x + dx;
      shape.start!.y = b.start!.y + dy;
    }
    if (b.current != null && shape.current != null) {
      shape.current!.x = b.current!.x + dx;
      shape.current!.y = b.current!.y + dy;
    }
  }
}

/// Top-most layer whose geometry (+ [tol] finger slop) is under [world], or -1.
int hitTopLayer(List<HlShape> shapes, Pt world, double tol) {
  for (var i = shapes.length - 1; i >= 0; i--) {
    if (shapes[i].hitTest(world, tol)) return i;
  }
  return -1;
}
