import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/theme_controller.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.themeController,
  });

  final ThemeController themeController;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isSignUp = false;
  bool _awaitingOtp = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submitCredentials() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final auth = Supabase.instance.client.auth;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isSignUp) {
        final displayName = _displayNameController.text.trim();
        final response = await auth.signUp(
          email: email,
          password: password,
          data: displayName.isEmpty ? null : {'display_name': displayName},
        );
        if (response.session == null && mounted) {
          setState(() {
            _awaitingOtp = true;
            _otpController.clear();
            _infoMessage =
                'Enviamos un código de 6 dígitos a $email. Ingrésalo para confirmar tu cuenta.';
          });
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) {
        if (e.message.toLowerCase().contains('email not confirmed')) {
          setState(() {
            _awaitingOtp = true;
            _otpController.clear();
            _errorMessage = null;
            _infoMessage = 'Tu correo aún no está confirmado. Ingresa o reenvía el código de 6 dígitos.';
          });
        } else {
          setState(() => _errorMessage = e.message);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'No se pudo completar la autenticación.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final auth = Supabase.instance.client.auth;
    final email = _emailController.text.trim();
    final token = _otpController.text.trim();

    try {
      await auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'No se pudo verificar el código.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final auth = Supabase.instance.client.auth;
    final email = _emailController.text.trim();

    try {
      await auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (mounted) {
        setState(() {
          _infoMessage = 'Enviamos un nuevo código de verificación a $email.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'No se pudo reenviar el código.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ñangareko',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro',
            icon: Icon(isDark ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded),
            onPressed: () => widget.themeController.toggleLightDark(context),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: _awaitingOtp
                      ? _buildOtpStep(theme)
                      : _buildCredentialsStep(theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCredentialsStep(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isSignUp ? 'Crear cuenta' : 'Iniciar sesión',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Gestiona tus finanzas personales de forma segura.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (_isSignUp) ...[
          TextFormField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Nombre visible (opcional)',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 14),
        ],
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty || !v.contains('@')) {
              return 'Ingresa un correo válido.';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _passwordController,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          validator: (value) {
            if ((value ?? '').length < 6) {
              return 'Debe tener al menos 6 caracteres.';
            }
            return null;
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (_infoMessage != null) ...[
          const SizedBox(height: 14),
          Text(_infoMessage!, style: TextStyle(color: theme.colorScheme.primary)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _isLoading ? null : _submitCredentials,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isSignUp ? 'Registrarme' : 'Ingresar'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => setState(() {
                    _isSignUp = !_isSignUp;
                    _errorMessage = null;
                    _infoMessage = null;
                  }),
          child: Text(
            _isSignUp ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate',
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verifica tu correo',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _emailController.text.trim(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Código de 6 dígitos',
            prefixIcon: Icon(Icons.pin_outlined),
            counterText: '',
          ),
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.length != 6 || int.tryParse(v) == null) {
              return 'Ingresa el código numérico de 6 dígitos.';
            }
            return null;
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (_infoMessage != null) ...[
          const SizedBox(height: 14),
          Text(_infoMessage!, style: TextStyle(color: theme.colorScheme.primary)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _isLoading ? null : _verifyOtp,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verificar cuenta'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isLoading ? null : _resendOtp,
          child: const Text('Reenviar código'),
        ),
        TextButton(
          onPressed: _isLoading
              ? null
              : () => setState(() {
                    _awaitingOtp = false;
                    _errorMessage = null;
                    _infoMessage = null;
                  }),
          child: const Text('Volver'),
        ),
      ],
    );
  }
}
