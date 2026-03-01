import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../pantalla_principal.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.settingsController});

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return PantallaPrincipal(settingsController: settingsController);
  }
}
