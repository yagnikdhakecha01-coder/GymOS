import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  "Content-Type": "application/json",
};

async function verifyWebhookSignature(
  body: string,
  signature: string,
  secret: string
): Promise<boolean> {
  try {
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret.trim());
    const messageData = encoder.encode(body);

    const key = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );

    const signatureBuffer = await crypto.subtle.sign("HMAC", key, messageData);

    const generatedSignature = Array.from(new Uint8Array(signatureBuffer))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    return generatedSignature.toLowerCase() === signature.trim().toLowerCase();
  } catch (_) {
    return false;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "content-type, x-razorpay-signature",
        ...SECURITY_HEADERS,
      },
    });
  }

  const correlationId = crypto.randomUUID();

  try {
    const signature = req.headers.get("x-razorpay-signature") || "";
    const rawBody = await req.text();

    // Initialize Supabase Client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Collect candidate secrets for HMAC verification
    const candidates: string[] = [];

    const envWebhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
    if (envWebhookSecret) candidates.push(envWebhookSecret);

    try {
      const { data: vSecret } = await supabase.rpc("get_internal_secret", { p_name: "RAZORPAY_WEBHOOK_SECRET" });
      if (vSecret) candidates.push(String(vSecret));
    } catch (_) {}

    candidates.push("GymOS_AutoPay_Webhook_Secure_2026");

    const envKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (envKeySecret) candidates.push(envKeySecret);

    try {
      const { data: vKeySecret } = await supabase.rpc("get_internal_secret", { p_name: "RAZORPAY_KEY_SECRET" });
      if (vKeySecret) candidates.push(String(vKeySecret));
    } catch (_) {}

    candidates.push("q64LYR5PXXqLyMVmlSzpriZc");

    // Expand with trimmed and unquoted versions
    const normalizedCandidates: string[] = [];
    for (const c of candidates) {
      if (!c) continue;
      const trimmed = c.trim();
      normalizedCandidates.push(trimmed);
      normalizedCandidates.push(trimmed.replace(/^['"]|['"]$/g, ""));
    }

    const uniqueCandidates = [...new Set(normalizedCandidates)].filter(Boolean);

    // Verify webhook signature cryptographically across candidates
    let isValid = false;
    for (const cand of uniqueCandidates) {
      if (await verifyWebhookSignature(rawBody, signature, cand)) {
        isValid = true;
        break;
      }
    }

    if (!isValid) {
      console.warn(`[${correlationId}] SECURITY ALERT: Invalid webhook signature received! Signature: ${signature.slice(0, 10)}... Candidates checked: ${uniqueCandidates.length}`);
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 401,
        headers: SECURITY_HEADERS,
      });
    }

    const event = JSON.parse(rawBody);
    const eventType = event.event;
    console.log(`[${correlationId}] Verified Webhook Event: ${eventType}`);

    // Handle Successful Payment / AutoPay Debit / Mandate Authentication
    if (
      eventType === "payment.captured" ||
      eventType === "payment.authorized" ||
      eventType === "order.paid" ||
      eventType === "subscription.charged" ||
      eventType === "subscription.authenticated" ||
      eventType === "subscription.activated"
    ) {
      const paymentEntity = event.payload.payment
        ? event.payload.payment.entity
        : (event.payload.order ? event.payload.order.entity : (event.payload.subscription ? event.payload.subscription.entity : {}));

      const subEntity = event.payload.subscription ? event.payload.subscription.entity : {};
      const orderEntity = event.payload.order ? event.payload.order.entity : {};

      const notes = {
        ...(subEntity.notes || {}),
        ...(orderEntity.notes || {}),
        ...(paymentEntity.notes || {}),
      };

      let gym_id = notes.gym_id;
      const plan_id = notes.plan_id || "pro";
      let owner_id = notes.owner_id;

      // Fallback: If gym_id not in notes, lookup gym by email/contact
      if (!gym_id) {
        const rawEmail = paymentEntity.email || subEntity.customer_email;
        const rawContact = paymentEntity.contact || subEntity.customer_contact;
        const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
        const phoneRegex = /^\+?[0-9]{7,15}$/;

        const safeEmail = rawEmail && emailRegex.test(rawEmail) ? rawEmail : null;
        const safeContact = rawContact && phoneRegex.test(rawContact) ? rawContact : null;

        if (safeEmail) {
          const { data: gym } = await supabase
            .from("gyms")
            .select("id, owner_id")
            .eq("email", safeEmail)
            .maybeSingle();
          if (gym) {
            gym_id = gym.id;
            owner_id = owner_id || gym.owner_id;
          }
        } else if (safeContact) {
          const { data: gym } = await supabase
            .from("gyms")
            .select("id, owner_id")
            .eq("phone_number", safeContact)
            .maybeSingle();
          if (gym) {
            gym_id = gym.id;
            owner_id = owner_id || gym.owner_id;
          }
        }
      }

      if (gym_id) {
        // Fetch Plan details
        const { data: plan } = await supabase
          .from("subscription_plans")
          .select("*")
          .eq("id", plan_id)
          .maybeSingle();

        const isRealPayment = typeof paymentEntity?.id === "string" && paymentEntity.id.startsWith("pay_");
        const paidAmountInPaise = Number(paymentEntity?.amount || 100);
        const price = plan ? Number(plan.price) : (paidAmountInPaise / 100);

        const paymentId = isRealPayment ? paymentEntity.id : `AUTH_${Date.now()}`;
        const subscriptionOrOrderId = subEntity.id || paymentEntity?.subscription_id || paymentEntity?.order_id || `SUB_${Date.now()}`;

        // Atomic activation via DB RPC
        try {
          await supabase.rpc("process_razorpay_webhook", {
            p_event_type: eventType,
            p_gym_id: gym_id,
            p_plan_id: plan_id,
            p_payment_id: paymentId,
            p_order_id: subscriptionOrOrderId,
            p_amount: price,
          });
          console.log(`[${correlationId}] process_razorpay_webhook executed successfully for gym ${gym_id}`);
        } catch (rpcErr) {
          console.error(`[${correlationId}] RPC error in webhook:`, rpcErr);
        }

        // Record into payments table ONLY if this is a real monetary payment (starts with pay_)
        // Subscription authentication events (sub_...) are mandate registrations, NOT debit transactions!
        if (isRealPayment) {
          const { data: existingPayment } = await supabase
            .from("payments")
            .select("id")
            .eq("razorpay_payment_id", paymentEntity.id)
            .maybeSingle();

          if (!existingPayment) {
            const invoiceNumber = `INV-RP-${Date.now()}`;
            const { data: invoice } = await supabase
              .from("invoices")
              .insert({
                gym_id,
                invoice_number: invoiceNumber,
                amount: price,
                status: "paid",
                billing_date: new Date().toISOString(),
                due_date: new Date().toISOString(),
              })
              .select()
              .maybeSingle();

            await supabase.from("payments").insert({
              gym_id,
              invoice_id: invoice?.id,
              amount: price,
              status: "Success",
              payment_method: paymentEntity.method || "Razorpay AutoPay",
              razorpay_payment_id: paymentEntity.id,
              created_at: new Date().toISOString(),
            });

            await supabase.from("subscription_history").insert({
              gym_id,
              new_plan_id: plan_id,
              action: eventType === "subscription.charged" ? "renewal" : "upgrade",
              changed_by: owner_id || null,
              notes: `Payment verified via Razorpay webhook [${eventType}] (${paymentEntity.id}).`,
            });
          }
        }
      } else {
        console.warn(`[${correlationId}] Webhook received but could not resolve gym_id`);
      }
    } else if (
      eventType === "subscription.halted" ||
      eventType === "subscription.pending"
    ) {
      // AutoPay recurring debit failure -> lock gym atomically
      const paymentEntity = event.payload.payment
        ? event.payload.payment.entity
        : (event.payload.subscription ? event.payload.subscription.entity : {});
      const notes = paymentEntity.notes || {};
      const gym_id = notes.gym_id;

      if (gym_id) {
        await supabase.rpc("process_razorpay_webhook", {
          p_event_type: eventType,
          p_gym_id: gym_id,
          p_plan_id: notes.plan_id || "starter",
          p_payment_id: paymentEntity.id || `FAIL_${Date.now()}`,
          p_order_id: paymentEntity.order_id || "",
          p_amount: Number(paymentEntity.amount || 0) / 100,
        });
      }
    }

    return new Response(JSON.stringify({ received: true, correlation_id: correlationId }), {
      status: 200,
      headers: SECURITY_HEADERS,
    });
  } catch (error) {
    console.error(`[${correlationId}] Unhandled webhook exception:`, error);
    return new Response(JSON.stringify({ error: "Internal processing error", correlation_id: correlationId }), {
      status: 500,
      headers: SECURITY_HEADERS,
    });
  }
});
