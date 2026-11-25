import 'package:flutter/material.dart';

@immutable
class FinancialColors extends ThemeExtension<FinancialColors> {
  const FinancialColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.transfer,
    required this.voided,
  });

  final Color income;
  final Color expense;
  final Color warning;
  final Color transfer;
  final Color voided;

  static FinancialColors lightFor(AppColorPalette palette) => switch (palette) {
        AppColorPalette.azul => const FinancialColors(
            income: Color(0xFF0284C7),
            expense: Color(0xFF1E293B),
            warning: Color(0xFFD97706),
            transfer: Color(0xFF1D4ED8),
            voided: Color(0xFF64748B),
          ),
        AppColorPalette.esmeralda => const FinancialColors(
            income: Color(0xFF059669),
            expense: Color(0xFFB45309),
            warning: Color(0xFFD97706),
            transfer: Color(0xFF0D9488),
            voided: Color(0xFF64748B),
          ),
        AppColorPalette.violeta => const FinancialColors(
            income: Color(0xFF7C3AED),
            expense: Color(0xFFBE185D),
            warning: Color(0xFFD97706),
            transfer: Color(0xFF6D28D9),
            voided: Color(0xFF64748B),
          ),
        AppColorPalette.marfilTurquesa => const FinancialColors(
            income: Color(0xFF00A896),
            expense: Color(0xFF151515),
            warning: Color(0xFFC27803),
            transfer: Color(0xFF0E7490),
            voided: Color(0xFF6B655B),
          ),
        AppColorPalette.zafiroNaranja => const FinancialColors(
            income: Color(0xFFFF5A12),
            expense: Color(0xFF13285A),
            warning: Color(0xFFD97706),
            transfer: Color(0xFF1D4ED8),
            voided: Color(0xFF64748B),
          ),
      };

  static FinancialColors darkFor(AppColorPalette palette) => switch (palette) {
        AppColorPalette.azul => const FinancialColors(
            income: Color(0xFF38BDF8),
            expense: Color(0xFFFB923C),
            warning: Color(0xFFFBBF24),
            transfer: Color(0xFF60A5FA),
            voided: Color(0xFF94A3B8),
          ),
        AppColorPalette.esmeralda => const FinancialColors(
            income: Color(0xFF34D399),
            expense: Color(0xFFFBBF24),
            warning: Color(0xFFF59E0B),
            transfer: Color(0xFF2DD4BF),
            voided: Color(0xFF94A3B8),
          ),
        AppColorPalette.violeta => const FinancialColors(
            income: Color(0xFFA78BFA),
            expense: Color(0xFFF472B6),
            warning: Color(0xFFFBBF24),
            transfer: Color(0xFFC084FC),
            voided: Color(0xFF94A3B8),
          ),
        AppColorPalette.marfilTurquesa => const FinancialColors(
            income: Color(0xFF2DD4BF),
            expense: Color(0xFFEEE3CC),
            warning: Color(0xFFFBBF24),
            transfer: Color(0xFF38BDF8),
            voided: Color(0xFF9E988C),
          ),
        AppColorPalette.zafiroNaranja => const FinancialColors(
            income: Color(0xFFFF7A3D),
            expense: Color(0xFFECE6DC),
            warning: Color(0xFFFBBF24),
            transfer: Color(0xFF60A5FA),
            voided: Color(0xFFA6B4D0),
          ),
      };

  @override
  FinancialColors copyWith({
    Color? income,
    Color? expense,
    Color? warning,
    Color? transfer,
    Color? voided,
  }) {
    return FinancialColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      warning: warning ?? this.warning,
      transfer: transfer ?? this.transfer,
      voided: voided ?? this.voided,
    );
  }

  @override
  FinancialColors lerp(ThemeExtension<FinancialColors>? other, double t) {
    if (other is! FinancialColors) {
      return this;
    }
    return FinancialColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      voided: Color.lerp(voided, other.voided, t)!,
    );
  }
}

