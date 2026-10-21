import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Port of `#appToast`: a pill that springs up from the bottom
/// (cubic-bezier(0.175, 0.885, 0.32, 1.275) == easeOutBack) for 2.2s.
class GlassToast {
  static OverlayEntry? _entry;
  static Timer? _timer;
  static final _key = GlobalKey<_ToastViewState>();

  static void show(BuildContext context, String msg) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => _ToastView(key: _key));
      overlay.insert(_entry!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _key.currentState?.show(msg));
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2200), () => _key.currentState?.hide());
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({super.key});
  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> {
  String _msg = '';
  bool _visible = false;

  void show(String m) => setState(() {
        _msg = m;
        _visible = true;
      });
  void hide() => setState(() => _visible = false);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 24;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, 2.2),
            duration: const Duration(milliseconds: 300),
            curve: const Cubic(0.175, 0.885, 0.32, 1.275),
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LinearGradient(colors: [
                        const Color(0xFF3D95FF).withValues(alpha: 0.92),
                        const Color(0xFF007BFF).withValues(alpha: 0.82),
                      ]),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text(_msg,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
