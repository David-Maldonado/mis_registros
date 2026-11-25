import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key, required this.apiClient});

  final ApiClient apiClient;

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

  Map<String, String> _accountNames = const {};
  Map<String, String> _categoryNames = const {};
  Map<String, Map<String, dynamic>> _currenciesById = const {};

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiClient.get('/transactions', query: {'limit': '20'}),
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
        'limit': '20',
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Chip(label: Text(_labelForType(type))),
                    Chip(
                      label: Text(isVoided ? 'Anulada' : 'Contabilizada'),
                    ),
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
                if (!isVoided)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _voidTransaction(tx['id'] as String);
                      },
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Anular operación'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
      final amountController = TextEditingController();
      final descController = TextEditingController();
      String? dialogError;

      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final matchingCategories = categories.where((c) => c['type'] == opType).toList();
            if (opType != 'transfer' &&
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
                        initialValue: toAccountId,
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
                    ] else ...[
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(allowDecimal: true),
                      ],
                      decoration: const InputDecoration(labelText: 'Importe'),
                    ),
                    const SizedBox(height: 12),
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
                      final occurredAt = DateTime.now().toUtc().toIso8601String();
                      final amount = CurrencyFormatter.toApiDecimal(amountController.text);
                      final desc = descController.text.trim();

                      if (opType == 'transfer') {
                        await widget.apiClient.post('/transactions/transfer', body: {
                          'client_request_id': clientRequestId,
                          'from_account_id': accountId,
                          'to_account_id': toAccountId,
                          'amount': amount,
                          'occurred_at': occurredAt,
                          if (desc.isNotEmpty) 'description': desc,
                        });
                      } else {
                        await widget.apiClient.post('/transactions/$opType', body: {
                          'client_request_id': clientRequestId,
                          'account_id': accountId,
                          'category_id': categoryId,
                          'amount': amount,
                          'occurred_at': occurredAt,
                          if (desc.isNotEmpty) 'description': desc,
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
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
      await _loadInitial();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinancialColors>()!;

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
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          else if (_items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No hay movimientos registrados todavía.'),
              ),
            )
          else ...[
            ..._items.map((tx) {
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
        'income' => Icons.arrow_upward_rounded,
        'expense' => Icons.arrow_downward_rounded,
        'transfer' => Icons.swap_horiz_rounded,
        'refund' => Icons.replay_rounded,
        'adjustment' => Icons.tune_rounded,
        _ => Icons.receipt_long_outlined,
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
