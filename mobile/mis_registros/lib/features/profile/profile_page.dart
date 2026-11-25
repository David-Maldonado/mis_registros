import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.apiClient,
    required this.themeController,
  });

  final ApiClient apiClient;
  final ThemeController themeController;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _timezoneController = TextEditingController(text: 'America/Asuncion');

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _selectedCurrencyId;
  List<Map<String, dynamic>> _currencies = const [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiClient.get('/profile'),
        widget.apiClient.get('/currencies'),
      ]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>;
      _nameController.text = (profile['display_name'] as String?) ?? '';
      _timezoneController.text = (profile['timezone'] as String?) ?? 'America/Asuncion';
      setState(() {
        _selectedCurrencyId = profile['default_currency_id'] as String?;
        _currencies = List<Map<String, dynamic>>.from(results[1] as List);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_selectedCurrencyId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.apiClient.patch('/profile', body: {
        'display_name': _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        'default_currency_id': _selectedCurrencyId,
        'timezone': _timezoneController.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Perfil y apariencia', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(
              listenable: widget.themeController,
              builder: (context, _) {
                final currentPalette = widget.themeController.palette;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tema de la aplicación',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text('Sistema'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Claro'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Oscuro'),
                        ),
                      ],
                      selected: {widget.themeController.themeMode},
                      onSelectionChanged: (s) => widget.themeController.setThemeMode(s.first),
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        const Icon(Icons.palette_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Color principal',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...AppColorPalette.values.map((palette) {
                      final isSelected = palette == currentPalette;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        selected: isSelected,
                        leading: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: palette.seedColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(palette.label),
                        trailing: isSelected ? const Icon(Icons.check) : null,
                        onTap: () => widget.themeController.setPalette(palette),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Cuenta: $email', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nombre visible'),
                  ),
                  const SizedBox(height: 12),
                  if (_currencies.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCurrencyId,
                      decoration: const InputDecoration(labelText: 'Moneda por defecto'),
                      items: _currencies
                          .map((c) => DropdownMenuItem(
                                value: c['id'] as String,
                                child: Text('${c['code']} - ${c['name']}'),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCurrencyId = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _timezoneController,
                    decoration: const InputDecoration(labelText: 'Zona horaria (IANA)'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _saveProfile,
                    child: Text(_saving ? 'Guardando...' : 'Guardar perfil'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
