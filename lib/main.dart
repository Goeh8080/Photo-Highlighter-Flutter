import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'services/album_repository.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Photo Merger & Highlighter — Flutter port of the single-file HTML app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final album = AlbumRepository();
  await album.init();
  runApp(PhotoMergerApp(theme: ThemeController(prefs), state: AppState(album)));
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
        title: 'Photo Merger & Highlighter',
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
