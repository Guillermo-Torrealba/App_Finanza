import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Política de privacidad')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Text(
            'Mis Finanzas Cloud — versión de revisión, 28 de octubre de 2026',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          Text(
            'Esta pantalla describe el comportamiento actual de la app y sus servicios conectados. Antes de publicar, el responsable debe completar y publicar una URL externa de privacidad, sus datos de contacto y las etiquetas de privacidad de App Store Connect.',
          ),
          _PolicySection(
            title: 'Datos que utiliza la app',
            body:
                'La cuenta puede incluir correo electrónico, nombre y teléfono. La app procesa identificadores de cuenta, movimientos, montos, categorías, cuentas, presupuestos, metas, notas, pagos compartidos, los últimos cuatro dígitos que agregues y preferencias. Si activas notificaciones, guarda el token del dispositivo. Si escaneas una boleta, la imagen y los campos extraídos pueden quedar asociados a tus movimientos.',
          ),
          _PolicySection(
            title: 'Funciones de inteligencia artificial',
            body:
                'Cuando eliges una función de IA, la app puede enviar a Supabase y OpenAI el texto que escribiste, categorías y cuentas disponibles, campos de movimientos (fecha, concepto, monto y categoría), un resumen financiero agregado o la imagen completa de una boleta, según la función. El análisis de voz en iOS solicita reconocimiento local; la transcripción queda en la pantalla y no se envía a la IA hasta que pulses el botón de análisis. Si iOS no permite reconocimiento local, el dictado falla y puedes escribir el texto.',
          ),
          _PolicySection(
            title: 'Proveedores',
            body:
                'Supabase presta autenticación, base de datos, almacenamiento y funciones de servidor. OpenAI procesa las solicitudes de IA que inicias. Si usas el bot financiero de WhatsApp, Meta procesa los mensajes y audios que envías; el bot consulta los movimientos asociados a tu teléfono y puede enviar a OpenAI la pregunta y campos mínimos de movimientos para responder. Firebase Cloud Messaging entrega notificaciones si las habilitas. Cada proveedor puede procesar datos para prestar su servicio conforme a sus condiciones y políticas.',
          ),
          _PolicySection(
            title: 'Almacenamiento de boletas: pendiente de cierre',
            body:
                'El bucket de boletas de producción aún mantiene compatibilidad pública mientras se migran los clientes y referencias antiguas. Una URL pública puede permitir leer su archivo. Esta configuración no cumple el objetivo de almacenamiento privado; no publiques la app hasta completar y comprobar el cambio a acceso privado y la migración de boletas antiguas.',
          ),
          _PolicySection(
            title: 'Retención y eliminación',
            body:
                'Puedes solicitar la eliminación desde Ajustes > Datos y mantenimiento > Eliminar cuenta. La solicitud usa una función autenticada del servidor; la app solo cierra la sesión cuando el servidor confirma el borrado. Los archivos antiguos sin referencia atribuible a una cuenta pueden requerir una revisión adicional antes de eliminarse.',
          ),
          _PolicySection(
            title: 'Contacto y publicación',
            body:
                'Para consultas de privacidad o soporte: gntorrealbam@gmail.com. La URL pública de esta política aún debe publicarse y agregarse a App Store Connect antes del envío.',
          ),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    );
  }
}
