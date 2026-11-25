import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.apiClient});

  final ApiClient apiClient;

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
    _loadData();
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
      setState(() => _error = e.toString());
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
    String? parentId = existing?['parent_id'] as String?;
    bool isActive = existing?['is_active'] as bool? ?? true;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final rootCategories = _categories
              .where((c) =>
                  c['type'] == formType &&
                  c['parent_id'] == null &&
                  c['is_active'] == true &&
                  c['id'] != existing?['id'])
              .toList();

          if (parentId != null && !rootCategories.any((c) => c['id'] == parentId)) {
            parentId = null;
          }

          return AlertDialog(
            title: Text(isEditing ? 'Editar categoría' : 'Nueva categoría'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: formType,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(value: 'expense', child: Text('Gasto')),
                      DropdownMenuItem(value: 'income', child: Text('Ingreso')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        formType = v;
                        parentId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: parentId,
                    decoration: const InputDecoration(labelText: 'Categoría padre (opcional)'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Ninguna (categoría raíz)'),
                      ),
                      ...rootCategories.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c['id'] as String,
                          child: Text(c['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => parentId = v),
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
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  try {
                    if (isEditing) {
                      await widget.apiClient.patch('/categories/${existing['id']}', body: {
                        'name': nameController.text.trim(),
                        'type': formType,
                        'parent_id': parentId,
                        'is_active': isActive,
                      });
                    } else {
                      await widget.apiClient.post('/categories', body: {
                        'name': nameController.text.trim(),
                        'type': formType,
                        'parent_id': ?parentId,
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() => _selectedType = formType);
                    await _loadData();
                  } catch (e) {
                    setDialogState(() => dialogError = e.toString());
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
              Text(
                'Categorías',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
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
              final isSubcategory = c['parent_id'] != null;
              final type = c['type'] as String? ?? 'expense';
              final isIncome = type == 'income';
              final typeColor = isIncome ? colors.income : colors.expense;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _showCategoryDialog(existing: c),
                  leading: Icon(
                    isSubcategory ? Icons.subdirectory_arrow_right : Icons.label_outline,
                    color: typeColor,
                  ),
                  title: Text(c['name'] as String? ?? ''),
                  subtitle: Text(isSubcategory ? 'Subcategoría' : 'Categoría principal'),
                  trailing: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
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
                      if (c['is_active'] != true)
                        const Chip(label: Text('Inactiva')),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
