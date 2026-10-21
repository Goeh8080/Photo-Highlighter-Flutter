import 'package:flutter/material.dart';

/// FLIP-style slot for list items in a Wrap: when the item's position changes
/// (reorder, or a neighbour removed) it slides smoothly from the old spot to
/// the new one; it can also play an exit animation before being removed.
class FlipSlot extends StatefulWidget {
  final Widget Function(BuildContext context, Future<void> Function() animateOut) builder;
  /// Ancestor used as the coordinate space (usually the Wrap's context).
  final GlobalKey spaceKey;
  const FlipSlot({super.key, required this.builder, required this.spaceKey});

  @override
  State<FlipSlot> createState() => _FlipSlotState();
}

class _FlipSlotState extends State<FlipSlot> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  late final AnimationController _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();
  Offset? _last;
  Offset _from = Offset.zero;

  Offset? _pos() {
    final box = context.findRenderObject() as RenderBox?;
    final space = widget.spaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || space == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: space);
  }

  void _check(Duration _) {
    if (!mounted) return;
    final now = _pos();
    if (now == null) return;
    final prev = _last;
    _last = now;
    if (prev != null && (prev - now).distance > 0.5) {
      // Start from where we visually were (including any in-flight offset).
      final current = _from * (1 - Curves.easeOutBack.transform(_move.value.clamp(0, 1)));
      _from = prev - now + current;
      _move.forward(from: 0);
    }
  }

  Future<void> _animateOut() async {
    await _exit.forward();
  }

  @override
  void dispose() {
    _move.dispose();
    _exit.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_check);
    return AnimatedBuilder(
      animation: Listenable.merge([_move, _exit, _enter]),
      builder: (context, child) {
        final m = _move.isAnimating || _move.value < 1 ? Curves.easeOutBack.transform(_move.value.clamp(0, 1)) : 1.0;
        final off = _from * (1 - m);
        final e = Curves.easeInCubic.transform(_exit.value);
        final en = Curves.easeOutBack.transform(_enter.value);
        final scale = (0.8 + 0.2 * en) * (1 - 0.35 * e);
        return Transform.translate(
          offset: off,
          child: Opacity(
            opacity: ((1 - e) * _enter.value.clamp(0.0, 1.0)).clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: widget.builder(context, _animateOut),
    );
  }
}
