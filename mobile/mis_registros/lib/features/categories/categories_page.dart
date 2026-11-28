import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/state/ledger_refresh_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/category_icon_resolver.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({
    super.key,
    required this.apiClient,
    this.refreshNotifier,
  });

  final ApiClient apiClient;
  final LedgerRefreshNotifier? refreshNotifier;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  bool _loading = true;
  String? _error;
  String _selectedType = 'expense';
  List<Map<String, dynamic>> _categories = const [];

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
      final data = await widget.apiClient.get('/categories');
      if (!mounted) return;
      setState(() => _categories = List<Map<String, dynamic>>.from(data as List));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppFeedback.formatError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCategoryDialog({Map<String, dynamic>? existing}) async {
    final isEditing = existing != null;
    final nameController = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    String formType = existing?['type'] as String? ?? _selectedType;
    bool isActive = existing?['is_active'] as bool? ?? true;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            title: Text(isEditing ? 'Editar categoría' : 'Nueva categoría'),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: formType,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tipo'),
                        items: const [
                          DropdownMenuItem(value: 'expense', child: Text('Gasto', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 'income', child: Text('Ingreso', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(() => formType = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: Icon(
                            CategoryIconResolver.resolve(nameController.text, type: formType),
                          ),
                          hintText: formType == 'income'
                              ? 'Ej.: Salario, Freelance, Ventas, Aguinaldo'
                              : 'Ej.: Supermercado, Combustible, Alquiler, Salud',
                        ),
                      ),
                      if (isEditing) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Activa'),
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
                      await widget.apiClient.delete('/categories/${existing['id']}');
                      if (ctx.mounted) Navigator.pop(ctx);
                      widget.refreshNotifier?.notifyDataChanged();
                      await _loadData();
                      if (mounted) AppFeedback.showSuccess(context, 'Categoría eliminada.');
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
                    setDialogState(() => dialogError = 'Ingresa un nombre para la categoría.');
                    return;
                  }
                  try {
                    if (isEditing) {
                      await widget.apiClient.patch('/categories/${existing['id']}', body: {
                        'name': cleanName,
                        'type': formType,
                        'parent_id': null,
                        'is_active': isActive,
                      });
                    } else {
                      await widget.apiClient.post('/categories', body: {
                        'name': cleanName,
                        'type': formType,
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() => _selectedType = formType);
                    widget.refreshNotifier?.notifyDataChanged();
                    await _loadData();
                    if (mounted) {
                      AppFeedback.showSuccess(
                        context,
                        isEditing ? 'Categoría actualizada.' : 'Categoría creada.',
                      );
                    }
                  } catch (e) {
                    setDialogState(() => dialogError = AppFeedback.formatError(e));
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FinancialColors>()!;
    final filtered = _categories.where((c) => c['type'] == _selectedType).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Categorías',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showCategoryDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Nueva'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Gastos')),
              ButtonSegment(value: 'income', label: Text('Ingresos')),
            ],
            selected: {_selectedType},
            onSelectionChanged: (s) => setState(() => _selectedType = s.first),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          else if (filtered.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No tienes categorías en este tipo. Crea la primera para registrar operaciones.'),
              ),
            )
          else
            ...filtered.map((c) {
              final type = c['type'] as String? ?? 'expense';
              final isIncome = type == 'income';
              final typeColor = isIncome ? colors.income : colors.expense;
              final isActive = c['is_active'] == true;
              final categoryName = c['name'] as String? ?? '';
              final iconColor = isActive ? typeColor : colors.voided;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _showCategoryDialog(existing: c),
                  leading: CircleAvatar(
                    backgroundColor: iconColor.withValues(alpha: 0.12),
                    child: Icon(
                      CategoryIconResolver.resolve(categoryName, type: type),
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: isActive ? null : colors.voided),
                  ),
                  subtitle: isActive
                      ? null
                      : Text(
                          'Inactiva',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.voided),
                        ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isIncome ? 'Ingreso' : 'Gasto',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: typeColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
