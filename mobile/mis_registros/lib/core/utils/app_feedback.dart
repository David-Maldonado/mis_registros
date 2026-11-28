import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum FeedbackType { success, error, warning, info }

class AppFeedback {
  const AppFeedback._();

  /// Traduce mensajes técnicos o en inglés a un castellano claro para el usuario.
  static String formatError(Object error) {
    final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    final lower = raw.toLowerCase();

    if (lower.contains('failed to fetch') ||
        lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('clientexception')) {
      return 'No se pudo conectar con el servidor. Verifica tu conexión e intenta de nuevo.';
    }
    if (lower.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (lower.contains('user already registered')) {
      return 'Este correo ya está registrado.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Tu correo aún no fue confirmado.';
    }
    if (lower.contains('token has expired') || lower.contains('otp_expired')) {
      return 'El código expiró o no es válido. Solicita uno nuevo.';
    }
    if (lower.contains('email rate limit exceeded')) {
      return 'Se alcanzó el límite temporal de envíos de correo. Intenta más tarde.';
    }
    if (lower.contains('password should be at least')) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (lower.contains('different from the old password') || lower.contains('same_password')) {
      return 'La nueva contraseña debe ser diferente a la actual.';
    }
    if (lower.contains('jwt expired') || lower.contains('unauthorized')) {
      return 'Tu sesión expiró. Vuelve a iniciar sesión.';
    }
    if (raw.isEmpty) {
      return 'Ocurrió un error inesperado. Intenta nuevamente.';
    }
    return raw;
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, FeedbackType.success);
  }

  static void showError(BuildContext context, Object error) {
    _show(context, formatError(error), FeedbackType.error);
  }

  static void showWarning(BuildContext context, String message) {
    _show(context, message, FeedbackType.warning);
  }

  static void showInfo(BuildContext context, String message) {
    _show(context, message, FeedbackType.info);
  }

  static void _show(BuildContext context, String message, FeedbackType type) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final theme = Theme.of(context);
    final colors = theme.extension<FinancialColors>();
    final isDark = theme.brightness == Brightness.dark;

    final accent = switch (type) {
      FeedbackType.success => colors?.income ?? theme.colorScheme.primary,
      FeedbackType.error => theme.colorScheme.error,
      FeedbackType.warning => colors?.warning ?? const Color(0xFFD97706),
      FeedbackType.info => theme.colorScheme.primary,
    };

    final icon = switch (type) {
      FeedbackType.success => Icons.check_circle_rounded,
      FeedbackType.error => Icons.error_outline_rounded,
      FeedbackType.warning => Icons.warning_amber_rounded,
      FeedbackType.info => Icons.info_outline_rounded,
    };

    final bgColor = isDark ? theme.colorScheme.surface : const Color(0xFF18181B);
    final fgColor = isDark ? theme.colorScheme.onSurface : Colors.white;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: bgColor,
          elevation: 4,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accent.withValues(alpha: 0.65), width: 1.2),
          ),
          duration: Duration(seconds: type == FeedbackType.error ? 4 : 3),
          content: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fgColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
