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

async function resolveRazorpayCredentials(supabase: ReturnType<typeof createClient>) {
  let keyId = Deno.env.get("RAZORPAY_KEY_ID");
  let keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");

  // Fetch live credentials from encrypted Supabase Vault if env has old test key or is missing
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

  // Handle CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: securityHeaders });
  }

  try {
    const body = await req.json();
    const { gym_id, plan_id, owner_id } = body;

    if (!gym_id || !plan_id) {
      console.warn(`[${correlationId}] Bad Request: Missing gym_id or plan_id`);
      return new Response(
        JSON.stringify({
          error: "Missing required parameters: gym_id, plan_id",
          correlation_id: correlationId,
        }),
        { status: 400, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase Client
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error(`[${correlationId}] Configuration Error: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing`);
      return new Response(
        JSON.stringify({
          error: "Internal server configuration error",
          correlation_id: correlationId,
        }),
        { status: 500, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Fetch Plan Details from database
    const { data: plan, error: planError } = await supabase
      .from("subscription_plans")
      .select("*")
      .eq("id", plan_id)
      .maybeSingle();

    if (planError || !plan) {
      console.error(`[${correlationId}] Plan Error:`, planError || "Plan not found");
      return new Response(
        JSON.stringify({
          error: "Requested subscription plan could not be retrieved",
          correlation_id: correlationId,
        }),
        { status: 404, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    const price = Number(plan.price);
    const amountInPaise = Math.round(price * 100);

    // Securely retrieve Razorpay credentials
    const { keyId, keySecret } = await resolveRazorpayCredentials(supabase);

    if (!keyId || !keySecret) {
      console.error(`[${correlationId}] Razorpay configuration credentials missing`);
      return new Response(
        JSON.stringify({
          error: "Payment gateway credentials are not configured",
          correlation_id: correlationId,
        }),
        { status: 500, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    // Call Razorpay Order Creation API
    const authHeader = `Basic ${btoa(`${keyId}:${keySecret}`)}`;
    const razorpayResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        "Authorization": authHeader,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: amountInPaise,
        currency: "INR",
        receipt: gym_id.substring(0, 40),
        notes: {
          gym_id,
          plan_id,
          owner_id: owner_id || "",
        },
      }),
    });

    if (!razorpayResponse.ok) {
      const errorText = await razorpayResponse.text();
      console.error(`[${correlationId}] Razorpay Order creation failed:`, errorText);
      return new Response(
        JSON.stringify({
          error: "Failed to initiate payment transaction with gateway",
          correlation_id: correlationId,
        }),
        { status: 500, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    const order = await razorpayResponse.json();

    // STRICT SECURITY: Only public order details and public key_id returned. Secret is NEVER exposed!
    return new Response(
      JSON.stringify({
        success: true,
        order_id: order.id,
        amount: order.amount,
        currency: order.currency,
        key_id: keyId,
      }),
      { status: 200, headers: { ...securityHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error(`[${correlationId}] Unhandled exception in create-subscription:`, error);
    return new Response(
      JSON.stringify({
        error: "An unexpected error occurred while processing your request",
        correlation_id: correlationId,
      }),
      { status: 500, headers: { ...securityHeaders, "Content-Type": "application/json" } }
    );
  }
});
