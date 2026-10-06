import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

function getSecurityAndCorsHeaders(req: Request) {
  const allowedOriginEnv = Deno.env.get("ALLOWED_ORIGIN");
  const origin = req.headers.get("origin");
  let allowOrigin = "*";
  if (allowedOriginEnv) {
    const allowed = allowedOriginEnv.split(",").map((s) => s.trim());
    if (origin && allowed.includes(origin)) {
      allowOrigin = origin;
    } else if (allowed.includes("*")) {
      allowOrigin = "*";
    } else {
      allowOrigin = allowed[0];
    }
  }
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  };
}

async function verifyHmac(text: string, signature: string, secret: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const messageData = encoder.encode(text);

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

async function verifySignature(
  orderOrSubId: string,
  paymentId: string,
  signature: string,
  secret: string
): Promise<boolean> {
  // Check order format: order_id|payment_id
  const matchOrder = await verifyHmac(`${orderOrSubId}|${paymentId}`, signature, secret);
  if (matchOrder) return true;

  // Check subscription format: payment_id|subscription_id
  const matchSub = await verifyHmac(`${paymentId}|${orderOrSubId}`, signature, secret);
  return matchSub;
}

async function resolveRazorpayCredentials(supabase: ReturnType<typeof createClient>) {
  let keyId = Deno.env.get("RAZORPAY_KEY_ID");
  let keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

  if (!keyId || keyId.startsWith("rzp_test")) {
    try {
      const { data: vKey } = await supabase.rpc("get_internal_secret", { p_name: "RAZORPAY_KEY_ID" });
      if (vKey) keyId = vKey;
    } catch (_) {}
  }
  if (!keySecret || keyId?.startsWith("rzp_live")) {
    try {
      const { data: vSecret } = await supabase.rpc("get_internal_secret", { p_name: "RAZORPAY_KEY_SECRET" });
      if (vSecret) keySecret = vSecret;
    } catch (_) {}
  }

  return { keyId, keySecret };
}

serve(async (req) => {
  const securityHeaders = getSecurityAndCorsHeaders(req);
  const correlationId = crypto.randomUUID();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: securityHeaders });
  }

  try {
    const body = await req.json();
    const {
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      gym_id,
      plan_id,
      owner_id,
      is_upgrade,
      old_plan_id,
      old_sub_id,
      unused_credit,
    } = body;

    if (
      !razorpay_order_id ||
      !razorpay_payment_id ||
      !razorpay_signature ||
      !gym_id ||
      !plan_id
    ) {
      console.warn(`[${correlationId}] Bad Request: Missing verification parameters`);
      return new Response(
        JSON.stringify({ error: "Missing required parameters", correlation_id: correlationId }),
        { status: 400, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const { keyId, keySecret } = await resolveRazorpayCredentials(supabase);

    if (!keySecret) {
      console.error(`[${correlationId}] Razorpay Key Secret is not configured in Supabase`);
      return new Response(
        JSON.stringify({ error: "Payment verification service is unavailable", correlation_id: correlationId }),
        { status: 500, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    // Verify HMAC-SHA256 signature
    const isValid = await verifySignature(
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      keySecret
    );

    if (!isValid) {
      console.warn(`[${correlationId}] Invalid Razorpay signature verification attempt for ${razorpay_order_id}`);
      return new Response(
        JSON.stringify({ success: false, error: "Payment signature verification failed", correlation_id: correlationId }),
        { status: 400, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch Plan details
    const { data: plan, error: planError } = await supabase
      .from("subscription_plans")
      .select("*")
      .eq("id", plan_id)
      .maybeSingle();

    if (planError) {
      console.error(`[${correlationId}] Error fetching plan:`, planError);
    }

    const price = plan ? Number(plan.price) : 699.0;
    let actualPaidAmount = price;

    // Verify payment from Razorpay API
    if (keyId && keySecret) {
      try {
        const authHeader = `Basic ${btoa(`${keyId}:${keySecret}`)}`;
        const rpRes = await fetch(`https://api.razorpay.com/v1/payments/${razorpay_payment_id}`, {
          headers: { "Authorization": authHeader },
        });
        if (rpRes.ok) {
          const rpPayment = await rpRes.json();
          actualPaidAmount = rpPayment.amount ? Number(rpPayment.amount) / 100 : price;
          if (rpPayment.status && rpPayment.status !== "captured" && rpPayment.status !== "authorized") {
            console.warn(`[${correlationId}] Razorpay payment status not completed: ${rpPayment.status}`);
            return new Response(
              JSON.stringify({ error: `Payment is not completed (status: ${rpPayment.status})`, correlation_id: correlationId }),
              { status: 400, headers: { ...securityHeaders, "Content-Type": "application/json" } }
            );
          }
        }
      } catch (checkErr) {
        console.warn(`[${correlationId}] Non-fatal: Razorpay amount check lookup encountered error (${checkErr})`);
      }
    }

    const isPlanUpgrade = is_upgrade === true || is_upgrade === "true";

    if (isPlanUpgrade && old_plan_id) {
      // 1. Process Plan Upgrade with Prorated credit adjustment in Database
      try {
        await supabase.rpc("process_plan_upgrade", {
          p_gym_id: gym_id,
          p_old_plan_id: old_plan_id,
          p_new_plan_id: plan_id,
          p_payment_id: razorpay_payment_id,
          p_new_subscription_id: razorpay_order_id,
          p_amount_paid: actualPaidAmount,
          p_unused_credit: Number(unused_credit || 0),
          p_owner_id: owner_id || null,
        });
      } catch (upgErr) {
        console.error(`[${correlationId}] process_plan_upgrade error:`, upgErr);
      }

      // 2. Automatically cancel old Razorpay AutoPay subscription mandate to prevent double debit!
      if (old_sub_id && String(old_sub_id).startsWith("sub_") && keyId && keySecret) {
        try {
          const authHeader = `Basic ${btoa(`${keyId}:${keySecret}`)}`;
          const cancelRes = await fetch(`https://api.razorpay.com/v1/subscriptions/${old_sub_id}/cancel`, {
            method: "POST",
            headers: {
              "Authorization": authHeader,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ cancel_at_cycle_end: 0 }),
          });
          console.log(`[${correlationId}] Old mandate ${old_sub_id} cancelled. Status: ${cancelRes.status}`);
        } catch (cancelErr) {
          console.warn(`[${correlationId}] Error cancelling old mandate ${old_sub_id}:`, cancelErr);
        }
      }
    } else {
      // Normal New Plan Activation
      try {
        await supabase.rpc("process_razorpay_webhook", {
          p_event_type: "payment.authorized",
          p_gym_id: gym_id,
          p_plan_id: plan_id,
          p_payment_id: razorpay_payment_id,
          p_order_id: razorpay_order_id,
          p_amount: actualPaidAmount,
        });
      } catch (rpcErr) {
        console.warn(`[${correlationId}] RPC process_razorpay_webhook error: ${rpcErr}`);
      }

      // Record Payment
      try {
        await supabase.from("payments").insert({
          gym_id,
          amount: actualPaidAmount,
          status: "Success",
          payment_method: "Razorpay Gateway",
          razorpay_payment_id: razorpay_payment_id,
          razorpay_signature: razorpay_signature,
          created_at: new Date().toISOString(),
        });
      } catch (paymentError) {
        console.error(`[${correlationId}] Error recording payment:`, paymentError);
      }

      // Record Subscription History
      try {
        await supabase.from("subscription_history").insert({
          gym_id,
          new_plan_id: plan_id,
          action: "upgrade",
          changed_by: owner_id || null,
          notes: `Activated ${plan_id.toUpperCase()} plan (₹${actualPaidAmount}) via verified Razorpay checkout.`,
          created_at: new Date().toISOString(),
        });
      } catch (historyError) {
        console.error(`[${correlationId}] Error writing subscription history:`, historyError);
      }
    }

    return new Response(
      JSON.stringify({ success: true, message: "Payment verified & subscription updated successfully!" }),
      { status: 200, headers: { ...securityHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error(`[${correlationId}] Unhandled exception in verify-payment:`, error);
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred while verifying payment", correlation_id: correlationId }),
      { status: 500, headers: { ...securityHeaders, "Content-Type": "application/json" } }
    );
  }
});
