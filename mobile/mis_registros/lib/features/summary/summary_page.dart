import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import 'annual_breakdown_page.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _MonthCapsulePoint {
  const _MonthCapsulePoint({
    required this.month,
    required this.income,
    required this.expense,
  });

  final int month;
  final double income;
  final double expense;

  double get total => income + expense;
}

class _SummaryPageState extends State<SummaryPage> {
  static const _monthLabels = [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];

  late int _year;
  late int _month;
  bool _loading = true;
  bool _showDetails = false;
  String? _error;

  Map<String, dynamic>? _pygSummary;
  List<_MonthCapsulePoint> _yearBars = const [];
  List<Map<String, dynamic>> _accountFlows = const [];
  String _userName = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Cargar los 12 meses del año seleccionado para la gráfica anual + flujos del mes activo
      final monthFutures = List.generate(
        12,
        (index) => widget.apiClient.get(
          '/reports/monthly-summary',
          query: {'year': '$_year', 'month': '${index + 1}'},
        ),
      );

      final flowsFuture = widget.apiClient.get(
        '/reports/monthly-account-flows',
        query: {'year': '$_year', 'month': '$_month'},
      );
      final profileFuture = widget.apiClient.get('/profile');

      final monthResults = await Future.wait(monthFutures);
      final flowsResult = await flowsFuture;
      final profileResult = await profileFuture as Map<String, dynamic>;

      if (!mounted) return;

      final emailFallback = Supabase.instance.client.auth.currentUser?.email?.split('@').first ?? 'Usuario';
      final displayName = (profileResult['display_name'] as String?)?.trim();
      final resolvedName = (displayName != null && displayName.isNotEmpty) ? displayName : emailFallback;

      final bars = <_MonthCapsulePoint>[];
      Map<String, dynamic>? selectedMonthPyg;

      for (var i = 0; i < 12; i++) {
        final list = List<Map<String, dynamic>>.from(monthResults[i] as List);
        final pygRow = list.cast<Map<String, dynamic>?>().firstWhere(
              (row) => row?['currency_code'] == 'PYG',
              orElse: () => list.isNotEmpty ? list.first : null,
            );

        final incomeVal = double.tryParse((pygRow?['income_total'] ?? '0').toString()) ?? 0;
        final expenseVal = double.tryParse((pygRow?['net_expense_total'] ?? '0').toString()) ?? 0;

        bars.add(_MonthCapsulePoint(month: i + 1, income: incomeVal, expense: expenseVal));

        if (i + 1 == _month) {
          selectedMonthPyg = pygRow;
        }
      }

      final allFlows = List<Map<String, dynamic>>.from(flowsResult as List);
      final pygFlows = allFlows.where((f) => f['currency_code'] == 'PYG').toList();

