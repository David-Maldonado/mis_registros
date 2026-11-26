import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mis_registros/core/theme/app_theme.dart';
import 'package:mis_registros/core/theme/theme_controller.dart';
import 'package:mis_registros/core/utils/currency_formatter.dart';
import 'package:mis_registros/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('CurrencyFormatter formatea PYG sin decimales y USD con 2 decimales', () {
    expect(
      CurrencyFormatter.format(amount: '1500000.0000', symbol: '₲', decimalPlaces: 0),
      '₲ 1.500.000',
    );
    expect(
      CurrencyFormatter.format(amount: '-250.5', symbol: r'$', decimalPlaces: 2),
      r'-$ 250,50',
    );
    expect(CurrencyFormatter.toApiDecimal('1.500.000'), '1500000');
    expect(CurrencyFormatter.toApiDecimal('1.500,50'), '1500.50');
  });

  testWidgets('ThemeController cambia y persiste modo claro/oscuro y paleta de color', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = ThemeController(initialMode: ThemeMode.light);

    await tester.pumpWidget(MisRegistrosConfigErrorApp(themeController: controller));
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);

    controller.setThemeMode(ThemeMode.dark);
    controller.setPalette(AppColorPalette.marfilTurquesa);
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.palette, AppColorPalette.marfilTurquesa);

    final restored = ThemeController();
    await restored.loadSavedPreferences();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.palette, AppColorPalette.marfilTurquesa);
  });
}
