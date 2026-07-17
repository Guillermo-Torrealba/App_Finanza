import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'app_settings.dart';
import 'app_secrets.dart';
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
    url: AppSecrets.supabaseUrl,
    anonKey: AppSecrets.supabaseAnonKey,
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


  @override
  Widget build(BuildContext context) {
    // ── Design tokens — Tech Minimal Dark ──
    const Color kBg          = Color(0xFF0A0A0A); // Scaffold background
    const Color kSurface      = Color(0xFF141414); // Cards, bottom bar
    const Color kSurfaceAlt   = Color(0xFF1C1C1C); // Inputs, alt cards
    const Color kBorder       = Color(0xFF2A2A2A); // 1px separators
    const Color kAccent       = Color(0xFF00E5A0); // Mint green — positive
    const Color kTextPrimary  = Color(0xFFF5F5F5); // Titles, big numbers
    const Color kTextSecondary = Color(0xFF888888); // Labels, subtitles

    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, _) {
        final settings = settingsController.settings;
        final seedColor = Color(settings.seedColorValue);

        // ── Dark ThemeData (forced) ──
        final darkTheme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: kAccent,
          scaffoldBackgroundColor: kBg,
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
            bodyColor: kTextPrimary,
            displayColor: kTextPrimary,
          ),
          // Cards
          cardColor: kSurface,
          cardTheme: CardThemeData(
            elevation: 0,
            color: kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: kBorder),
            ),
          ),
          // Inputs
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: kSurfaceAlt,
            hintStyle: const TextStyle(color: kTextSecondary, fontSize: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kAccent, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          // Elevated buttons
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: kAccent,
              foregroundColor: Colors.black,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 24,
              ),
            ),
          ),
          // Filled buttons
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.black,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // FAB
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: kAccent,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: CircleBorder(),
          ),
          // BottomAppBar
          bottomAppBarTheme: const BottomAppBarThemeData(
            color: kSurface,
            elevation: 0,
            shape: CircularNotchedRectangle(),
          ),
          // AppBar
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: TextStyle(
              color: kTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
            iconTheme: IconThemeData(color: kTextPrimary),
          ),
          // Dividers
          dividerTheme: const DividerThemeData(
            color: kBorder,
            thickness: 1,
            space: 1,
          ),
          // Chips
          chipTheme: ChipThemeData(
            backgroundColor: kSurfaceAlt,
            selectedColor: const Color(0xFF1A3A2E),
            side: const BorderSide(color: kBorder),
            labelStyle: const TextStyle(color: kTextPrimary, fontSize: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          // Segmented buttons
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const Color(0xFF1A3A2E);
                }
                return kSurfaceAlt;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return kAccent;
                return kTextSecondary;
              }),
              side: WidgetStatePropertyAll(
                BorderSide(color: kBorder),
              ),
            ),
          ),
          // Icon
          iconTheme: const IconThemeData(color: kTextPrimary),
          // Snackbar
          snackBarTheme: SnackBarThemeData(
            backgroundColor: kSurface,
            contentTextStyle: const TextStyle(color: kTextPrimary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: kBorder),
            ),
            behavior: SnackBarBehavior.floating,
          ),
          // Dialog
          dialogTheme: DialogThemeData(
            backgroundColor: kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: kBorder),
            ),
            titleTextStyle: const TextStyle(
              color: kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            contentTextStyle: TextStyle(
              color: kTextSecondary,
              fontSize: 14,
            ),
          ),
          // BottomSheet
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
          ),
          // PopupMenu
          popupMenuTheme: PopupMenuThemeData(
            color: kSurfaceAlt,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kBorder),
            ),
          ),
          visualDensity: settings.compactMode
              ? VisualDensity.compact
              : VisualDensity.standard,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            },
          ),
        );

        // ── Light ThemeData (kept as fallback) ──
        final lightTheme = ThemeData(
          useMaterial3: true,
          colorSchemeSeed: seedColor,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            },
          ),
          scaffoldBackgroundColor: const Color(0xFFF8F9FA),
          textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
          visualDensity: settings.compactMode
              ? VisualDensity.compact
              : VisualDensity.standard,
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            color: Colors.white,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: seedColor, width: 2),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 24,
              ),
            ),
          ),
        );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          // ── Modo oscuro forzado ──
          themeMode: ThemeMode.dark,
          theme: lightTheme,
          darkTheme: darkTheme,
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
