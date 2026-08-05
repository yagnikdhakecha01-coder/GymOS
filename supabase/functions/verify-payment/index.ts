import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function verifySignature(
  orderId: string,
  paymentId: string,
  signature: string,
  secret: string
): Promise<boolean> {
  const text = `${orderId}|${paymentId}`;
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const {
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      gym_id,
      plan_id,
      owner_id,
    } = await req.json();

    if (
      !razorpay_order_id ||
      !razorpay_payment_id ||
      !razorpay_signature ||
      !gym_id ||
      !plan_id ||
      !owner_id
    ) {
      return new Response(
        JSON.stringify({ error: "Missing required parameters" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const secret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!secret) {
      return new Response(
        JSON.stringify({ error: "Razorpay Key Secret is not configured in Supabase" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Verify signature
    const isValid = await verifySignature(
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      secret
    );

    if (!isValid) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid signature verification" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase Client with Service Role Key
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Fetch Plan details
    const { data: plan } = await supabase
      .from("subscription_plans")
      .select("*")
      .eq("id", plan_id)
      .maybeSingle();

    const price = plan ? Number(plan.price) : 699.0;

    // 1. Update/Upsert Subscriptions table
    const { data: sub, error: subError } = await supabase
      .from("subscriptions")
      .upsert(
        {
          gym_id,
          owner_id,
          plan_id,
          status: "active",
          start_date: new Date().toISOString(),
          end_date: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
          razorpay_subscription_id: razorpay_order_id, // Save order_id as fallback reference
          updated_at: new Date().toISOString(),
        },
        { onConflict: "gym_id" }
      )
      .select()
      .single();

    if (subError) {
      return new Response(
        JSON.stringify({ error: "Failed to update subscription", details: subError }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Insert Invoice
    const invoiceNumber = `INV-${Date.now()}`;
    const { data: invoice } = await supabase
      .from("invoices")
      .insert({
        gym_id,
        subscription_id: sub.id,
        invoice_number: invoiceNumber,
        amount: price,
        status: "paid",
        billing_date: new Date().toISOString(),
        due_date: new Date().toISOString(),
      })
      .select()
      .single();

    // 3. Insert Payment
    await supabase.from("payments").insert({
      gym_id,
      subscription_id: sub.id,
      invoice_id: invoice?.id,
      amount: price,
      status: "Success",
      payment_method: "Razorpay Gateway",
      razorpay_payment_id: razorpay_payment_id,
    });

    // 4. Record Subscription History
    await supabase.from("subscription_history").insert({
      gym_id,
      old_plan_id: null,
      new_plan_id: plan_id,
      action: "upgrade",
      changed_by: owner_id,
      notes: `Upgraded/Renewed to ${plan_id.toUpperCase()} plan via verified Razorpay checkout.`,
    });

    return new Response(
      JSON.stringify({ success: true, message: "Payment verified & subscription updated successfully!" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
