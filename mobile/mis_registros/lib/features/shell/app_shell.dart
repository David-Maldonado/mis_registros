import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/state/ledger_refresh_notifier.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../accounts/accounts_page.dart';
import '../categories/categories_page.dart';
import '../profile/profile_page.dart';
import '../summary/summary_page.dart';
import '../transactions/transactions_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.apiClient,
    required this.themeController,
  });

  final ApiClient apiClient;
  final ThemeController themeController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _refreshNotifier = LedgerRefreshNotifier();
  int _selectedIndex = 0;

  @override
  void dispose() {
    _refreshNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 840;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pages = [
      SummaryPage(apiClient: widget.apiClient, refreshNotifier: _refreshNotifier),
      TransactionsPage(apiClient: widget.apiClient, refreshNotifier: _refreshNotifier),
      AccountsPage(apiClient: widget.apiClient, refreshNotifier: _refreshNotifier),
      CategoriesPage(apiClient: widget.apiClient, refreshNotifier: _refreshNotifier),
      ProfilePage(
        apiClient: widget.apiClient,
        themeController: widget.themeController,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('MisRegistros'),
        actions: [
          PopupMenuButton<AppColorPalette>(
            tooltip: 'Elegir color',
            icon: const Icon(Icons.palette_outlined),
            initialValue: widget.themeController.palette,
            onSelected: widget.themeController.setPalette,
            itemBuilder: (context) => AppColorPalette.values
                .map(
                  (p) => PopupMenuItem<AppColorPalette>(
                    value: p,
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: p.seedColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(p.label)),
                        if (p == widget.themeController.palette)
                          const Icon(Icons.check, size: 18),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          IconButton(
            tooltip: isDark ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro',
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => widget.themeController.toggleLightDark(context),
          ),
          IconButton(
            tooltip: 'Perfil y configuración',
            icon: const Icon(Icons.person_outline),
            onPressed: () => setState(() => _selectedIndex = 4),
          ),
        ],
      ),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.pie_chart_outline),
                  selectedIcon: Icon(Icons.pie_chart),
                  label: Text('Resumen'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: Text('Movimientos'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: Text('Cuentas'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.category_outlined),
                  selectedIcon: Icon(Icons.category),
                  label: Text('Categorías'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('Perfil'),
                ),
              ],
            ),
          if (isWide) const VerticalDivider(width: 1),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: pages[_selectedIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex < 4 ? _selectedIndex : 0,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.pie_chart_outline),
                  selectedIcon: Icon(Icons.pie_chart),
                  label: 'Resumen',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Movimientos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: 'Cuentas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.category_outlined),
                  selectedIcon: Icon(Icons.category),
                  label: 'Categorías',
                ),
              ],
            ),
    );
  }
}
