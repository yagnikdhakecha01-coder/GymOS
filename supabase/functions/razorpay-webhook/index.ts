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
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
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

  return generatedSignature === signature;
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
    const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") || "";

    if (!signature || !webhookSecret) {
      console.warn(`[${correlationId}] Webhook rejected: Missing signature or server webhook secret`);
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 400,
        headers: SECURITY_HEADERS,
      });
    }

    const rawBody = await req.text();

    // Verify webhook signature cryptographically
    const isValid = await verifyWebhookSignature(rawBody, signature, webhookSecret);
    if (!isValid) {
      console.warn(`[${correlationId}] Invalid webhook signature received`);
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 401,
        headers: SECURITY_HEADERS,
      });
    }

    const event = JSON.parse(rawBody);
    const eventType = event.event;

    // Initialize Supabase Client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    if (eventType === "payment.captured" || eventType === "payment.authorized" || eventType === "order.paid") {
      const paymentEntity = event.payload.payment ? event.payload.payment.entity : (event.payload.order ? event.payload.order.entity : {});
      const notes = paymentEntity.notes || {};
      let gym_id = notes.gym_id;
      const plan_id = notes.plan_id || 'pro';
      let owner_id = notes.owner_id;

      // Fallback: If gym_id not in notes, securely lookup gym with sanitized inputs
      if (!gym_id) {
        const rawEmail = paymentEntity.email;
        const rawContact = paymentEntity.contact;
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
        // Fetch Plan details to enforce strict server-side price check
        const { data: plan } = await supabase
          .from("subscription_plans")
          .select("*")
          .eq("id", plan_id)
          .maybeSingle();

        // Strict Server-Side Amount Verification (Prevent Price Tampering)
        if (plan) {
          const expectedAmountInPaise = Math.round(Number(plan.price) * 100);
          const paidAmountInPaise = Number(paymentEntity.amount);
          if (paidAmountInPaise < expectedAmountInPaise) {
            console.error(`[${correlationId}] SECURITY ALERT: Amount mismatch! Paid: ${paidAmountInPaise}, Expected: ${expectedAmountInPaise} for plan: ${plan_id}`);
            return new Response(JSON.stringify({ error: "Amount tampering detected" }), {
              status: 400,
              headers: SECURITY_HEADERS,
            });
          }
        }

        const price = plan ? Number(plan.price) : Number(paymentEntity.amount) / 100;

        // 1. Update/Upsert Subscription status
        const { data: sub } = await supabase
          .from("subscriptions")
          .upsert(
            {
              gym_id,
              ...(owner_id ? { owner_id } : {}),
              plan_id,
              status: "active",
              start_date: new Date().toISOString(),
              end_date: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
              trial_end: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
              razorpay_subscription_id: paymentEntity.id || paymentEntity.order_id,
              auto_pay: true,
              updated_at: new Date().toISOString(),
            },
            { onConflict: "gym_id" }
          )
          .select()
          .maybeSingle();

        // 2. Update Gyms table directly
        await supabase.from("gyms").update({
          plan: plan_id,
          status: "active",
          expiry_date: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
          is_locked: false,
        }).eq("id", gym_id);

        // 3. Check if payment already exists in DB
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
              subscription_id: sub?.id,
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
            subscription_id: sub?.id,
            invoice_id: invoice?.id,
            amount: price,
            status: "Success",
            payment_method: paymentEntity.method || "Razorpay Gateway",
            razorpay_payment_id: paymentEntity.id,
            created_at: new Date().toISOString(),
          });

          await supabase.from("subscription_history").insert({
            gym_id,
            old_plan_id: null,
            new_plan_id: plan_id,
            action: "upgrade",
            changed_by: owner_id,
            notes: `Upgraded to ${plan_id.toUpperCase()} plan via verified Razorpay webhook (${paymentEntity.id}).`,
          });
        }
      }
    } else if (eventType === "payment.failed") {
      const paymentEntity = event.payload.payment.entity;
      const notes = paymentEntity.notes || {};
      const gym_id = notes.gym_id;

      if (gym_id) {
        // Record Failed Payment
        await supabase.from("payments").insert({
          gym_id,
          amount: Number(paymentEntity.amount) / 100,
          status: "Failed",
          payment_method: paymentEntity.method || "Razorpay Webhook",
          razorpay_payment_id: paymentEntity.id,
          created_at: new Date().toISOString(),
        });
      }
    }

    return new Response(JSON.stringify({ received: true }), {
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
