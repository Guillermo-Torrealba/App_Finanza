// @ts-ignore
import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4"
// @ts-ignore
import { JWT } from 'npm:google-auth-library@9.0.0'

const FIREBASE_PROJECT_ID = 'appfinanzas-3a1ca'

serve(async (req: any) => {
  try {
    // 1. Obtener el payload que envía el Webhook al hacer un INSERT
    const payload = await req.json()
    console.log("Webhook Payload:", JSON.stringify(payload))
    
    // Asumiendo que se disparó por un INSERT
    const transaccion = payload.record
    if (!transaccion) {
       return new Response("No es un payload de Webhook válido", { status: 400 })
    }

    const userId = transaccion.user_id
    const monto = transaccion.monto || transaccion.amount || 0
    // Adaptar esto al nombre exacto de tu columna (comercio, detalle, nombre, etc)
    const comercio = transaccion.comercio || transaccion.detalle || 'un comercio' 

    if (!userId) {
       return new Response("La transacción no tiene user_id", { status: 400 })
    }

    // 2. Conectar a Supabase como Administrador (Service Role) para leer el token
    const supabaseClient = createClient(
      // @ts-ignore
      Deno.env.get('SUPABASE_URL') ?? '',
      // @ts-ignore
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Consultamos la tabla donde guardaste el token desde Flutter
    const { data: userData, error: dbError } = await supabaseClient
      .from('usuarios_tokens')
      .select('fcm_token')
      .eq('user_id', userId)
      .single()

    if (dbError || !userData?.fcm_token) {
      console.error(`No se encontró token para el usuario ${userId}`, dbError)
      return new Response("El usuario no tiene token guardado", { status: 200 })
    }

    const fcm_token = userData.fcm_token

    // 3. Autenticación con Google (Firebase)
    // @ts-ignore
    const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!serviceAccountStr) throw new Error('No se encontró FIREBASE_SERVICE_ACCOUNT en Secrets')
    
    const serviceAccount = JSON.parse(serviceAccountStr)
    const jwtClient = new JWT({
      email: serviceAccount.client_email,
      key: serviceAccount.private_key,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })
    
    const tokens = await jwtClient.authorize()
    const accessToken = tokens.access_token

    // 4. Armar el mensaje para iPhone
    const fcmMessage = {
      message: {
        token: fcm_token,
        notification: {
          title: "¡Pago Registrado! 💸",
          body: `Registramos exitosamente tu pago de \$${monto} en ${comercio}.`,
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1
            }
          }
        }
      }
    }

    // 5. Enviar la notificación a Firebase
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify(fcmMessage),
      }
    )

    const fcmData = await fcmRes.json()
    console.log("FCM Response:", fcmData)

    return new Response(JSON.stringify({ success: true, response: fcmData }), {
      headers: { "Content-Type": "application/json" },
    })
  } catch (error: any) {
    console.error("Error general:", error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    })
  }
})
