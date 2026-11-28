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
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_moon_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Ñangareko',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<AppColorPalette>(
            tooltip: 'Elegir color',
            icon: const Icon(Icons.color_lens_rounded),
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
                          const Icon(Icons.check_rounded, size: 18),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          IconButton(
            tooltip: isDark ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro',
            icon: Icon(isDark ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded),
            onPressed: () => widget.themeController.toggleLightDark(context),
          ),
          IconButton(
            tooltip: 'Perfil y configuración',
            icon: const Icon(Icons.manage_accounts_rounded),
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
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights_rounded),
                  label: Text('Resumen'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.swap_vert_outlined),
                  selectedIcon: Icon(Icons.swap_vert_rounded),
                  label: Text('Movimientos'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: Text('Cuentas'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: Text('Categorías'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.manage_accounts_outlined),
                  selectedIcon: Icon(Icons.manage_accounts_rounded),
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
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights_rounded),
                  label: 'Resumen',
                ),
                NavigationDestination(
                  icon: Icon(Icons.swap_vert_outlined),
                  selectedIcon: Icon(Icons.swap_vert_rounded),
                  label: 'Movimientos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: 'Cuentas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Categorías',
                ),
              ],
            ),
    );
  }
}
