import 'package:flutter/material.dart';
import 'app_theme.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({
    ThemeMode initialMode = ThemeMode.system,
    AppColorPalette initialPalette = AppColorPalette.azul,
  })  : _themeMode = initialMode,
        _palette = initialPalette;

  ThemeMode _themeMode;
  AppColorPalette _palette;

  ThemeMode get themeMode => _themeMode;
  AppColorPalette get palette => _palette;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
  }

  void setPalette(AppColorPalette palette) {
    if (_palette == palette) {
      return;
    }
    _palette = palette;
    notifyListeners();
  }

  void toggleLightDark(BuildContext context) {
    final isCurrentlyDark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    setThemeMode(isCurrentlyDark ? ThemeMode.light : ThemeMode.dark);
  }
}
