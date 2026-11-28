import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/app_feedback.dart';

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
      AppFeedback.showSuccess(context, 'Perfil actualizado correctamente.');
    } catch (e) {
      if (!mounted) return;
      final msg = AppFeedback.formatError(e);
      setState(() => _error = msg);
      AppFeedback.showError(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool updating = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: const Text('Cambiar contraseña'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: newPassController,
                      obscureText: obscureNew,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Nueva contraseña',
                        hintText: 'Mínimo 6 caracteres',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: obscureNew ? 'Mostrar' : 'Ocultar',
                          icon: Icon(obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPassController,
                      obscureText: obscureConfirm,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Confirmar nueva contraseña',
                        hintText: 'Repite tu nueva contraseña',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          tooltip: obscureConfirm ? 'Mostrar' : 'Ocultar',
                          icon: Icon(obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                        ),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        dialogError!,
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: updating ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: updating
                  ? null
                  : () async {
                      final newPassword = newPassController.text;
                      final confirmPassword = confirmPassController.text;

                      if (newPassword.length < 6) {
                        setDialogState(() => dialogError = 'La contraseña debe tener al menos 6 caracteres.');
                        return;
                      }
                      if (newPassword != confirmPassword) {
                        setDialogState(() => dialogError = 'Las contraseñas no coinciden.');
                        return;
                      }

                      setDialogState(() {
                        updating = true;
                        dialogError = null;
                      });

                      try {
                        await Supabase.instance.client.auth.updateUser(
                          UserAttributes(password: newPassword),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          AppFeedback.showSuccess(context, 'Contraseña actualizada correctamente.');
                        }
                      } on AuthException catch (e) {
                        setDialogState(() => dialogError = AppFeedback.formatError(e.message));
                      } catch (e) {
                        setDialogState(() => dialogError = AppFeedback.formatError(e));
                      } finally {
                        if (ctx.mounted) setDialogState(() => updating = false);
                      }
                    },
              child: Text(updating ? 'Actualizando...' : 'Actualizar'),
            ),
          ],
        ),
      ),
    );
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
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto, size: 18),
                            label: Text('Sistema', overflow: TextOverflow.ellipsis),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined, size: 18),
                            label: Text('Claro', overflow: TextOverflow.ellipsis),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined, size: 18),
                            label: Text('Oscuro', overflow: TextOverflow.ellipsis),
                          ),
                        ],
                        selected: {widget.themeController.themeMode},
                        onSelectionChanged: (s) => widget.themeController.setThemeMode(s.first),
                      ),
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
                    decoration: const InputDecoration(
                      labelText: 'Nombre visible',
                      hintText: 'Ej.: David Maldonado',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_currencies.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCurrencyId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Moneda por defecto'),
                      items: _currencies
                          .map((c) => DropdownMenuItem(
                                value: c['id'] as String,
                                child: Text(
                                  '${c['code']} - ${c['name']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCurrencyId = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _timezoneController,
                    decoration: const InputDecoration(
                      labelText: 'Zona horaria (IANA)',
                      hintText: 'Ej.: America/Asuncion',
                      helperText: 'Se usa para agrupar tus resúmenes en tu hora local.',
                      helperMaxLines: 2,
                    ),
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
                  FilledButton.tonalIcon(
                    onPressed: _showChangePasswordDialog,
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Cambiar contraseña'),
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
