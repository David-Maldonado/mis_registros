import 'package:flutter/services.dart';

class CurrencyFormatter {
  const CurrencyFormatter._();

  /// Formatea un importe decimal exacto (sin usar double para evitar pérdida de precisión).
  static String format({
    required Object? amount,
    required String symbol,
    required int decimalPlaces,
  }) {
    final raw = (amount ?? '0').toString().trim();
    if (raw.isEmpty) {
      return symbol.isEmpty ? '0' : '$symbol 0';
    }

    final isNegative = raw.startsWith('-');
    final unsigned = isNegative ? raw.substring(1) : raw;
    final parts = unsigned.split('.');
    final integerRaw = parts[0].isEmpty ? '0' : parts[0];
    final fractionRaw = parts.length > 1 ? parts[1] : '';

    final formattedInt = addThousandsSeparator(integerRaw);
    final prefix = symbol.isEmpty ? '' : '$symbol ';

    if (decimalPlaces <= 0) {
      return '${isNegative ? '-' : ''}$prefix$formattedInt';
    }

    final paddedFraction = fractionRaw.padRight(decimalPlaces, '0');
    final trimmedFraction = paddedFraction.substring(0, decimalPlaces);
    return '${isNegative ? '-' : ''}$prefix$formattedInt,$trimmedFraction';
  }

  /// Convierte un texto formateado con separadores de miles (ej. "1.500.000,50")
  /// al formato decimal estándar esperado por la API ("1500000.50").
  static String toApiDecimal(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '0';
    return trimmed.replaceAll('.', '').replaceAll(',', '.');
  }

  static String addThousandsSeparator(String digits) {
    final clean = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (clean.isEmpty) return '0';
    final buffer = StringBuffer();
    for (var i = 0; i < clean.length; i++) {
      final remaining = clean.length - i;
      if (i > 0 && remaining % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(clean[i]);
    }
    return buffer.toString();
  }
}

/// Formatea números con separador de miles (.) en tiempo real al escribir.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  ThousandsSeparatorInputFormatter({
    this.allowNegative = false,
    this.allowDecimal = false,
  });

  final bool allowNegative;
  final bool allowDecimal;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }

    final isNegative = allowNegative && text.startsWith('-');
    var unsigned = text.replaceAll('-', '');

    if (allowDecimal) {
      // Aceptar coma o punto decimal únicamente si el usuario escribe decimales;
      // removemos los puntos de miles existentes y conservamos una sola coma decimal.
      unsigned = unsigned.replaceAll('.', '');
      final commaIndex = unsigned.indexOf(',');
      if (commaIndex != -1) {
        final intPart = unsigned.substring(0, commaIndex).replaceAll(RegExp(r'[^0-9]'), '');
        final decPart = unsigned
            .substring(commaIndex + 1)
            .replaceAll(RegExp(r'[^0-9]'), '');
        final limitedDec = decPart.length > 4 ? decPart.substring(0, 4) : decPart;
        final formattedInt = intPart.isEmpty ? '0' : CurrencyFormatter.addThousandsSeparator(intPart);
        final formatted = '${isNegative ? '-' : ''}$formattedInt,$limitedDec';
        return TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }

    final digitsOnly = unsigned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      final onlySign = isNegative ? '-' : '';
      return TextEditingValue(
        text: onlySign,
        selection: TextSelection.collapsed(offset: onlySign.length),
      );
    }

    final formatted = '${isNegative ? '-' : ''}${CurrencyFormatter.addThousandsSeparator(digitsOnly)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
