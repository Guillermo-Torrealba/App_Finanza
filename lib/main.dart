import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'app_settings.dart';
import 'login_screen.dart';
import 'pantalla_principal.dart';
import 'onboarding_screen.dart';
import 'push_notification_service.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializamos Firebase con la configuración generada
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://xycshsxqcfypgffnqmxb.supabase.co',
    anonKey: 'sb_publishable_RoIT8jS3qG_VYtX1t--h8A_vqlTyk3_',
  );

  // Inicializamos los listeners de notificaciones push
  await PushNotificationService.init();

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
          builder: (context, child) {
            return ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
              ),
              child: child!,
            );
          },
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: seedColor,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              },
            ),
            scaffoldBackgroundColor: const Color(0xFFF8F9FA), // Off-white clean
            textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
            visualDensity: settings.compactMode
                ? VisualDensity.compact
                : VisualDensity.standard,
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              color: Colors.white,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: seedColor, width: 2),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: seedColor,
            scaffoldBackgroundColor: const Color(0xFF0F172A), // Midnight blue
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
            cardColor: const Color(0xFF1E293B), // Slate softer dark
            cardTheme: const CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
                side: BorderSide(color: Color(0xFF334155)),
              ),
              color: Color(0xFF1E293B),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: seedColor, width: 2),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
              ),
            ),
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
