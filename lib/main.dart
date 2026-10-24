import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'services/album_repository.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Photo Highlighter — Flutter port of the single-file HTML app.
///
/// Start-up is defensive: the first frame is drawn immediately (no awaits
/// before runApp), storage is initialised afterwards with timeouts, and any
/// uncaught error shows a readable error screen instead of a black screen.
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _BootState.reportError(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _BootState.reportError(error, stack);
      return true;
    };
    ErrorWidget.builder = (details) => _ErrorView(error: details.exception, stack: details.stack);
    runApp(const BootApp());
  }, (error, stack) => _BootState.reportError(error, stack));
}

/// Shows a white splash with the icon while storage initialises, then the app.
class BootApp extends StatefulWidget {
  const BootApp({super.key});
  @override
  State<BootApp> createState() => _BootState();
}

class _BootState extends State<BootApp> {
  static _BootState? _instance;
  static final List<String> _pendingErrors = [];

  static void reportError(Object error, StackTrace? stack) {
    debugPrint('PhotoHighlighter fatal: $error\n$stack');
    final s = _instance;
    if (s != null && s.mounted && s._ready == null) {
      // Only take over the screen if start-up itself failed.
      s.setState(() => s._bootError = '$error');
    } else {
      _pendingErrors.add('$error');
    }
  }

  ({ThemeController theme, AppState state})? _ready;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    _instance = this;
    _init();
  }

  Future<void> _init() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('prefs init failed: $e');
    }
    final album = AlbumRepository();
    try {
      await album.init().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('album init failed: $e');
      album.useMemoryFallback();
    }
    if (!mounted) return;
    setState(() => _ready = (theme: ThemeController(prefs), state: AppState(album)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _ready;
    if (_bootError != null) {
      return MaterialApp(debugShowCheckedModeBanner: false, home: _ErrorView(error: _bootError!));
    }
    if (r == null) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF007BFF)))),
      );
    }
    return PhotoMergerApp(theme: r.theme, state: r.state);
  }
}

class PhotoMergerApp extends StatelessWidget {
  final ThemeController theme;
  final AppState state;
  const PhotoMergerApp({super.key, required this.theme, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      controller: theme,
      builder: (context, palette) => MaterialApp(
        title: 'Photo Highlighter',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(palette),
        themeAnimationDuration: Duration.zero,
        // One shared backdrop snapshot for all button-level glass blurs.
        builder: (context, child) => BackdropGroup(child: child!),
        home: HomeScreen(state: state),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final StackTrace? stack;
  const _ErrorView({required this.error, this.stack});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text('Something went wrong:\n\n$error${kDebugMode && stack != null ? '\n\n$stack' : ''}',
                style: const TextStyle(color: Colors.black87, fontSize: 13)),
          ),
        ),
      );
}
