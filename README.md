# app_finanzas

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Configuración segura

La app requiere `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` en tiempo de
compilación. Usa una clave `sb_publishable_`; nunca agregues claves `sb_secret_`,
`service_role` ni `OPENAI_API_KEY` al cliente. Revisa
[`docs/SECURE_CLIENT_CONFIGURATION.md`](docs/SECURE_CLIENT_CONFIGURATION.md)
para los comandos y el estado de compatibilidad de boletas.