enum AppColorPalette {
  azul(
    'Azul',
    Color(0xFF1D4ED8),
    Color(0xFF3B82F6),
    Color(0xFFDBEAFE),
    Color(0xFF1E3A8A),
  ),
  esmeralda(
    'Esmeralda',
    Color(0xFF047857),
    Color(0xFF10B981),
    Color(0xFFD1FAE5),
    Color(0xFF064E3B),
  ),
  violeta(
    'Violeta',
    Color(0xFF6D28D9),
    Color(0xFF8B5CF6),
    Color(0xFFEDE9FE),
    Color(0xFF4C1D95),
  ),
  marfilTurquesa(
    'Marfil & Turquesa',
    Color(0xFF00A896),
    Color(0xFF2DD4BF),
    Color(0xFFCCF2EC),
    Color(0xFF134E4A),
  ),
  zafiroNaranja(
    'Zafiro & Naranja',
    Color(0xFFFF5A12),
    Color(0xFFFF7A3D),
    Color(0xFFFFE4D6),
    Color(0xFF223C7A),
  );

  const AppColorPalette(
    this.label,
    this.lightPrimary,
    this.darkPrimary,
    this.lightContainer,
    this.darkContainer,
  );

  final String label;
  final Color lightPrimary;
  final Color darkPrimary;
  final Color lightContainer;
  final Color darkContainer;

  Color get seedColor => lightPrimary;
}

class _SurfaceSpec {
  const _SurfaceSpec({
    required this.bg,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineBorder,
    required this.highest,
    required this.inputFill,
    required this.secondary,
    required this.onPrimary,
  });

  final Color bg;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineBorder;
  final Color highest;
  final Color inputFill;
  final Color secondary;
  final Color onPrimary;
}

class AppTheme {
  const AppTheme._();

  static _SurfaceSpec _lightSpec(AppColorPalette palette) => switch (palette) {
        AppColorPalette.marfilTurquesa => _SurfaceSpec(
            bg: const Color(0xFFEEE3CC),
            surface: const Color(0xFFF7F0E2),
            onSurface: const Color(0xFF151515),
            onSurfaceVariant: const Color(0xFF4B463D),
            outline: const Color(0xFFC9C1AE),
            outlineBorder: const Color(0xFFDFD2B7),
            highest: const Color(0xFFE5D8BE),
            inputFill: const Color(0xFFF3EBD8),
            secondary: const Color(0xFF151515),
            onPrimary: Colors.white,
          ),
        AppColorPalette.zafiroNaranja => _SurfaceSpec(
            bg: const Color(0xFFECE6DC),
            surface: const Color(0xFFF7F4EE),
            onSurface: const Color(0xFF13285A),
            onSurfaceVariant: const Color(0xFF3E4F75),
            outline: const Color(0xFFBFC5D4),
            outlineBorder: const Color(0xFFDAD3C6),
            highest: const Color(0xFFE1D9CC),
            inputFill: const Color(0xFFF2EDE4),
            secondary: const Color(0xFF13285A),
            onPrimary: Colors.white,
          ),
        _ => _SurfaceSpec(
            bg: const Color(0xFFF4F6F9),
            surface: const Color(0xFFFFFFFF),
            onSurface: const Color(0xFF0F172A),
            onSurfaceVariant: const Color(0xFF475569),
            outline: const Color(0xFFCBD5E1),
            outlineBorder: const Color(0xFFE2E8F0),
            highest: const Color(0xFFE9EEF5),
            inputFill: const Color(0xFFF8FAFC),
            secondary: palette.lightPrimary,
            onPrimary: Colors.white,
          ),
      };

