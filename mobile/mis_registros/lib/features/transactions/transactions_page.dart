import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/network/api_client.dart';
import '../../core/state/ledger_refresh_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    required this.apiClient,
    this.refreshNotifier,
  });

  final ApiClient apiClient;
  final LedgerRefreshNotifier? refreshNotifier;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  static const _uuid = Uuid();
  static final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic>? _nextCursor;

  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _categories = const [];
  Map<String, String> _accountNames = const {};
  Map<String, String> _categoryNames = const {};
  Map<String, Map<String, dynamic>> _currenciesById = const {};

  // Filtros locales rápidos sobre el historial cargado
  String _filterType = 'all';
  String? _filterAccountId;
  bool _showVoided = true;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_onExternalChange);
    _loadInitial();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiClient.get('/transactions', query: {'limit': '30'}),
        widget.apiClient.get('/accounts'),
        widget.apiClient.get('/categories'),
        widget.apiClient.get('/currencies'),
      ]);

      if (!mounted) return;

      final txRes = results[0] as Map<String, dynamic>;
      final accounts = List<Map<String, dynamic>>.from(results[1] as List);
      final categories = List<Map<String, dynamic>>.from(results[2] as List);
      final currencies = List<Map<String, dynamic>>.from(results[3] as List);

      setState(() {
        _items = List<Map<String, dynamic>>.from(txRes['items'] as List);
        _nextCursor = txRes['next_cursor'] as Map<String, dynamic>?;
        _accounts = accounts;
        _categories = categories;
        _accountNames = {
          for (final a in accounts) a['id'] as String: a['name'] as String,
        };
        _categoryNames = {
          for (final c in categories) c['id'] as String: c['name'] as String,
        };
        _currenciesById = {
          for (final c in currencies) c['id'] as String: c,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await widget.apiClient.get('/transactions', query: {
        'limit': '30',
        'cursor_occurred_at': _nextCursor!['occurred_at'] as String,
        'cursor_id': _nextCursor!['id'] as String,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...List<Map<String, dynamic>>.from(res['items'] as List)];
        _nextCursor = res['next_cursor'] as Map<String, dynamic>?;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _formatTxAmount(Map<String, dynamic> tx) {
    final currency = _currenciesById[tx['currency_id'] as String?];
    final code = currency?['code'] as String? ?? 'PYG';
    final symbol = code == 'PYG' ? 'Gs.' : (currency?['symbol'] as String? ?? '');
    final decimals = (currency?['decimal_places'] as num?)?.toInt() ?? 0;

    return CurrencyFormatter.format(
      amount: tx['amount'],
      symbol: symbol,
      decimalPlaces: decimals,
    );
  }

  String _formatTxDate(Object? rawDate) {
    if (rawDate == null) return '';
    final parsed = DateTime.tryParse(rawDate.toString());
    if (parsed == null) return rawDate.toString();
    return _dateFormat.format(parsed.toLocal());
  }

  String _describeAccountFlow(Map<String, dynamic> tx) {
    final type = tx['type'] as String? ?? '';
    final movements = List<Map<String, dynamic>>.from(
      (tx['account_movements'] as List?) ?? const [],
    );

    if (movements.isEmpty) {
      return 'Sin movimiento de cuenta';
    }

    if (type == 'transfer') {
      String? fromName;
      String? toName;
      for (final m in movements) {
        final signed = (m['signed_amount'] ?? '0').toString();
        final accName = _accountNames[m['account_id']] ?? 'Cuenta';
        if (signed.startsWith('-')) {
          fromName = accName;
        } else {
          toName = accName;
        }
      }
      return 'De: ${fromName ?? '-'} → A: ${toName ?? '-'}';
    }

    final first = movements.first;
    final accName = _accountNames[first['account_id']] ?? 'Cuenta';
    final signed = (first['signed_amount'] ?? '0').toString();
    if (signed.startsWith('-')) {
      return 'Salió de: $accName';
    }
    return 'Entró a: $accName';
  }

  Future<DateTime?> _pickDateTime(BuildContext ctx, DateTime current) async {
    final pickedDate = await showDatePicker(
      context: ctx,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !ctx.mounted) return null;

    final pickedTime = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    final time = pickedTime ?? TimeOfDay.fromDateTime(current);
    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> _showTransactionDetail(Map<String, dynamic> tx) async {
    final type = tx['type'] as String? ?? '';
    final isVoided = tx['status'] == 'voided';
    final categoryName = tx['category_id'] != null
        ? (_categoryNames[tx['category_id']] ?? 'Categoría')
        : 'Sin categoría';
    final flowText = _describeAccountFlow(tx);
    final amountText = _formatTxAmount(tx);
    final dateText = _formatTxDate(tx['occurred_at']);
    final desc = (tx['description'] as String?)?.trim();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Chip(label: Text(_labelForType(type))),
                    Chip(label: Text(isVoided ? 'Anulada' : 'Contabilizada')),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  amountText,
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _DetailRow(icon: Icons.account_balance_wallet_outlined, label: 'Cuenta', value: flowText),
                _DetailRow(icon: Icons.category_outlined, label: 'Categoría', value: categoryName),
                _DetailRow(icon: Icons.schedule_outlined, label: 'Fecha y hora', value: dateText),
                if (desc != null && desc.isNotEmpty)
                  _DetailRow(icon: Icons.notes_outlined, label: 'Descripción', value: desc),
                if (isVoided && tx['void_reason'] != null)
                  _DetailRow(
                    icon: Icons.info_outline,
                    label: 'Motivo anulación',
                    value: tx['void_reason'].toString(),
                  ),
                const SizedBox(height: 16),
                if (!isVoided) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEditDescriptionDialog(tx);
                        },
                        icon: const Icon(Icons.edit_note_outlined),
                        label: const Text('Editar nota'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showReplaceTransactionDialog(tx);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar operación'),
                      ),
                      if (type == 'expense')
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showRefundDialog(tx);
                          },
                          icon: const Icon(Icons.replay_rounded),
                          label: const Text('Devolución'),
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _voidTransaction(tx['id'] as String);
                        },
                        icon: const Icon(Icons.block_outlined),
                        label: const Text('Anular'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditDescriptionDialog(Map<String, dynamic> tx) async {
    final controller = TextEditingController(text: (tx['description'] as String?) ?? '');
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Editar descripción'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 10),
                Text(dialogError!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.apiClient.patch('/transactions/${tx['id']}/description', body: {
                    'description': controller.text.trim().isEmpty ? null : controller.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  widget.refreshNotifier?.notifyDataChanged();
                  await _loadInitial();
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

  Future<void> _showRefundDialog(Map<String, dynamic> expenseTx) async {
    final activeAccounts = _accounts
        .where((a) => a['is_active'] == true && a['currency_id'] == expenseTx['currency_id'])
        .toList();

    if (activeAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cuentas activas en la moneda del gasto.')),
      );
      return;
    }

    String accountId = activeAccounts.first['id'] as String;
    DateTime occurredAt = DateTime.now();
    final amountController = TextEditingController();
    final descController = TextEditingController();
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Registrar devolución'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Cuenta receptora'),
                  items: activeAccounts
                      .map((a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(a['name'] as String),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => accountId = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [ThousandsSeparatorInputFormatter(allowDecimal: true)],
                  decoration: InputDecoration(
                    labelText: 'Importe a devolver',
                    helperText: 'Máx. gasto original: ${_formatTxAmount(expenseTx)}',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Fecha y hora'),
                  subtitle: Text(_dateFormat.format(occurredAt)),
                  onTap: () async {
                    final picked = await _pickDateTime(ctx, occurredAt);
                    if (picked != null) setDialogState(() => occurredAt = picked);
                  },
                ),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                ),
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
                  final desc = descController.text.trim();
                  await widget.apiClient.post('/transactions/refund', body: {
                    'client_request_id': _uuid.v4(),
                    'original_transaction_id': expenseTx['id'],
                    'account_id': accountId,
                    'amount': CurrencyFormatter.toApiDecimal(amountController.text),
                    'occurred_at': occurredAt.toUtc().toIso8601String(),
                    if (desc.isNotEmpty) 'description': desc,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  widget.refreshNotifier?.notifyDataChanged();
                  await _loadInitial();
                } catch (e) {
                  setDialogState(() => dialogError = e.toString());
                }
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReplaceTransactionDialog(Map<String, dynamic> tx) async {
    final activeAccounts = _accounts.where((a) => a['is_active'] == true).toList();
    final activeCategories = _categories.where((c) => c['is_active'] == true).toList();
    if (activeAccounts.isEmpty) return;

    final type = tx['type'] as String;
    final movements = List<Map<String, dynamic>>.from(
      (tx['account_movements'] as List?) ?? const [],
    );

    String accountId = activeAccounts.first['id'] as String;
    String? toAccountId;
    String initialAmountStr = (tx['amount'] ?? '0').toString();

    if (type == 'transfer') {
      for (final m in movements) {
        final signed = (m['signed_amount'] ?? '0').toString();
        if (signed.startsWith('-')) {
          accountId = m['account_id'] as String;
        } else {
          toAccountId = m['account_id'] as String;
        }
      }
    } else if (movements.isNotEmpty) {
      accountId = movements.first['account_id'] as String;
      if (type == 'adjustment') {
        initialAmountStr = (movements.first['signed_amount'] ?? '0').toString();
      }
    }

    if (!activeAccounts.any((a) => a['id'] == accountId)) {
      accountId = activeAccounts.first['id'] as String;
    }

    String? categoryId = tx['category_id'] as String?;
    DateTime occurredAt =
        DateTime.tryParse((tx['occurred_at'] ?? '').toString())?.toLocal() ?? DateTime.now();

    final currency = _currenciesById[tx['currency_id'] as String?];
    final decimals = (currency?['decimal_places'] as num?)?.toInt() ?? 0;
    final amountController = TextEditingController(
      text: CurrencyFormatter.format(
        amount: initialAmountStr,
        symbol: '',
        decimalPlaces: decimals,
      ),
    );
    final descController = TextEditingController(text: (tx['description'] as String?) ?? '');
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final matchingCategories = activeCategories.where((c) => c['type'] == type).toList();
          if ((type == 'income' || type == 'expense') &&
              (categoryId == null || !matchingCategories.any((c) => c['id'] == categoryId))) {
            categoryId = matchingCategories.isNotEmpty ? matchingCategories.first['id'] as String : null;
          }

          return AlertDialog(
            title: Text('Editar ${_labelForType(type).toLowerCase()}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: accountId,
                    decoration: InputDecoration(
                      labelText: type == 'transfer' ? 'Cuenta origen' : 'Cuenta',
                    ),
                    items: activeAccounts
                        .map((a) => DropdownMenuItem(
                              value: a['id'] as String,
                              child: Text(a['name'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => accountId = v!),
                  ),
                  if (type == 'transfer') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: activeAccounts.any((a) => a['id'] == toAccountId && a['id'] != accountId)
                          ? toAccountId
                          : null,
                      decoration: const InputDecoration(labelText: 'Cuenta destino'),
                      items: activeAccounts
                          .where((a) => a['id'] != accountId)
                          .map((a) => DropdownMenuItem(
                                value: a['id'] as String,
                                child: Text(a['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => toAccountId = v),
                    ),
                  ],
                  if (type == 'income' || type == 'expense') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: categoryId,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: matchingCategories
                          .map((c) => DropdownMenuItem(
                                value: c['id'] as String,
                                child: Text(c['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => categoryId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: type == 'adjustment'
                        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                        : const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      ThousandsSeparatorInputFormatter(
                        allowNegative: type == 'adjustment',
                        allowDecimal: true,
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: type == 'adjustment'
                          ? 'Importe con signo (+ o -)'
                          : 'Importe',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Fecha y hora'),
                    subtitle: Text(_dateFormat.format(occurredAt)),
                    onTap: () async {
                      final picked = await _pickDateTime(ctx, occurredAt);
                      if (picked != null) setDialogState(() => occurredAt = picked);
                    },
                  ),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                  ),
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
                    final desc = descController.text.trim();
                    await widget.apiClient.put('/transactions/${tx['id']}', body: {
                      'client_request_id': _uuid.v4(),
                      'account_id': accountId,
                      'amount': CurrencyFormatter.toApiDecimal(amountController.text),
                      'occurred_at': occurredAt.toUtc().toIso8601String(),
                      if (type == 'income' || type == 'expense') 'category_id': categoryId,
                      if (type == 'transfer') 'to_account_id': toAccountId,
                      if (desc.isNotEmpty) 'description': desc,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    widget.refreshNotifier?.notifyDataChanged();
                    await _loadInitial();
                  } catch (e) {
                    setDialogState(() => dialogError = e.toString());
                  }
                },
                child: const Text('Guardar cambios'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCreateTransactionDialog() async {
    try {
      final results = await Future.wait([
        widget.apiClient.get('/accounts'),
        widget.apiClient.get('/categories'),
      ]);
      if (!mounted) return;

      final accounts = List<Map<String, dynamic>>.from(results[0] as List)
          .where((a) => a['is_active'] == true)
          .toList();
      final categories = List<Map<String, dynamic>>.from(results[1] as List)
          .where((c) => c['is_active'] == true)
          .toList();

      if (accounts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Primero crea una cuenta activa en la pestaña Cuentas.')),
        );
        return;
      }

      String opType = 'expense';
      String accountId = accounts.first['id'] as String;
      String? toAccountId = accounts.length > 1 ? accounts[1]['id'] as String : null;
      String? categoryId;
      DateTime occurredAt = DateTime.now();
      final amountController = TextEditingController();
      final descController = TextEditingController();
      String? dialogError;

      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final matchingCategories = categories.where((c) => c['type'] == opType).toList();
            if ((opType == 'income' || opType == 'expense') &&
                (categoryId == null || !matchingCategories.any((c) => c['id'] == categoryId))) {
              categoryId = matchingCategories.isNotEmpty ? matchingCategories.first['id'] as String : null;
            }

            return AlertDialog(
              title: const Text('Nueva operación'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: opType,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      items: const [
                        DropdownMenuItem(value: 'expense', child: Text('Gasto')),
                        DropdownMenuItem(value: 'income', child: Text('Ingreso')),
                        DropdownMenuItem(value: 'transfer', child: Text('Transferencia / Pago tarjeta')),
                        DropdownMenuItem(value: 'adjustment', child: Text('Ajuste de saldo')),
                      ],
                      onChanged: (v) => setDialogState(() {
                        opType = v ?? 'expense';
                        categoryId = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: accountId,
                      decoration: InputDecoration(
                        labelText: opType == 'transfer' ? 'Cuenta origen' : 'Cuenta',
                      ),
                      items: accounts
                          .map((a) => DropdownMenuItem(
                                value: a['id'] as String,
                                child: Text(a['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => accountId = v!),
                    ),
                    if (opType == 'transfer') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: accounts.any((a) => a['id'] == toAccountId && a['id'] != accountId)
                            ? toAccountId
                            : null,
                        decoration: const InputDecoration(labelText: 'Cuenta destino'),
                        items: accounts
                            .where((a) => a['id'] != accountId)
                            .map((a) => DropdownMenuItem(
                                  value: a['id'] as String,
                                  child: Text(a['name'] as String),
                                ))
                            .toList(),
                        onChanged: (v) => setDialogState(() => toAccountId = v),
                      ),
                    ] else if (opType == 'income' || opType == 'expense') ...[
                      const SizedBox(height: 12),
                      if (matchingCategories.isEmpty)
                        const Text(
                          'No tienes categorías activas para este tipo. Créala primero en la pestaña Categorías.',
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: categoryId,
                          decoration: const InputDecoration(labelText: 'Categoría'),
                          items: matchingCategories
                              .map((c) => DropdownMenuItem(
                                    value: c['id'] as String,
                                    child: Text(c['name'] as String),
                                  ))
                              .toList(),
                          onChanged: (v) => setDialogState(() => categoryId = v),
                        ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: opType == 'adjustment'
                          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                          : const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(
                          allowNegative: opType == 'adjustment',
                          allowDecimal: true,
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: opType == 'adjustment'
                            ? 'Importe (+ suma, - resta)'
                            : 'Importe',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: const Text('Fecha y hora'),
                      subtitle: Text(_dateFormat.format(occurredAt)),
                      onTap: () async {
                        final picked = await _pickDateTime(ctx, occurredAt);
                        if (picked != null) setDialogState(() => occurredAt = picked);
                      },
                    ),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                    ),
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
                      final clientRequestId = _uuid.v4();
                      final occurredIso = occurredAt.toUtc().toIso8601String();
                      final amount = CurrencyFormatter.toApiDecimal(amountController.text);
                      final desc = descController.text.trim();

                      if (opType == 'transfer') {
                        await widget.apiClient.post('/transactions/transfer', body: {
                          'client_request_id': clientRequestId,
                          'from_account_id': accountId,
                          'to_account_id': toAccountId,
                          'amount': amount,
                          'occurred_at': occurredIso,
                          if (desc.isNotEmpty) 'description': desc,
                        });
                      } else if (opType == 'adjustment') {
                        await widget.apiClient.post('/transactions/adjustment', body: {
                          'client_request_id': clientRequestId,
                          'account_id': accountId,
                          'signed_amount': amount,
                          'occurred_at': occurredIso,
                          if (desc.isNotEmpty) 'description': desc,
                        });
                      } else {
                        await widget.apiClient.post('/transactions/$opType', body: {
                          'client_request_id': clientRequestId,
                          'account_id': accountId,
                          'category_id': categoryId,
                          'amount': amount,
                          'occurred_at': occurredIso,
                          if (desc.isNotEmpty) 'description': desc,
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      widget.refreshNotifier?.notifyDataChanged();
                      await _loadInitial();
                    } catch (e) {
                      setDialogState(() => dialogError = e.toString());
                    }
                  },
                  child: const Text('Registrar'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _voidTransaction(String id) async {
    try {
      await widget.apiClient.post('/transactions/$id/void', body: {'void_reason': 'voided_by_user'});
      widget.refreshNotifier?.notifyDataChanged();
      await _loadInitial();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _items.where((tx) {
      if (!_showVoided && tx['status'] == 'voided') return false;
      if (_filterType != 'all' && tx['type'] != _filterType) return false;
      if (_filterAccountId != null) {
        final movements = List<Map<String, dynamic>>.from(
          (tx['account_movements'] as List?) ?? const [],
        );
        if (!movements.any((m) => m['account_id'] == _filterAccountId)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinancialColors>()!;
    final visibleItems = _filteredItems;

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Movimientos', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              FilledButton.icon(
                onPressed: _showCreateTransactionDialog,
                icon: const Icon(Icons.add),
                label: const Text('Registrar'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Barra de filtros rápidos
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChipItem(
                  label: 'Todos',
                  selected: _filterType == 'all',
                  onSelected: () => setState(() => _filterType = 'all'),
                ),
                const SizedBox(width: 6),
                _FilterChipItem(
                  label: 'Gastos',
                  selected: _filterType == 'expense',
                  onSelected: () => setState(() => _filterType = 'expense'),
                ),
                const SizedBox(width: 6),
                _FilterChipItem(
                  label: 'Ingresos',
                  selected: _filterType == 'income',
                  onSelected: () => setState(() => _filterType = 'income'),
                ),
                const SizedBox(width: 6),
                _FilterChipItem(
                  label: 'Transferencias',
                  selected: _filterType == 'transfer',
                  onSelected: () => setState(() => _filterType = 'transfer'),
                ),
                const SizedBox(width: 6),
                _FilterChipItem(
                  label: 'Devoluciones',
                  selected: _filterType == 'refund',
                  onSelected: () => setState(() => _filterType = 'refund'),
                ),
                const SizedBox(width: 6),
                _FilterChipItem(
                  label: 'Ajustes',
                  selected: _filterType == 'adjustment',
                  onSelected: () => setState(() => _filterType = 'adjustment'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_accounts.isNotEmpty)
                DropdownButton<String?>(
                  value: _filterAccountId,
                  hint: const Text('Todas las cuentas'),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todas las cuentas')),
                    ..._accounts.map(
                      (a) => DropdownMenuItem<String?>(
                        value: a['id'] as String,
                        child: Text(a['name'] as String),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterAccountId = v),
                ),
              FilterChip(
                label: const Text('Ver anuladas'),
                selected: _showVoided,
                onSelected: (v) => setState(() => _showVoided = v),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          else if (visibleItems.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No hay movimientos que coincidan con los filtros actuales.'),
              ),
            )
          else ...[
            ...visibleItems.map((tx) {
              final type = tx['type'] as String? ?? '';
              final isVoided = tx['status'] == 'voided';
              final color = isVoided
                  ? colors.voided
                  : switch (type) {
                      'income' || 'refund' => colors.income,
                      'expense' => colors.expense,
                      'transfer' => colors.transfer,
                      _ => colors.warning,
                    };

              final categoryName = tx['category_id'] != null
                  ? (_categoryNames[tx['category_id']] ?? '')
                  : '';
              final titleText = (tx['description'] as String?)?.trim().isNotEmpty == true
                  ? tx['description'] as String
                  : (categoryName.isNotEmpty ? categoryName : _labelForType(type));
              final flowText = _describeAccountFlow(tx);
              final dateText = _formatTxDate(tx['occurred_at']);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _showTransactionDetail(tx),
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(_iconForType(type), color: color, size: 20),
                  ),
                  title: Text(
                    titleText,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: isVoided ? TextDecoration.lineThrough : null,
                      color: isVoided ? colors.voided : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(flowText, style: theme.textTheme.bodySmall),
                      Text(
                        '${categoryName.isNotEmpty ? '$categoryName • ' : ''}$dateText',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(
                    _formatTxAmount(tx),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      decoration: isVoided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              );
            }),
            if (_nextCursor != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: OutlinedButton(
                    onPressed: _loadingMore ? null : _loadMore,
                    child: Text(_loadingMore ? 'Cargando...' : 'Cargar más'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  IconData _iconForType(String type) => switch (type) {
        'income' => Icons.south_west_rounded,
        'expense' => Icons.north_east_rounded,
        'transfer' => Icons.sync_alt_rounded,
        'refund' => Icons.undo_rounded,
        'adjustment' => Icons.tune_rounded,
        _ => Icons.receipt_long_rounded,
      };

  String _labelForType(String type) => switch (type) {
        'income' => 'Ingreso',
        'expense' => 'Gasto',
        'transfer' => 'Transferencia',
        'refund' => 'Devolución',
        'adjustment' => 'Ajuste',
        _ => type,
      };
}

class _FilterChipItem extends StatelessWidget {
  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
