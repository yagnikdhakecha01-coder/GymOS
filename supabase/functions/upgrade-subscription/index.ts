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
    const { gym_id, new_plan_id, owner_id } = body;

    if (!gym_id || !new_plan_id) {
      console.warn(`[${correlationId}] Missing gym_id or new_plan_id`);
      return new Response(
        JSON.stringify({ error: "Missing required parameters: gym_id, new_plan_id", correlation_id: correlationId }),
        { status: 400, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 1. Fetch current subscription and gym details
    const { data: sub, error: subErr } = await supabase
      .from("subscriptions")
      .select("*")
      .eq("gym_id", gym_id)
      .maybeSingle();

    const { data: gym, error: gymErr } = await supabase
      .from("gyms")
      .select("*")
      .eq("id", gym_id)
      .maybeSingle();

    const currentPlanId = (sub?.plan_id || gym?.plan || "free_trial").toLowerCase();

    // 2. Fetch new plan details from database
    const { data: newPlan, error: newPlanErr } = await supabase
      .from("subscription_plans")
      .select("*")
      .eq("id", new_plan_id)
      .maybeSingle();

    if (newPlanErr || !newPlan) {
      return new Response(
        JSON.stringify({ error: "New plan not found", correlation_id: correlationId }),
        { status: 404, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch old plan details
    const { data: oldPlan } = await supabase
      .from("subscription_plans")
      .select("*")
      .eq("id", currentPlanId)
      .maybeSingle();

    const oldPrice = oldPlan ? Number(oldPlan.price) : 0.0;
    const newPrice = Number(newPlan.price);

    // 3. Compute Prorated Unused Days Credit
    let remainingDays = 0;
    let unusedCredit = 0.0;

    const expiryDateStr = sub?.end_date || gym?.expiry_date;
    if (expiryDateStr && oldPrice > 0) {
      const expiryDate = new Date(expiryDateStr);
      const now = new Date();
      if (expiryDate > now) {
        remainingDays = Math.max(0, Math.ceil((expiryDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));
        const dailyRate = oldPrice / 30.0;
        unusedCredit = Math.round(dailyRate * remainingDays * 100) / 100;
        // Cap unused credit so it doesn't exceed new plan price minus minimum 1 rupee
        if (unusedCredit > newPrice - 1) {
          unusedCredit = Math.max(0, newPrice - 1);
        }
      }
    }

    const payableAmount = Math.max(1, Math.round(newPrice - unusedCredit));
    const oldSubId = sub?.razorpay_subscription_id || "";

    // 4. Retrieve credentials securely from Vault
    const { keyId, keySecret } = await resolveRazorpayCredentials(supabase);
    if (!keyId || !keySecret) {
      return new Response(
        JSON.stringify({ error: "Payment gateway credentials unavailable", correlation_id: correlationId }),
        { status: 500, headers: { ...securityHeaders, "Content-Type": "application/json" } }
      );
    }

    const authHeader = `Basic ${btoa(`${keyId}:${keySecret}`)}`;
    const rzpPlanId = newPlan.razorpay_plan_id;
    let subscriptionId: string | null = null;
    let orderId: string | null = null;

    // 5. Create new Razorpay Subscription for new plan
    if (rzpPlanId) {
      try {
        const subRes = await fetch("https://api.razorpay.com/v1/subscriptions", {
          method: "POST",
          headers: {
            "Authorization": authHeader,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            plan_id: rzpPlanId,
            total_count: 60,
            quantity: 1,
            customer_notify: 1,
            notes: {
              gym_id,
              is_upgrade: "true",
              old_plan_id: currentPlanId,
              new_plan_id,
              old_sub_id: oldSubId,
              remaining_days: String(remainingDays),
              unused_credit: String(unusedCredit),
              payable_amount: String(payableAmount),
              owner_id: owner_id || "",
            },
          }),
        });

        if (subRes.ok) {
          const subData = await subRes.json();
          subscriptionId = subData.id;
        } else {
          console.warn(`[${correlationId}] Subscription create returned:`, await subRes.text());
        }
      } catch (err) {
        console.warn(`[${correlationId}] Error creating subscription:`, err);
      }
    }

    // Fallback to order if needed
    if (!subscriptionId) {
      const orderRes = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: {
          "Authorization": authHeader,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          amount: Math.round(payableAmount * 100),
          currency: "INR",
          receipt: gym_id.substring(0, 40),
          notes: {
            gym_id,
            is_upgrade: "true",
            old_plan_id: currentPlanId,
            new_plan_id,
            old_sub_id: oldSubId,
            unused_credit: String(unusedCredit),
            owner_id: owner_id || "",
          },
        }),
      });

      if (orderRes.ok) {
        const orderData = await orderRes.json();
        orderId = orderData.id;
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        subscription_id: subscriptionId,
        order_id: orderId || subscriptionId,
        old_plan_id: currentPlanId,
        new_plan_id,
        new_plan_name: newPlan.name,
        new_plan_price: newPrice,
        old_plan_price: oldPrice,
        remaining_days: remainingDays,
        unused_credit: unusedCredit,
        payable_amount: payableAmount,
        old_sub_id: oldSubId,
        key_id: keyId,
      }),
      { status: 200, headers: { ...securityHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error(`[${correlationId}] Unhandled exception in upgrade-subscription:`, error);
    return new Response(
      JSON.stringify({ error: "Failed to process plan upgrade", correlation_id: correlationId }),
      { status: 500, headers: { ...securityHeaders, "Content-Type": "application/json" } }
    );
  }
});
