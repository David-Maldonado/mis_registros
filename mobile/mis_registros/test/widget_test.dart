import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mis_registros/core/theme/app_theme.dart';
import 'package:mis_registros/core/theme/theme_controller.dart';
import 'package:mis_registros/core/utils/account_icon_resolver.dart';
import 'package:mis_registros/core/utils/app_feedback.dart';
import 'package:mis_registros/core/utils/category_icon_resolver.dart';
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
    expect(
      AppFeedback.formatError('ClientException: Failed to fetch'),
      contains('No se pudo conectar'),
    );
    expect(
      AppFeedback.formatError('Invalid login credentials'),
      'Correo o contraseña incorrectos.',
    );
    expect(
      CategoryIconResolver.resolve('Supermercado', type: 'expense'),
      Icons.shopping_cart_rounded,
    );
    expect(
      CategoryIconResolver.resolve('Salario mensual', type: 'income'),
      Icons.payments_rounded,
    );
    expect(
      CategoryIconResolver.resolve('Varios', type: 'expense'),
      Icons.sell_rounded,
    );
    expect(
      CategoryIconResolver.resolve('Otros', type: 'income'),
      Icons.monetization_on_rounded,
    );
    expect(
      AccountIconResolver.resolve('Fondo de ahorro', type: 'bank'),
      Icons.savings_rounded,
    );
    expect(
      AccountIconResolver.resolve('Visa Itaú', type: 'credit_card'),
      Icons.credit_card_rounded,
    );
    expect(
      AccountIconResolver.resolve('Principal', type: 'e_wallet'),
      Icons.contactless_rounded,
    );
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