      setState(() {
        _pygSummary = selectedMonthPyg;
        _yearBars = bars;
        _accountFlows = pygFlows.isNotEmpty ? pygFlows : allFlows;
        _userName = resolvedName;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectMonth(int month) {
    if (_month == month) return;
    setState(() => _month = month);
    _loadData();
  }

  void _selectYear(int year) {
    if (_year == year) return;
    setState(() => _year = year);
    _loadData();
  }

  String _fmtPyg(Object? value) {
    return CurrencyFormatter.format(
      amount: value ?? '0',
      symbol: 'Gs.',
      decimalPlaces: 0,
    );
  }

  String _greetingByHour() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Buen día';
    }
    if (hour >= 12 && hour < 19) {
      return 'Buenas tardes';
    }
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.extension<FinancialColors>()!;

    // Colores propios de MisRegistros (adaptados a tema claro y oscuro)
    final headerTint = theme.colorScheme.primary;
    final incomeBarColor = colors.income;
    final expenseBarColor = colors.expense;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Cabecera con banda superior de color + saludo horario + tarjeta de Balance
          Stack(
            children: [
              Container(
                height: 155,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            theme.colorScheme.primaryContainer,
                            theme.colorScheme.surface,
                          ]
                        : [
                            headerTint,
                            headerTint.withValues(alpha: 0.85),
                          ],
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _userName.isEmpty
                            ? _greetingByHour()
                            : '${_greetingByHour()}, $_userName',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? theme.colorScheme.onSurface : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _BalanceHeroCard(
                      summary: _pygSummary,
                      monthLabel: '${_monthLabels[_month - 1]} $_year',
                      accentYellow: incomeBarColor,
                      onAccentYellow: isDark ? const Color(0xFF0B0F19) : Colors.white,
                      deepTeal: expenseBarColor,
                      onDeepTeal: isDark ? const Color(0xFF0B0F19) : Colors.white,
                      colors: colors,
                      formatPyg: _fmtPyg,
                      showDetails: _showDetails,
                      onToggleDetails: () => setState(() => _showDetails = !_showDetails),
                      onPrevMonth: () {
                        final prev = DateTime(_year, _month - 1, 1);
                        setState(() {
                          _year = prev.year;
                          _month = prev.month;
                        });
                        _loadData();
                      },
                      onNextMonth: () {
                        final next = DateTime(_year, _month + 1, 1);
                        setState(() {
                          _year = next.year;
                          _month = next.month;
                        });
                        _loadData();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                          const SizedBox(height: 8),
                          OutlinedButton(onPressed: _loadData, child: const Text('Reintentar')),
                        ],
                      ),
                    ),
                  )
                else ...[
                  // Segunda tarjeta: gráfico anual de 12 barras cápsula (Ene - Dic)
                  _AnnualCapsulesCard(
                    year: _year,
                    selectedMonth: _month,
                    bars: _yearBars,
                    monthLabels: _monthLabels,
                    accentYellow: incomeBarColor,
                    deepTeal: expenseBarColor,
                    onSelectMonth: _selectMonth,
                    onSelectYear: _selectYear,
                    onOpenBreakdown: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AnnualBreakdownPage(
                            apiClient: widget.apiClient,
                            initialYear: _year,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Sección inferior: flujo por cuenta del mes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cuentas (${_monthLabels[_month - 1]})',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'PYG',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_accountFlows.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Todavía no tienes cuentas registradas.'),
                      ),
                    )
                  else
                    ..._accountFlows.map((flow) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      flow['account_name'] as String? ?? '',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          '↑ ${_fmtPyg(flow['inflows_total'])}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colors.income,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '↓ ${_fmtPyg(flow['outflows_total'])}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colors.expense,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _fmtPyg(flow['net_flow']),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceHeroCard extends StatelessWidget {
  const _BalanceHeroCard({
    required this.summary,
    required this.monthLabel,
    required this.accentYellow,
    required this.onAccentYellow,
    required this.deepTeal,
    required this.onDeepTeal,
    required this.colors,
    required this.formatPyg,
    required this.showDetails,
    required this.onToggleDetails,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  final Map<String, dynamic>? summary;
  final String monthLabel;
  final Color accentYellow;
  final Color onAccentYellow;
  final Color deepTeal;
  final Color onDeepTeal;
  final FinancialColors colors;
  final String Function(Object?) formatPyg;
  final bool showDetails;
  final VoidCallback onToggleDetails;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balanceRaw = (summary?['monthly_balance'] ?? '0').toString();
    final incomeRaw = (summary?['income_total'] ?? '0').toString();
    final expenseRaw = (summary?['net_expense_total'] ?? '0').toString();
    final isNegativeBalance = balanceRaw.startsWith('-');

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tu balance',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(Icons.chevron_left, size: 18),
                      onPressed: onPrevMonth,
                    ),
                    Text(
                      monthLabel,
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(Icons.chevron_right, size: 18),
                      onPressed: onNextMonth,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatPyg(balanceRaw),
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.5,
                  color: isNegativeBalance ? colors.expense : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Barra dividida Ingresos / Egreso estilo píldora bipartita
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        color: accentYellow,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ingresos',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: onAccentYellow.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                formatPyg(incomeRaw),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: onAccentYellow,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        color: deepTeal,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Egreso',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: onDeepTeal.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                formatPyg(expenseRaw),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: onDeepTeal,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onToggleDetails,
                icon: Icon(showDetails ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(showDetails ? 'Ocultar detalle' : 'Ver todo'),
              ),
            ),

            if (showDetails) ...[
              const Divider(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  _DetailItem(
                    label: 'Gastos brutos',
                    value: formatPyg(summary?['gross_expense_total']),
                    color: colors.expense,
                  ),
                  _DetailItem(
                    label: 'Devoluciones',
                    value: formatPyg(summary?['refund_total']),
                    color: colors.income,
                  ),
                  _DetailItem(
                    label: 'Transferencias',
                    value: formatPyg(summary?['transfer_total']),
                    color: colors.transfer,
                  ),
                  _DetailItem(
                    label: 'Ajustes (neto)',
                    value: formatPyg(summary?['adjustment_net_total']),
                    color: colors.warning,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnnualCapsulesCard extends StatelessWidget {
  const _AnnualCapsulesCard({
    required this.year,
    required this.selectedMonth,
    required this.bars,
    required this.monthLabels,
    required this.accentYellow,
    required this.deepTeal,
    required this.onSelectMonth,
    required this.onSelectYear,
    required this.onOpenBreakdown,
  });

  final int year;
  final int selectedMonth;
  final List<_MonthCapsulePoint> bars;
  final List<String> monthLabels;
  final Color accentYellow;
  final Color deepTeal;
  final void Function(int month) onSelectMonth;
  final void Function(int year) onSelectYear;
  final VoidCallback onOpenBreakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = [year - 2, year - 1, year, year + 1];
    final emptyBarColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7);

    var maxTotal = 0.0;
    for (final b in bars) {
      if (b.total > maxTotal) maxTotal = b.total;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Selector de año en píldora
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: year,
                      isDense: true,
                      items: years
                          .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                          .toList(),
                      onChanged: (y) {
                        if (y != null) onSelectYear(y);
                      },
                    ),
                  ),
                ),
                // Leyenda compacta Ingreso / Egreso + botón circular ver más (torta anual)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DotLabel(color: accentYellow, label: 'Ingreso'),
                    const SizedBox(width: 8),
                    _DotLabel(color: deepTeal, label: 'Egreso'),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Ver desglose anual por categoría',
                      visualDensity: VisualDensity.compact,
                      onPressed: onOpenBreakdown,
                      icon: const Icon(Icons.pie_chart_outline, size: 18),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 12 barras tipo cápsula (Ene - Dic)
            SizedBox(
              height: 145,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: bars.map((b) {
                  final isSelected = b.month == selectedMonth;
                  final hasData = b.total > 0 && maxTotal > 0;
                  final heightFactor = hasData ? (b.total / maxTotal).clamp(0.18, 1.0) : 1.0;

                  final incomeShare = hasData ? (b.income / b.total) : 0.5;
                  final incomeFlex = (incomeShare * 1000).round();
                  final expenseFlex = ((1 - incomeShare) * 1000).round();

                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onSelectMonth(b.month),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: heightFactor,
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: 10,
                                  decoration: BoxDecoration(
                                    color: emptyBarColor,
                                    borderRadius: BorderRadius.circular(10),
                                    border: isSelected
                                        ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                                        : null,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: hasData
                                      ? Column(
                                          children: [
                                            if (expenseFlex > 0)
                                              Expanded(
                                                flex: expenseFlex,
                                                child: Container(color: deepTeal),
                                              ),
                                            if (incomeFlex > 0)
                                              Expanded(
                                                flex: incomeFlex,
                                                child: Container(color: accentYellow),
                                              ),
                                          ],
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              monthLabels[b.month - 1],
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 10,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotLabel extends StatelessWidget {
  const _DotLabel({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 135,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
