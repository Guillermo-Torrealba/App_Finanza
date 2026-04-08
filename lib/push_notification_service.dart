import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;
  // Tu clave VAPID extraída de Firebase
  static const String _vapidKey = 'BN1qeX_GWXTO7BuQiApQoj8X0yolzcU2dsgZGMbtLe31muEFMH7bz6Xh_aEoYvv9egFz0F4EIDgzQtIlR9F_uaI'; 

  static Future<bool> tienePermiso() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return false; // Evitar crashes en Windows
    }
    try {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> solicitarPermiso(BuildContext context) async {
    try {
      // 1. Pedir permiso al usuario (esto mostrará el popup en iOS)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('Permiso de notificaciones concedido.');

        // 2. Traer el token conectando con Firebase
        String? token = await _messaging.getToken(vapidKey: _vapidKey);
        
        if (token != null) {
          debugPrint('Este es tu FCM Token: $token');
          await _guardarTokenEnSupabase(token);
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('¡Notificaciones activadas exitosamente!'), backgroundColor: Colors.green),
            );
          }
          return true;
        }
        return false;
      } else {
        debugPrint('Permiso denegado por el usuario.');
        if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No diste permiso para notificaciones.'), backgroundColor: Colors.red),
            );
          }
      }
      return false;
    } catch (e) {
      debugPrint('Error configurando notificaciones: $e');
      if (context.mounted) {
        String mensajeError = 'Error: No soportado en este dispositivo (Windows). PRUEBA EN WEB/IOS.';
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
          mensajeError = 'Las notificaciones push de Firebase no funcionan en la app nativa de Windows. Pruebalo en Web o Celular.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensajeError), 
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return false;
    }
  }

  static Future<void> _guardarTokenEnSupabase(String token) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    
    if (user != null) {
      try {
        // Guarda o actualiza el token para este usuario
        await supabase.from('usuarios_tokens').upsert({
          'user_id': user.id,
          'fcm_token': token,
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('¡Token guardado exitosamente en Supabase!');
      } catch (e) {
        debugPrint('Error guardando token en Supabase: $e');
      }
    }
  }
}
