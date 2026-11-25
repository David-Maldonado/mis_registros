import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/theme_controller.dart';
import '../shell/app_shell.dart';
import 'auth_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.apiClient,
    required this.themeController,
  });

  final ApiClient apiClient;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session == null) {
          return AuthPage(themeController: themeController);
        }
        return AppShell(
          apiClient: apiClient,
          themeController: themeController,
        );
      },
    );
  }
}
