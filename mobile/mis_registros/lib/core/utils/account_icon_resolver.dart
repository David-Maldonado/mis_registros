import 'package:flutter/material.dart';

/// Resuelve un ícono semántico de Material para una cuenta a partir de su
/// nombre y tipo (`cash`, `bank`, `e_wallet`, `credit_card`).
class AccountIconResolver {
  const AccountIconResolver._();

  static IconData resolve(String name, {required String type}) {
    final normalized = _normalize(name);

    if (normalized.isNotEmpty) {
      for (final rule in _rules) {
        for (final keyword in rule.keywords) {
          if (normalized.contains(keyword)) {
            return rule.icon;
          }
        }
      }
    }

    return switch (type) {
      'cash' => Icons.payments_rounded,
      'bank' => Icons.account_balance_rounded,
      'e_wallet' => Icons.contactless_rounded,
      'credit_card' => Icons.credit_card_rounded,
      _ => Icons.account_balance_wallet_rounded,
    };
  }

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }

  static const List<_AccountIconRule> _rules = [
    _AccountIconRule(
      icon: Icons.savings_rounded,
      keywords: ['ahorro', 'alcancia', 'reserva', 'emergencia', 'fondo', 'chanchito'],
    ),
    _AccountIconRule(
      icon: Icons.credit_card_rounded,
      keywords: ['visa', 'mastercard', 'amex', 'cabal', 'tarjeta', 'credito', 'tc'],
    ),
    _AccountIconRule(
      icon: Icons.contactless_rounded,
      keywords: ['tigo', 'personal pay', 'ueno', 'mango', 'zimple', 'paypal', 'mercado pago', 'qr'],
    ),
    _AccountIconRule(
      icon: Icons.account_balance_rounded,
      keywords: [
        'banco',
        'itau',
        'continental',
        'familiar',
        'gnb',
        'atlas',
        'basa',
        'sudameris',
        'vision',
        'bnf',
        'cooperativa',
        'financiera',
      ],
    ),
    _AccountIconRule(
      icon: Icons.trending_up_rounded,
      keywords: ['inversion', 'bolsa', 'plazo fijo', 'cda'],
    ),
    _AccountIconRule(
      icon: Icons.storefront_rounded,
      keywords: ['negocio', 'empresa', 'comercio', 'caja chica', 'ventas'],
    ),
    _AccountIconRule(
      icon: Icons.currency_exchange_rounded,
      keywords: ['dolar', 'usd', 'euro', 'divisa'],
    ),
    _AccountIconRule(
      icon: Icons.payments_rounded,
      keywords: ['efectivo', 'billetera', 'bolsillo', 'cash'],
    ),
  ];
}

class _AccountIconRule {
  const _AccountIconRule({required this.icon, required this.keywords});

  final IconData icon;
  final List<String> keywords;
}
