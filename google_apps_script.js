/**
 * Google Apps Script - Integración Banco BICE / BCI -> Mis Finanzas App
 * 
 * INSTRUCCIONES:
 * 1. Ve a https://script.google.com y crea un nuevo proyecto.
 * 2. Pega todo este código reemplazando lo que haya.
 * 3. Reemplaza WEBHOOK_TOKEN con tu Token Secreto (el rojo de la app).
 * 4. Guarda y ejecuta la función "procesarCorreosBancarios" una vez manualmente
 *    para que Google te pida permisos de Gmail.
 * 5. Ve al menú "Activadores" (icono de reloj) y crea uno:
 *    - Función: procesarCorreosBancarios
 *    - Evento: Basado en tiempo
 *    - Intervalo: Cada 1 minuto (o cada 5 minutos)
 * 6. ¡Listo! Cada vez que llegue un correo de transferencia, se registrará
 *    automáticamente en tu app como "A revisar".
 */

function procesarCorreosBancarios() {
  // ══════════════════════════════════════════════════════════════
  // CONFIGURACIÓN — Reemplaza ESTE_ES_TU_TOKEN por tu Token Secreto
  // ══════════════════════════════════════════════════════════════
  var WEBHOOK_TOKEN = "ESTE_ES_TU_TOKEN"; 
  var WEBHOOK_URL   = "https://xycshsxqcfypgffnqmxb.supabase.co/rest/v1/rpc/registrar_gasto_webhook";
  var SUPABASE_ANON_KEY = "sb_publishable_RoIT8jS3qG_VYtX1t--h8A_vqlTyk3_";

  // Buscar correos no leídos de transferencias bancarias
  var query = 'is:unread ('
    + 'subject:"Hicimos la transferencia" '
    + 'OR subject:"Recibiste una transferencia" '
    + 'OR subject:"Has recibido una transferencia"'
    + ')';

  var threads = GmailApp.search(query, 0, 10);
  if (threads.length === 0) return;

  for (var i = 0; i < threads.length; i++) {
    var messages = threads[i].getMessages();
    for (var j = 0; j < messages.length; j++) {
      var msg = messages[j];
      if (!msg.isUnread()) continue;
      
      var subject = msg.getSubject();
      var body    = msg.getPlainBody();
      
      var montoStr = null;
      var comercio = "Desconocido";
      var tipo     = "Gasto";
      
      // ── CASO 1: TRANSFERENCIA ENVIADA (BICE) → Gasto ──
      if (subject.indexOf("Hicimos la transferencia") !== -1) {
        tipo = "Gasto";
        var m1 = body.match(/Monto[\s\r\n]*\$\s*([\d.,]+)/i);
        if (m1) montoStr = m1[1];
        
        var c1 = body.match(/Cuenta de destino[\s\S]*?Nombre[\s\r\n]+([^\r\n]+)/i);
        if (c1) comercio = "Transferencia a " + c1[1].trim();

      // ── CASO 2: TRANSFERENCIA RECIBIDA (BICE) → Ingreso ──
      } else if (subject.indexOf("Recibiste una transferencia") !== -1) {
        tipo = "Ingreso";
        var m2 = body.match(/Monto[\s\r\n]*\$\s*([\d.,]+)/i);
        if (m2) montoStr = m2[1];
        
        var c2 = body.match(/Cuenta de origen[\s\S]*?Nombre[\s\r\n]+([^\r\n]+)/i);
        if (c2) comercio = "Transferencia de " + c2[1].trim();
        
      // ── CASO 3: TRANSFERENCIA RECIBIDA (BCI u otros → BICE) → Ingreso ──
      } else if (subject.indexOf("Has recibido una transferencia") !== -1) {
        tipo = "Ingreso";
        var m3 = body.match(/Monto transferido:\s*\$\s*([\d.,]+)/i);
        if (m3) montoStr = m3[1];
        
        var c3 = body.match(/(?:Raz[oó]n social|Nombre):\s*([^\r\n]+)/i);
        if (c3) comercio = "Transferencia de " + c3[1].trim();
      }
      
      // Si logramos extraer el monto, enviamos al webhook
      if (montoStr) {
        var montoLimpio = montoStr.replace(/[^0-9]/g, '');
        var montoInt    = parseInt(montoLimpio, 10);
        
        var payload = {
          "p_token":    WEBHOOK_TOKEN,
          "p_monto":    montoInt,
          "p_comercio": comercio,
          "p_tipo":     tipo
        };
        
        var options = {
          "method":      "post",
          "contentType": "application/json",
          "headers":     { "apikey": SUPABASE_ANON_KEY },
          "payload":     JSON.stringify(payload),
          "muteHttpExceptions": true
        };
        
        try {
          var response = UrlFetchApp.fetch(WEBHOOK_URL, options);
          if (response.getResponseCode() >= 200 && response.getResponseCode() < 300) {
            msg.markRead(); // Lo marcamos como leído para no re-procesarlo
            Logger.log("✅ " + tipo + " registrado: $" + montoLimpio + " — " + comercio);
          } else {
            Logger.log("❌ Error HTTP " + response.getResponseCode() + ": " + response.getContentText());
          }
        } catch (e) {
          Logger.log("❌ Excepción: " + e.toString());
        }
      } else {
        Logger.log("⚠️ No se pudo extraer monto del correo: " + subject);
      }
    }
  }
}