  static _SurfaceSpec _darkSpec(AppColorPalette palette) => switch (palette) {
        AppColorPalette.marfilTurquesa => _SurfaceSpec(
            bg: const Color(0xFF151515),
            surface: const Color(0xFF1F1E1C),
            onSurface: const Color(0xFFEEE3CC),
            onSurfaceVariant: const Color(0xFFB8AF9C),
            outline: const Color(0xFF423F38),
            outlineBorder: const Color(0xFF32302B),
            highest: const Color(0xFF292723),
            inputFill: const Color(0xFF181715),
            secondary: const Color(0xFFEEE3CC),
            onPrimary: const Color(0xFF06101F),
          ),
        AppColorPalette.zafiroNaranja => _SurfaceSpec(
            bg: const Color(0xFF13285A),
            surface: const Color(0xFF1B3573),
            onSurface: const Color(0xFFECE6DC),
            onSurfaceVariant: const Color(0xFFB8C4DF),
            outline: const Color(0xFF3D5A9E),
            outlineBorder: const Color(0xFF2C488C),
            highest: const Color(0xFF23428A),
            inputFill: const Color(0xFF162E68),
            secondary: const Color(0xFFECE6DC),
            onPrimary: Colors.white,
          ),
        _ => _SurfaceSpec(
            bg: const Color(0xFF0B0F19),
            surface: const Color(0xFF131A2A),
            onSurface: const Color(0xFFF8FAFC),
            onSurfaceVariant: const Color(0xFF94A3B8),
            outline: const Color(0xFF334155),
            outlineBorder: const Color(0xFF243047),
            highest: const Color(0xFF1E293B),
            inputFill: const Color(0xFF0F172A),
            secondary: palette.darkPrimary,
            onPrimary: const Color(0xFF06101F),
          ),
      };

  static ThemeData light([AppColorPalette palette = AppColorPalette.azul]) {
    final spec = _lightSpec(palette);
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: palette.lightPrimary,
      onPrimary: spec.onPrimary,
      primaryContainer: palette.lightContainer,
      onPrimaryContainer: spec.onSurface,
      secondary: spec.secondary,
      onSecondary: Colors.white,
      secondaryContainer: palette.lightContainer,
      onSecondaryContainer: spec.onSurface,
      error: const Color(0xFFE11D48),
      onError: Colors.white,
      surface: spec.surface,
      onSurface: spec.onSurface,
      onSurfaceVariant: spec.onSurfaceVariant,
      outline: spec.outline,
      outlineVariant: spec.outlineBorder,
      surfaceContainerHighest: spec.highest,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      spec: spec,
      indicatorColor: palette.lightContainer,
      financialColors: FinancialColors.lightFor(palette),
    );
  }

  static ThemeData dark([AppColorPalette palette = AppColorPalette.azul]) {
    final spec = _darkSpec(palette);
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.darkPrimary,
      onPrimary: spec.onPrimary,
      primaryContainer: palette.darkContainer,
      onPrimaryContainer: spec.onSurface,
      secondary: spec.secondary,
      onSecondary: const Color(0xFF06101F),
      secondaryContainer: palette.darkContainer,
      onSecondaryContainer: spec.onSurface,
      error: const Color(0xFFFB7185),
      onError: const Color(0xFF1F070E),
      surface: spec.surface,
      onSurface: spec.onSurface,
      onSurfaceVariant: spec.onSurfaceVariant,
      outline: spec.outline,
      outlineVariant: spec.outlineBorder,
      surfaceContainerHighest: spec.highest,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      spec: spec,
      indicatorColor: palette.darkContainer,
      financialColors: FinancialColors.darkFor(palette),
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required _SurfaceSpec spec,
    required Color indicatorColor,
    required FinancialColors financialColors,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: spec.bg,
      appBarTheme: AppBarTheme(
        backgroundColor: spec.bg,
        foregroundColor: spec.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: spec.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: spec.outlineBorder),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: spec.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: indicatorColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: spec.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: spec.outlineBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: spec.outlineBorder),
        ),
      ),
      extensions: [financialColors],
    );
  }
}
