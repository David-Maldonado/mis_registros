import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({
    ThemeMode initialMode = ThemeMode.system,
    AppColorPalette initialPalette = AppColorPalette.azul,
  })  : _themeMode = initialMode,
        _palette = initialPalette;

  static const _themeModeKey = 'mis_registros_theme_mode';
  static const _paletteKey = 'mis_registros_color_palette';

  ThemeMode _themeMode;
  AppColorPalette _palette;

  ThemeMode get themeMode => _themeMode;
  AppColorPalette get palette => _palette;

  Future<void> loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);
    final savedPalette = prefs.getString(_paletteKey);

    if (savedMode != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => ThemeMode.system,
      );
    }

    if (savedPalette != null) {
      _palette = AppColorPalette.values.firstWhere(
        (p) => p.name == savedPalette,
        orElse: () => AppColorPalette.azul,
      );
    }

    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
    _persistThemeMode(mode);
  }

  void setPalette(AppColorPalette palette) {
    if (_palette == palette) {
      return;
    }
    _palette = palette;
    notifyListeners();
    _persistPalette(palette);
  }

  void toggleLightDark(BuildContext context) {
    final isCurrentlyDark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    setThemeMode(isCurrentlyDark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> _persistThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.name);
    } catch (_) {
      // Ignorar errores de almacenamiento en entornos sin plugin inicializado
    }
  }

  Future<void> _persistPalette(AppColorPalette palette) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_paletteKey, palette.name);
    } catch (_) {
      // Ignorar errores de almacenamiento en entornos sin plugin inicializado
    }
  }
}
