import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _currencies = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiClient.get('/accounts/balances'),
        widget.apiClient.get('/currencies'),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(results[0] as List);
        _currencies = List<Map<String, dynamic>>.from(results[1] as List);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateDialog() async {
    if (_currencies.isEmpty) return;
    final nameController = TextEditingController();
    final initialController = TextEditingController(text: '0');
    final limitController = TextEditingController();
    String selectedType = 'cash';
    String selectedCurrencyId = _currencies.first['id'] as String;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nueva cuenta'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'bank', child: Text('Banco')),
                    DropdownMenuItem(value: 'e_wallet', child: Text('Billetera electrónica')),
                    DropdownMenuItem(value: 'credit_card', child: Text('Tarjeta de crédito')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedType = v ?? 'cash'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCurrencyId,
                  decoration: const InputDecoration(labelText: 'Moneda'),
                  items: _currencies
                      .map((c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text('${c['code']} (${c['symbol']})'),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedCurrencyId = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: initialController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: [
                    ThousandsSeparatorInputFormatter(
                      allowNegative: selectedType == 'credit_card',
                      allowDecimal: true,
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: selectedType == 'credit_card'
                        ? 'Saldo inicial (<= 0, negativo = deuda)'
                        : 'Saldo inicial (>= 0)',
                  ),
                ),
                if (selectedType == 'credit_card') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: limitController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      ThousandsSeparatorInputFormatter(allowDecimal: true),
                    ],
                    decoration: const InputDecoration(labelText: 'Límite de crédito'),
                  ),
                ],
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Text(dialogError!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.apiClient.post('/accounts', body: {
                    'currency_id': selectedCurrencyId,
                    'name': nameController.text.trim(),
                    'type': selectedType,
                    'initial_balance': initialController.text.trim().isEmpty
                        ? '0'
                        : CurrencyFormatter.toApiDecimal(initialController.text),
                    if (selectedType == 'credit_card')
                      'credit_limit': CurrencyFormatter.toApiDecimal(limitController.text),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadData();
                } catch (e) {
                  setDialogState(() => dialogError = e.toString());
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinancialColors>()!;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cuentas', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              FilledButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add),
                label: const Text('Nueva'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          else if (_accounts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Aún no tienes cuentas. Crea tu primera cuenta para empezar.'),
              ),
            )
          else
            ..._accounts.map((acc) {
              final type = acc['type'] as String? ?? '';
              final symbol = acc['currency_symbol'] as String? ?? '';
              final decimals = (acc['currency_decimal_places'] as num?)?.toInt() ?? 0;
              final rawBalance = (acc['current_balance'] ?? '0').toString();
              final isCreditCard = type == 'credit_card';

              // En tarjetas, la deuda se muestra en positivo cuando current_balance < 0
              final displayBalance = isCreditCard && rawBalance.startsWith('-')
                  ? rawBalance.substring(1)
                  : rawBalance;
              final availableCreditStr = acc['available_credit']?.toString();
              final isOverLimit =
                  isCreditCard && availableCreditStr != null && availableCreditStr.startsWith('-');

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(_iconForType(type)),
                  title: Text(acc['name'] as String? ?? ''),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_labelForType(type)),
                      if (isCreditCard && availableCreditStr != null)
                        Text(
                          'Crédito disponible: ${CurrencyFormatter.format(amount: availableCreditStr, symbol: symbol, decimalPlaces: decimals)}',
                          style: TextStyle(color: isOverLimit ? colors.warning : null),
                        ),
                    ],
                  ),
                  trailing: Text(
                    CurrencyFormatter.format(
                      amount: displayBalance,
                      symbol: symbol,
                      decimalPlaces: decimals,
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isCreditCard && rawBalance.startsWith('-') ? colors.expense : colors.income,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  IconData _iconForType(String type) => switch (type) {
        'cash' => Icons.payments_outlined,
        'bank' => Icons.account_balance_outlined,
        'e_wallet' => Icons.account_balance_wallet_outlined,
        'credit_card' => Icons.credit_card_outlined,
        _ => Icons.savings_outlined,
      };

  String _labelForType(String type) => switch (type) {
        'cash' => 'Efectivo',
        'bank' => 'Banco',
        'e_wallet' => 'Billetera electrónica',
        'credit_card' => 'Tarjeta de crédito (deuda)',
        _ => type,
      };
}
