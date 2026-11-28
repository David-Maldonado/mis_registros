import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/state/ledger_refresh_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/account_icon_resolver.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/currency_formatter.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({
    super.key,
    required this.apiClient,
    this.refreshNotifier,
  });

  final ApiClient apiClient;
  final LedgerRefreshNotifier? refreshNotifier;

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
    widget.refreshNotifier?.addListener(_onExternalChange);
    _loadData();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) _loadData();
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

  Future<void> _showAccountDialog({Map<String, dynamic>? existing}) async {
    final isEditing = existing != null;
    if (!isEditing && _currencies.isEmpty) return;

    final decimals = (existing?['currency_decimal_places'] as num?)?.toInt() ?? 0;
    final nameController = TextEditingController(text: existing?['name'] as String? ?? '');
    final initialController = TextEditingController(
      text: isEditing
          ? CurrencyFormatter.format(
              amount: existing['initial_balance'],
              symbol: '',
              decimalPlaces: decimals,
            )
          : '0',
    );
    final limitController = TextEditingController(
      text: existing?['credit_limit'] != null
          ? CurrencyFormatter.format(
              amount: existing!['credit_limit'],
              symbol: '',
              decimalPlaces: decimals,
            )
          : '',
    );

    String selectedType = existing?['type'] as String? ?? 'cash';
    String selectedCurrencyId = existing?['currency_id'] as String? ??
        (_currencies.firstWhere(
          (c) => c['code'] == 'PYG',
          orElse: () => _currencies.first,
        )['id'] as String);
    bool isActive = existing?['is_active'] as bool? ?? true;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text(isEditing ? 'Editar cuenta' : 'Nueva cuenta'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Nombre',
                        prefixIcon: Icon(
                          AccountIconResolver.resolve(nameController.text, type: selectedType),
                        ),
                        hintText: _nameHintForType(selectedType),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!isEditing) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tipo'),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Efectivo', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'bank', child: Text('Banco', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'e_wallet', child: Text('Billetera electrónica', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'credit_card', child: Text('Tarjeta de crédito', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setDialogState(() => selectedType = v ?? 'cash'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCurrencyId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Moneda'),
                        items: _currencies
                            .map((c) => DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text(
                                    '${c['code']} (${c['symbol']})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedCurrencyId = v!),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: initialController,
                      keyboardType: selectedType == 'credit_card'
                          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                          : const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(
                          allowNegative: selectedType == 'credit_card',
                          allowDecimal: true,
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: selectedType == 'credit_card'
                            ? 'Saldo inicial (<= 0, deuda)'
                            : 'Saldo inicial (>= 0)',
                        hintText: selectedType == 'credit_card' ? 'Ej.: 0 o -500.000' : 'Ej.: 250.000',
                        helperText: isEditing
                            ? 'Solo modificable si la cuenta aún no tiene movimientos.'
                            : (selectedType == 'credit_card'
                                ? 'Usa 0 si no tienes deuda actual, o un monto negativo si ya debes.'
                                : 'Dinero con el que empiezas en esta cuenta (puede ser 0).'),
                        helperMaxLines: 2,
                      ),
                    ),
                    if (selectedType == 'credit_card') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: limitController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          ThousandsSeparatorInputFormatter(allowDecimal: true),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Límite de crédito',
                          hintText: 'Ej.: 5.000.000',
                          helperText: 'Opcional. Sirve para ver cuánto crédito disponible te queda.',
                          helperMaxLines: 2,
                        ),
                      ),
                    ],
                    if (isEditing) ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Cuenta activa'),
                        value: isActive,
                        onChanged: (v) => setDialogState(() => isActive = v),
                      ),
                    ],
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Text(dialogError!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            if (isEditing)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () async {
                  try {
                    await widget.apiClient.delete('/accounts/${existing['account_id']}');
                    if (ctx.mounted) Navigator.pop(ctx);
                    widget.refreshNotifier?.notifyDataChanged();
                    await _loadData();
                    if (mounted) AppFeedback.showSuccess(context, 'Cuenta eliminada.');
                  } catch (e) {
                    setDialogState(() => dialogError = AppFeedback.formatError(e));
                  }
                },
                child: const Text('Eliminar'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final cleanName = nameController.text.trim();
                if (cleanName.isEmpty) {
                  setDialogState(() => dialogError = 'Ingresa un nombre para la cuenta.');
                  return;
                }
                try {
                  final initialBalance = initialController.text.trim().isEmpty
                      ? '0'
                      : CurrencyFormatter.toApiDecimal(initialController.text);
                  final creditLimit = selectedType == 'credit_card'
                      ? CurrencyFormatter.toApiDecimal(limitController.text)
                      : null;

                  if (isEditing) {
                    await widget.apiClient.patch('/accounts/${existing['account_id']}', body: {
                      'name': cleanName,
                      'initial_balance': initialBalance,
                      'credit_limit': creditLimit,
                      'is_active': isActive,
                    });
                  } else {
                    await widget.apiClient.post('/accounts', body: {
                      'currency_id': selectedCurrencyId,
                      'name': cleanName,
                      'type': selectedType,
                      'initial_balance': initialBalance,
                      'credit_limit': ?creditLimit,
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  widget.refreshNotifier?.notifyDataChanged();
                  await _loadData();
                  if (mounted) {
                    AppFeedback.showSuccess(
                      context,
                      isEditing ? 'Cuenta actualizada.' : 'Cuenta creada.',
                    );
                  }
                } catch (e) {
                  setDialogState(() => dialogError = AppFeedback.formatError(e));
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
                onPressed: () => _showAccountDialog(),
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
          else ...[
            if (_accounts.any((a) => a['is_active'] == true)) ...[
              _buildTotalsCard(theme, colors),
              const SizedBox(height: 12),
            ],
            ..._accounts.map((acc) {
              final type = acc['type'] as String? ?? '';
              final code = acc['currency_code'] as String? ?? 'PYG';
              final symbol = code == 'PYG' ? 'Gs.' : (acc['currency_symbol'] as String? ?? '');
              final decimals = (acc['currency_decimal_places'] as num?)?.toInt() ?? 0;
              final rawBalance = (acc['current_balance'] ?? '0').toString();
              final isCreditCard = type == 'credit_card';
              final isActive = acc['is_active'] == true;

              // En tarjetas, la deuda se muestra en positivo cuando current_balance < 0
              final displayBalance = isCreditCard && rawBalance.startsWith('-')
                  ? rawBalance.substring(1)
                  : rawBalance;
              final availableCreditStr = acc['available_credit']?.toString();
              final isOverLimit =
                  isCreditCard && availableCreditStr != null && availableCreditStr.startsWith('-');

              final accountName = acc['name'] as String? ?? '';
              final iconColor = !isActive
                  ? colors.voided
                  : (isCreditCard && rawBalance.startsWith('-')
                      ? colors.expense
                      : theme.colorScheme.primary);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _showAccountDialog(existing: acc),
                  leading: CircleAvatar(
                    backgroundColor: iconColor.withValues(alpha: 0.12),
                    child: Icon(
                      AccountIconResolver.resolve(accountName, type: type),
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          accountName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isActive ? null : colors.voided,
                          ),
                        ),
                      ),
                      if (!isActive)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            'Inactiva',
                            style: theme.textTheme.labelSmall?.copyWith(color: colors.voided),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_labelForType(type), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (isCreditCard && availableCreditStr != null)
                        Text(
                          'Disponible: ${CurrencyFormatter.format(amount: availableCreditStr, symbol: symbol, decimalPlaces: decimals)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isOverLimit ? colors.warning : null),
                        ),
                    ],
                  ),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
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
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalsCard(ThemeData theme, FinancialColors colors) {
    final activeAccounts = _accounts.where((a) => a['is_active'] == true).toList();
    final byCurrency = <String, _CurrencyTotal>{};

    for (final acc in activeAccounts) {
      final code = acc['currency_code'] as String? ?? 'PYG';
      final symbol = code == 'PYG' ? 'Gs.' : (acc['currency_symbol'] as String? ?? code);
      final decimals = (acc['currency_decimal_places'] as num?)?.toInt() ?? 0;
      final balance = double.tryParse((acc['current_balance'] ?? '0').toString()) ?? 0;
      final isCreditCard = acc['type'] == 'credit_card';

      final current = byCurrency[code] ??
          _CurrencyTotal(
            code: code,
            symbol: symbol,
            decimals: decimals,
          );

      byCurrency[code] = _CurrencyTotal(
        code: code,
        symbol: symbol,
        decimals: decimals,
        available: isCreditCard ? current.available : current.available + balance,
        cardDebt: isCreditCard && balance < 0 ? current.cardDebt + (-balance) : current.cardDebt,
        net: current.net + balance,
        hasCreditCard: current.hasCreditCard || isCreditCard,
      );
    }

    final entries = byCurrency.values.toList()
      ..sort((a, b) {
        if (a.code == 'PYG') return -1;
        if (b.code == 'PYG') return 1;
        return a.code.compareTo(b.code);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entries.length > 1 ? 'Disponible total (${entries[i].code})' : 'Disponible total',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    entries[i].code,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyFormatter.format(
                    amount: entries[i].available,
                    symbol: entries[i].symbol,
                    decimalPlaces: entries[i].decimals,
                  ),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: entries[i].available < 0 ? colors.expense : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (entries[i].hasCreditCard) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Deuda tarjetas: ${CurrencyFormatter.format(amount: entries[i].cardDebt, symbol: entries[i].symbol, decimalPlaces: entries[i].decimals)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: entries[i].cardDebt > 0 ? colors.expense : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Neto: ${CurrencyFormatter.format(amount: entries[i].net, symbol: entries[i].symbol, decimalPlaces: entries[i].decimals)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: entries[i].net < 0 ? colors.expense : colors.income,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _labelForType(String type) => switch (type) {
        'cash' => 'Efectivo',
        'bank' => 'Banco',
        'e_wallet' => 'Billetera electrónica',
        'credit_card' => 'Tarjeta de crédito (deuda)',
        _ => type,
      };

  String _nameHintForType(String type) => switch (type) {
        'cash' => 'Ej.: Efectivo, Billetera, Caja chica',
        'bank' => 'Ej.: Banco Itaú, Continental, Caja de ahorro',
        'e_wallet' => 'Ej.: Tigo Money, Personal Pay, Ueno',
        'credit_card' => 'Ej.: Visa Itaú, Mastercard Continental',
        _ => 'Ej.: Mi cuenta principal',
      };
}

class _CurrencyTotal {
  const _CurrencyTotal({
    required this.code,
    required this.symbol,
    required this.decimals,
    this.available = 0,
    this.cardDebt = 0,
    this.net = 0,
    this.hasCreditCard = false,
  });

  final String code;
  final String symbol;
  final int decimals;
  final double available;
  final double cardDebt;
  final double net;
  final bool hasCreditCard;
}
