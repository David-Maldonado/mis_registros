import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController();
  await themeController.loadSavedPreferences();

  if (!AppConfig.isConfigured) {
    runApp(MisRegistrosConfigErrorApp(themeController: themeController));
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  final apiClient = ApiClient();

  runApp(
    MisRegistrosApp(
      apiClient: apiClient,
      themeController: themeController,
    ),
  );
}

class MisRegistrosApp extends StatelessWidget {
  const MisRegistrosApp({
    super.key,
    required this.apiClient,
    required this.themeController,
  });

  final ApiClient apiClient;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'MisRegistros',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(themeController.palette),
          darkTheme: AppTheme.dark(themeController.palette),
          themeMode: themeController.themeMode,
          home: AuthGate(
            apiClient: apiClient,
            themeController: themeController,
          ),
        );
      },
    );
  }
}

class MisRegistrosConfigErrorApp extends StatelessWidget {
  const MisRegistrosConfigErrorApp({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MisRegistros',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeController.themeMode,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Falta configurar SUPABASE_URL y SUPABASE_ANON_KEY.\n'
              'Ejecuta Flutter con --dart-define-from-file=.env.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
