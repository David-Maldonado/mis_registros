import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/currency_formatter.dart';

class AnnualBreakdownPage extends StatefulWidget {
  const AnnualBreakdownPage({
    super.key,
    required this.apiClient,
    required this.initialYear,
    this.initialMonth,
  });

  final ApiClient apiClient;
  final int initialYear;
  final int? initialMonth;

  @override
  State<AnnualBreakdownPage> createState() => _AnnualBreakdownPageState();
}

class _AnnualBreakdownPageState extends State<AnnualBreakdownPage> {
  static const _monthNames = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  static const _palette = [
    Color(0xFF0F766E),
    Color(0xFF2563EB),
    Color(0xFFD97706),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFDB2777),
    Color(0xFF0284C7),
    Color(0xFFEA580C),
    Color(0xFF4F46E5),
  ];

  late int _year;
  int? _month;
  String _selectedType = 'expense';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    _month = widget.initialMonth;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final endpoint = _month == null
          ? '/reports/annual-category-breakdown'
          : '/reports/monthly-category-breakdown';
      final query = <String, String>{
        'year': '$_year',
        if (_month != null) 'month': '$_month',
        'type': _selectedType,
        'currency_code': 'PYG',
      };

      final data = await widget.apiClient.get(endpoint, query: query);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data as List);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AppFeedback.formatError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtPyg(Object? value) {
    return CurrencyFormatter.format(
      amount: value ?? '0',
      symbol: 'Gs.',
      decimalPlaces: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = [_year - 2, _year - 1, _year, _year + 1];

    var totalAmount = 0.0;
    for (final row in _rows) {
      totalAmount += double.tryParse((row['total_amount'] ?? '0').toString()) ?? 0;
    }

    final periodTitle = _month == null
        ? 'Enero - Diciembre $_year'
        : '${_monthNames[_month! - 1]} $_year';
    final emptyPeriodText = _month == null
        ? 'de enero a diciembre de $_year'
        : 'en ${_monthNames[_month! - 1].toLowerCase()} de $_year';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _month == null
              ? 'Desglose anual por categoría'
              : 'Desglose de ${_monthNames[_month! - 1]}',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Egresos')),
                    ButtonSegment(value: 'income', label: Text('Ingresos')),
                  ],
                  selected: {_selectedType},
                  onSelectionChanged: (s) {
                    setState(() => _selectedType = s.first);
                    _loadData();
                  },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _month,
                          isDense: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Todo el año'),
                            ),
                            ...List.generate(
                              12,
                              (i) => DropdownMenuItem<int?>(
                                value: i + 1,
                                child: Text(_monthNames[i]),
                              ),
                            ),
                          ],
                          onChanged: (m) {
                            setState(() => _month = m);
                            _loadData();
                          },
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _year,
                          isDense: true,
                          items: years
                              .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                              .toList(),
                          onChanged: (y) {
                            if (y == null) return;
                            setState(() => _year = y);
                            _loadData();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
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
            else if (_rows.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No hay ${_selectedType == 'income' ? 'ingresos' : 'egresos'} registrados $emptyPeriodText.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        periodTitle,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 220,
                        width: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(220, 220),
                              painter: _PieChartPainter(
                                values: _rows
                                    .map((r) => double.tryParse((r['total_amount'] ?? '0').toString()) ?? 0)
                                    .toList(),
                                colors: List.generate(
                                  _rows.length,
                                  (i) => _palette[i % _palette.length],
                                ),
                                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedType == 'income' ? 'Total ingresos' : 'Total egresos',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _fmtPyg(totalAmount.round()),
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Categorías',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...List.generate(_rows.length, (index) {
                final row = _rows[index];
                final color = _palette[index % _palette.length];
                final pct = (row['percentage'] ?? 0).toString().replaceAll('.', ',');

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(
                      row['category_name'] as String? ?? 'Sin categoría',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _fmtPyg(row['total_amount']),
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
    );
  }
}

class _PieChartPainter extends CustomPainter {
  _PieChartPainter({
    required this.values,
    required this.colors,
    required this.backgroundColor,
  });

  final List<double> values;
  final List<Color> colors;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, v) => sum + v);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    const strokeWidth = 28.0;

    if (total <= 0) {
      final paint = Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius, paint);
      return;
    }

    var startAngle = -math.pi / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * (2 * math.pi);
      if (sweep <= 0) continue;

      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}
