import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
};

/**
 * Computes SHA-256 hash of a string for deduplication / payload hashing
 */
async function computeSha256(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Validates Meta x-hub-signature-256 HMAC-SHA256 signature
 */
async function verifyMetaSignature(
  rawBody: string,
  signatureHeader: string,
  appSecret: string
): Promise<boolean> {
  try {
    const signature = signatureHeader.replace(/^sha256=/, "");
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(appSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );
    const hmacBuffer = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
    const expectedSignature = Array.from(new Uint8Array(hmacBuffer))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    return signature === expectedSignature;
  } catch (err) {
    console.error("Signature verification error:", err);
    return false;
  }
}

/**
 * Resolves the verification token from Deno environment, platform_settings, or secure secrets store
 */
async function getVerifyToken(supabaseClient: any): Promise<string | null> {
  const envToken = Deno.env.get("WHATSAPP_VERIFY_TOKEN");
  if (envToken && envToken.trim().length > 0) {
    return envToken.trim();
  }

  // 1. Check platform_settings (managed directly via GymOS Admin Web Portal)
  try {
    const { data: ps } = await supabaseClient
      .from("platform_settings")
      .select("value")
      .eq("key", "meta_whatsapp_config")
      .maybeSingle();

    if (ps?.value?.verify_token) {
      return (ps.value.verify_token as string).trim();
    }
  } catch (err) {
    console.error("Failed to query verify token from platform_settings:", err);
  }

  // 2. Resilient fallback to isolated whatsapp_system_secrets table
  try {
    const { data } = await supabaseClient
      .from("whatsapp_system_secrets")
      .select("secret_value")
      .eq("secret_name", "WHATSAPP_VERIFY_TOKEN")
      .maybeSingle();

    if (data?.secret_value) {
      return data.secret_value.trim();
    }
  } catch (err) {
    console.error("Failed to query fallback verify token:", err);
  }

  return null;
}

serve(async (req: Request) => {
  const correlationId = crypto.randomUUID();

  // 1. CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "content-type, authorization, x-hub-signature-256",
        ...SECURITY_HEADERS,
      },
    });
  }

  // Initialize Supabase Service Role client for isolated server-side operations
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // 2. GET Request: Meta Webhook Verification Handshake
  if (req.method === "GET") {
    const url = new URL(req.url);
    const mode = url.searchParams.get("hub.mode");
    const verifyTokenParam = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");

    console.log(`[${correlationId}] GET webhook verification attempt. Mode: ${mode}`);

    const expectedVerifyToken = await getVerifyToken(supabase);

    if (!expectedVerifyToken) {
      console.error(`[${correlationId}] WHATSAPP_VERIFY_TOKEN is not configured.`);
      return new Response(
        JSON.stringify({ error: "Verification token not configured on server" }),
        { status: 500, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
      );
    }

    if (mode === "subscribe" && verifyTokenParam === expectedVerifyToken) {
      console.log(`[${correlationId}] Verification token successfully validated.`);
      // Meta requires returning the challenge value as plain text with HTTP 200
      return new Response(challenge || "", {
        status: 200,
        headers: {
          ...SECURITY_HEADERS,
          "Content-Type": "text/plain; charset=utf-8",
        },
      });
    }

    console.warn(`[${correlationId}] Verification token mismatch or invalid mode: ${mode}`);
    return new Response(
      JSON.stringify({ error: "Forbidden: verification token mismatch" }),
      { status: 403, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
    );
  }

  // 3. POST Request: Meta Webhook Event Ingestion
  if (req.method === "POST") {
    const rawBody = await req.text();
    const signatureHeader = req.headers.get("x-hub-signature-256");
    let appSecret = Deno.env.get("WHATSAPP_APP_SECRET");

    // Fallback to platform_settings if appSecret not set in Deno.env
    if (!appSecret) {
      try {
        const { data: ps } = await supabase
          .from("platform_settings")
          .select("value")
          .eq("key", "meta_whatsapp_config")
          .maybeSingle();
        if (ps?.value?.app_secret) {
          appSecret = ps.value.app_secret;
        }
      } catch {
        // ignore
      }
    }

    // Cryptographic signature verification if Meta App Secret is configured
    if (appSecret) {
      if (!signatureHeader) {
        console.warn(`[${correlationId}] Missing x-hub-signature-256 header.`);
        return new Response(JSON.stringify({ error: "Missing signature" }), {
          status: 401,
          headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
        });
      }

      const isValid = await verifyMetaSignature(rawBody, signatureHeader, appSecret);
      if (!isValid) {
        console.warn(`[${correlationId}] Invalid x-hub-signature-256 signature.`);
        return new Response(JSON.stringify({ error: "Invalid signature" }), {
          status: 401,
          headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
        });
      }
    }

    const payloadHash = await computeSha256(rawBody);

    let parsedPayload: any = null;
    try {
      parsedPayload = JSON.parse(rawBody);
    } catch {
      console.warn(`[${correlationId}] Malformed JSON payload.`);
      return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
        status: 400,
        headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
      });
    }

    // Extract event type and Meta message ID for idempotency key
    const changeEntry = parsedPayload?.entry?.[0]?.changes?.[0];
    const eventType = changeEntry?.field || parsedPayload?.object || "unknown";
    const metaMessageId = changeEntry?.value?.messages?.[0]?.id || null;

    console.log(
      `[${correlationId}] Received webhook event: ${eventType}, messageId: ${metaMessageId ? metaMessageId.substring(0, 10) + "..." : "none"}`
    );

    // Idempotency check: if messageId exists and already recorded, avoid duplicate processing
    if (metaMessageId) {
      const { data: existing } = await supabase
        .from("whatsapp_webhook_events")
        .select("id")
        .eq("meta_message_id", metaMessageId)
        .maybeSingle();

      if (existing) {
        console.log(`[${correlationId}] Duplicate event detected (${metaMessageId}). Idempotent 200 returned.`);
        return new Response(
          JSON.stringify({ status: "success", duplicate: true }),
          { status: 200, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
        );
      }
    }

    // Persist event into isolated whatsapp_webhook_events table
    try {
      await supabase.from("whatsapp_webhook_events").insert({
        provider: "meta",
        event_type: eventType,
        received_at: new Date().toISOString(),
        processing_status: "received",
        payload_hash: payloadHash,
        meta_message_id: metaMessageId,
      });
    } catch (dbErr) {
      console.error(`[${correlationId}] Failed to log webhook event:`, dbErr);
    }

    // Process incoming WhatsApp messages
    try {
      const messages = changeEntry?.value?.messages;
      const contacts = changeEntry?.value?.contacts;
      const contactName = contacts?.[0]?.profile?.name || null;

      if (Array.isArray(messages) && messages.length > 0) {
        for (const msg of messages) {
          const fromPhone = msg.from;
          const msgId = msg.id;
          let body = "";

          if (msg.type === "text") {
            body = msg.text?.body || "";
          } else if (msg.type === "image") {
            body = msg.image?.caption || "📷 Image";
          } else if (msg.type === "document") {
            body = msg.document?.caption || "📄 Document";
          } else if (msg.type === "audio") {
            body = "🎵 Audio message";
          } else if (msg.type === "video") {
            body = "🎥 Video message";
          } else if (msg.type === "button") {
            body = msg.button?.text || "🔘 Button Response";
          } else if (msg.type === "interactive") {
            body = msg.interactive?.button_reply?.title || msg.interactive?.list_reply?.title || "🔘 Interactive Response";
          } else {
            body = `[${msg.type || "message"}]`;
          }

          if (fromPhone && body) {
            await supabase.from("whatsapp_messages").upsert(
              {
                wamid: msgId,
                phone_number: fromPhone,
                sender_name: contactName,
                direction: "inbound",
                message_type: msg.type || "text",
                message_body: body,
                status: "received",
                meta_payload: msg,
                created_at: new Date().toISOString(),
              },
              { onConflict: "wamid" }
            );
            console.log(`[${correlationId}] Ingested inbound WhatsApp msg from ${fromPhone}: ${body.substring(0, 30)}`);
          }
        }
      }

      // Process message status receipts (delivered, read, sent, failed)
      const statuses = changeEntry?.value?.statuses;
      if (Array.isArray(statuses) && statuses.length > 0) {
        for (const st of statuses) {
          const statusId = st.id;
          const statusVal = st.status; // 'sent' | 'delivered' | 'read' | 'failed'
          const errDetail = st.errors?.[0];
          const errorMsg = errDetail ? `[Meta #${errDetail.code || 'Error'}] ${errDetail.message || errDetail.title || 'Message failed to deliver'}` : null;

          if (statusId && statusVal) {
            const updateData: Record<string, any> = { status: statusVal };
            if (errorMsg) updateData.error_message = errorMsg;

            await supabase
              .from("whatsapp_messages")
              .update(updateData)
              .eq("wamid", statusId);
            console.log(`[${correlationId}] Updated message ${statusId} status to ${statusVal} ${errorMsg || ''}`);
          }
        }
      }
    } catch (ingestErr) {
      console.error(`[${correlationId}] Error processing messages/statuses into whatsapp_messages:`, ingestErr);
    }

    // Return HTTP 200 OK promptly as required by Meta Cloud API
    // IMPORTANT: No business logic, triggers, or message sends are executed here.
    return new Response(
      JSON.stringify({ status: "success", received: true }),
      {
        status: 200,
        headers: {
          ...SECURITY_HEADERS,
          "Content-Type": "application/json",
        },
      }
    );
  }

  // Other HTTP methods
  return new Response(JSON.stringify({ error: "Method not allowed" }), {
    status: 405,
    headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
  });
});
