# Configuración segura del cliente Flutter

El cliente recibe sólo el URL del proyecto Supabase y una clave publicable
`sb_publishable_`. La clave es identificador público del proyecto: los permisos
dependen de RLS y de la sesión del usuario. No poner en Flutter `sb_secret_`,
`service_role`, JWT de administrador ni `OPENAI_API_KEY`.

Configura cada build mediante valores locales/de CI; no los guardes en archivos
versionados:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

Para compilar una distribución, usa los mismos dos defines con
`flutter build ipa --release` después de configurar firma y perfil de Apple.
El archivo compilado incluirá la clave publicable; nunca incluyas claves de
servidor. Las funciones de OCR y análisis se invocan con la sesión Supabase del
usuario y aplican límites de uso en servidor.

La configuración se valida en `lib/app_config.dart`. Si falta alguno de los
dos valores o la clave no comienza por `sb_publishable_`, la app no inicia el
cliente de Supabase. No uses `lib/app_secrets.dart` ni la antigua clave OpenAI.

Las subidas nuevas usan `boletas/<UUID del usuario>/<UUID del archivo>.jpg`.
La política actual de producción rechaza las subidas a raíz que hace la app
Flutter antigua. El bucket todavía es público para lectura hasta desplegar una
versión compatible y migrar los registros y archivos históricos.

## Sesión móvil

En iOS y Android, las sesiones Supabase y los verificadores PKCE se guardan en
`flutter_secure_storage` (Keychain en iOS y almacenamiento Android cifrado).
Al primer inicio, la app copia las credenciales v2 existentes desde
`SharedPreferences`, verifica la copia segura y luego elimina la copia antigua.
Si no puede verificar la migración, el cliente falla al iniciar Auth en vez de
continuar escribiendo una sesión en texto claro. Android excluye el archivo de
Auth de respaldos y transferencias de dispositivo.

Web y escritorio conservan el almacenamiento predeterminado de Supabase; no
deben tratarse como almacenamiento seguro de una app móvil ni desplegarse con
un secreto de servidor. El bucket público también sigue siendo un bloqueo de
publicación hasta completar el cutover y conciliar las boletas históricas.
