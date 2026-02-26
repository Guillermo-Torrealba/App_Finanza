import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';
import 'login_screen.dart';
import 'pantalla_principal.dart';
import 'onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://xycshsxqcfypgffnqmxb.supabase.co',
    anonKey: 'sb_publishable_RoIT8jS3qG_VYtX1t--h8A_vqlTyk3_',
  );

  final preferences = await SharedPreferences.getInstance();
  final settingsController = SettingsController(preferences: preferences);
  await settingsController.init();

  runApp(AppFinanzas(settingsController: settingsController));
}

class AppFinanzas extends StatelessWidget {
  const AppFinanzas({super.key, required this.settingsController});

  final SettingsController settingsController;

  ThemeMode _themeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        final settings = settingsController.settings;
        final seedColor = Color(settings.seedColorValue);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode(settings.themeMode),
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: seedColor,
            visualDensity: settings.compactMode
                ? VisualDensity.compact
                : VisualDensity.standard,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: seedColor,
            cardColor: const Color(
              0xFF1E1E1E,
            ), // Slightly lighter than background
            visualDensity: settings.compactMode
                ? VisualDensity.compact
                : VisualDensity.standard,
          ),
          home: supabase.auth.currentSession == null
              ? LoginScreen(settingsController: settingsController)
              : settings.hasCompletedOnboarding
              ? PantallaPrincipal(settingsController: settingsController)
              : OnboardingScreen(settingsController: settingsController),
        );
      },
    );
  }
}
