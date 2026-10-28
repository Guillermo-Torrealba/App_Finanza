import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { JWT } from "npm:google-auth-library@9.0.0"

const FIREBASE_PROJECT_ID = "appfinanzas-3a1ca"
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

type WebhookPayload = {
  type?: unknown
  table?: unknown
  schema?: unknown
  timestamp?: unknown
  signature?: unknown
  record?: { id?: unknown; user_id?: unknown }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  })
}

function serviceKey(): string {
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS")
  if (keys) {
    try {
      const parsed = JSON.parse(keys) as Record<string, unknown>
      if (typeof parsed.default === "string" && parsed.default.startsWith("sb_secret_")) return parsed.default
    } catch {
      // Fail closed below if the reserved environment secret is malformed.
    }
  }
  throw new Error("missing server API key")
}

function normalizeID(value: unknown): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null
  const id = String(value)
  return /^[1-9][0-9]*$/.test(id) ? id : null
}

async function verifyHMAC(payload: WebhookPayload): Promise<boolean> {
  const id = normalizeID(payload.record?.id)
  const userID = payload.record?.user_id
  const timestamp = typeof payload.timestamp === "number" ? payload.timestamp : Number(payload.timestamp)
  const signature = payload.signature

  if (
    !id ||
    typeof userID !== "string" ||
    !UUID_PATTERN.test(userID) ||
    !Number.isSafeInteger(timestamp) ||
    typeof signature !== "string" ||
    !/^[0-9a-f]{64}$/.test(signature)
  ) return false

  const url = Deno.env.get("SUPABASE_URL")
  if (!url) return false

  try {
    // The validator is server-only. Never expose it as an anon RPC oracle.
    const client = createClient(url, serviceKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data, error } = await client.rpc("validate_alerta_pago_webhook", {
      p_timestamp: timestamp,
      p_gasto_id: id,
      p_user_id: userID,
      p_signature: signature,
    })
    return !error && data === true
  } catch {
    return false
  }
}

export function serveNotifications(): void {
  serve(async (req) => {
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405)

    let payload: WebhookPayload
    try {
      payload = await req.json()
    } catch {
      return json({ error: "invalid_request" }, 400)
    }

    if (
      payload.type !== "INSERT" ||
      payload.table !== "gastos" ||
      payload.schema !== "public" ||
      !payload.record
    ) return json({ error: "invalid_request" }, 400)

    const signed = await verifyHMAC(payload)
    if (!signed) return json({ error: "unauthorized" }, 401)

    const id = normalizeID(payload.record.id)
    const userID = payload.record.user_id
    if (!id || typeof userID !== "string" || !UUID_PATTERN.test(userID)) {
      return json({ error: "invalid_request" }, 400)
    }

    try {
      const url = Deno.env.get("SUPABASE_URL")
      if (!url) return json({ error: "service_unavailable" }, 503)
      const admin = createClient(url, serviceKey(), {
        auth: { persistSession: false, autoRefreshToken: false },
      })

      const { data: expense, error: expenseError } = await admin
        .from("gastos")
        .select("monto,item")
        .eq("id", id)
        .eq("user_id", userID)
        .maybeSingle()

      if (expenseError || !expense) return json({ error: "service_unavailable" }, 503)

      const { data: userData, error: tokenError } = await admin
        .from("usuarios_tokens")
        .select("fcm_token")
        .eq("user_id", userID)
        .maybeSingle()

      if (tokenError) return json({ error: "service_unavailable" }, 503)
      if (!userData?.fcm_token) return json({ success: true, delivered: false }, 202)

      const serviceAccountValue = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")
      if (!serviceAccountValue) return json({ error: "service_unavailable" }, 503)

      const serviceAccount = JSON.parse(serviceAccountValue)
      const jwtClient = new JWT({
        email: serviceAccount.client_email,
        key: serviceAccount.private_key,
        scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
      })
      const accessToken = (await jwtClient.authorize()).access_token
      if (!accessToken) return json({ error: "service_unavailable" }, 503)

      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            message: {
              token: userData.fcm_token,
              notification: {
                title: "¡Pago Registrado! 💸",
                body: `Registramos exitosamente tu pago de $${expense.monto} en ${expense.item || "un comercio"}.`,
              },
              apns: { payload: { aps: { sound: "default", badge: 1 } } },
            },
          }),
          signal: AbortSignal.timeout(10_000),
        },
      )

      if (!response.ok) {
        console.error("payment_notification_delivery_failed", response.status)
        return json({ error: "delivery_failed" }, 502)
      }
      return json({ success: true })
    } catch {
      console.error("payment_notification_handler_failed")
      return json({ error: "service_unavailable" }, 503)
    }
  })
}
