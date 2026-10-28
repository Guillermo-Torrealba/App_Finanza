# Política de privacidad — borrador de revisión

**App:** Mis Finanzas Cloud / App Finanzas  
**Última actualización:** 28 de octubre de 2026  
**Contacto:** gntorrealbam@gmail.com

> Este borrador describe el comportamiento revisado de los clientes iOS y los servicios conectados. No lo publiques ni envíes la app a App Store hasta completar la migración del almacenamiento de boletas, revisar las etiquetas de App Store Connect y confirmar el contacto y la URL pública.

## Datos que se utilizan

La cuenta puede tratar correo electrónico, nombre, teléfono e identificador de usuario. Las funciones financieras pueden tratar movimientos, montos, fechas, categorías, cuentas, saldos, últimos cuatro dígitos, presupuestos, metas, notas y nombres que agregues a gastos compartidos. Si activas notificaciones, se guarda un token técnico del dispositivo. Si escaneas boletas, la imagen y los campos extraídos pueden asociarse a tus movimientos.

Si configuras la integración bancaria opcional, Google Apps Script procesa los correos que coinciden con las etiquetas y remitentes configurados. Envía su contenido a una función del servidor para extraer datos. La aplicación conserva identificadores, remitente, asunto y datos financieros extraídos; para mensajes no clasificados puede guardar un extracto limitado con números largos ocultos.

## Uso de los datos y proveedores

Supabase proporciona autenticación, base de datos, almacenamiento y funciones de servidor. Firebase Cloud Messaging entrega notificaciones cuando las habilitas. Google procesa Gmail y Apps Script cuando activas esa integración.

Cuando solicitas una función de inteligencia artificial, la app envía a OpenAI a través de funciones autenticadas de Supabase los datos necesarios: texto que escribiste, categorías y cuentas disponibles, resúmenes financieros agregados o la imagen completa de una boleta, según la función. No se incluye la clave privada de OpenAI en el cliente.

En iOS compatible, el dictado solicita reconocimiento en el dispositivo. El audio no se envía a Apple ni a los servidores de la app; si el reconocimiento local no está disponible, el dictado falla. La transcripción queda en pantalla y solo se envía a la IA cuando confirmas la acción de análisis.

Los proveedores pueden procesar datos en las regiones necesarias para prestar sus servicios y conforme a sus propias condiciones y políticas. La app no vende datos financieros ni los usa para publicidad personalizada.

## Almacenamiento de boletas — bloqueo de publicación

El bucket de boletas de producción continúa público mientras se migran clientes y referencias antiguas. Una URL pública puede permitir leer su imagen aunque la persona no haya iniciado sesión. La app está preparada para firmar rutas nuevas de propietario, pero el cutover privado, la conciliación de objetos antiguos y la prueba de CSV todavía están pendientes. **No publiques este borrador ni una versión de la app antes de cerrar ese gate.**

## Conservación y eliminación

Los registros activos se conservan mientras la cuenta esté en uso. Puedes iniciar la eliminación desde **Ajustes → Datos y mantenimiento → Eliminar cuenta**. La app llama a una función autenticada y solo cierra la sesión cuando el servidor confirma la eliminación. La función borra registros de la cuenta y las boletas owner-prefixed con referencias verificables. Los objetos antiguos sin propiedad verificable pueden permanecer hasta que se concilie su origen. Los respaldos y registros técnicos de proveedores siguen sus ciclos de conservación.

Para consultas de privacidad, solicitudes de acceso o corrección, o para informar un problema, escribe a **gntorrealbam@gmail.com**.

## Seguridad

La aplicación usa autenticación, controles de acceso por cuenta y funciones de servidor para las operaciones sensibles. Ningún sistema conectado a internet puede garantizar seguridad absoluta. Esta política y las declaraciones de privacidad de App Store deben actualizarse si cambian los datos, proveedores o funciones.
