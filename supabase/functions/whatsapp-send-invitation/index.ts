import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: SECURITY_HEADERS });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body = await req.json().catch(() => ({}));
    const record = body.record || body;

    const gymId = record.gym_id;
    const memberId = record.member_id;
    const staffId = record.staff_id;
    const invitationCode = record.invitation_code;
    const phone = (record.registered_mobile || record.phone || "").replace(/[^0-9]/g, "");

    if (!invitationCode || !phone) {
      return new Response(
        JSON.stringify({ error: "Missing invitation_code or registered_mobile" }),
        { status: 400, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // 1. Check Invitation Settings in platform_settings
    const { data: invSettingsRow } = await supabase
      .from("platform_settings")
      .select("value")
      .eq("key", "whatsapp_invitation_settings")
      .maybeSingle();

    const invSettings = invSettingsRow?.value || {};
    const autoSendEnabled = invSettings.auto_send_enabled === true;
    const isManualTrigger = body.force_send === true;

    // Safety gate: skip if auto_send is disabled and not forced manually
    if (!autoSendEnabled && !isManualTrigger) {
      console.log(`[Auto-Send Disabled] Skipping automated invite for ${phone}.`);
      return new Response(
        JSON.stringify({
          status: "skipped",
          message: "Auto-send invitation is disabled by Admin in platform_settings.",
        }),
        { status: 200, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
      );
    }

    const templateName = invSettings.template_name || "";
    const templateLang = invSettings.template_language || "en_US";
    const paramMapping = invSettings.param_mapping || {
      "1": "gym_name",
      "2": "name",
      "3": "invitation_code",
      "4": "phone",
    };

    if (!templateName) {
      console.error("[Configuration Error] Template name not set in whatsapp_invitation_settings.");
      return new Response(
        JSON.stringify({ error: "No template configured in whatsapp_invitation_settings" }),
        { status: 400, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // 2. Fetch Meta Credentials
    const { data: metaCredsRow } = await supabase
      .from("platform_settings")
      .select("value")
      .eq("key", "meta_whatsapp_config")
      .maybeSingle();

    const metaCreds = metaCredsRow?.value || {};
    const accessToken = metaCreds.access_token || Deno.env.get("WHATSAPP_ACCESS_TOKEN");
    const phoneNumberId = metaCreds.phone_number_id || Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");

    if (!accessToken || !phoneNumberId) {
      console.error("[Credentials Error] Meta WhatsApp credentials not configured.");
      return new Response(
        JSON.stringify({ error: "Meta WhatsApp credentials not found." }),
        { status: 500, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // 3. Resolve Gym Name & Person Name
    let gymName = "Our Gym";
    if (gymId) {
      const { data: gym } = await supabase.from("gyms").select("name").eq("id", gymId).maybeSingle();
      if (gym?.name) gymName = gym.name;
    }

    let personName = "Member";
    if (memberId) {
      const { data: mem } = await supabase.from("members").select("name").eq("id", memberId).maybeSingle();
      if (mem?.name) personName = mem.name;
    } else if (staffId) {
      const { data: stf } = await supabase.from("staff").select("name").eq("id", staffId).maybeSingle();
      if (stf?.name) personName = stf.name;
    }

    // 4. Build Dynamic Parameters from Mapping
    const sortedKeys = Object.keys(paramMapping).sort(
      (a, b) => (parseInt(a) || 0) - (parseInt(b) || 0)
    );

    const bodyVariables: string[] = [];
    for (const key of sortedKeys) {
      const field = paramMapping[key];
      switch (field) {
        case "gym_name":
          bodyVariables.push(gymName);
          break;
        case "name":
        case "member_name":
        case "staff_name":
          bodyVariables.push(personName);
          break;
        case "invitation_code":
        case "code":
          bodyVariables.push(invitationCode);
          break;
        case "phone":
        case "registered_mobile":
          bodyVariables.push(phone);
          break;
        default:
          bodyVariables.push(field || "-");
      }
    }

    const components: any[] = [];
    if (bodyVariables.length > 0) {
      components.push({
        type: "body",
        parameters: bodyVariables.map((val) => ({ type: "text", text: val.trim() })),
      });
    }

    const payload: any = {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: phone,
      type: "template",
      template: {
        name: templateName,
        language: { code: templateLang },
        ...(components.length > 0 ? { components } : {}),
      },
    };

    // 5. Send to Meta WhatsApp Graph API
    console.log(`[Dispatching WhatsApp Invite] Sending template ${templateName} to ${phone}...`);
    const metaRes = await fetch(`https://graph.facebook.com/v20.0/${phoneNumberId}/messages`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const metaData = await metaRes.json();

    if (!metaRes.ok || metaData.error) {
      console.error("[Meta API Error]", metaData.error);
      return new Response(
        JSON.stringify({ error: metaData.error?.message || "Failed to dispatch via Meta API", details: metaData }),
        { status: 502, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
      );
    }

    const wamid = metaData.messages?.[0]?.id || null;

    // 6. Record outbound message into whatsapp_messages table
    try {
      await supabase.from("whatsapp_messages").insert({
        wamid,
        phone_number: phone,
        sender_name: personName,
        direction: "outbound",
        message_type: "template",
        message_body: `[Invitation Template: ${templateName}] (Code: ${invitationCode})`,
        status: "sent",
        meta_payload: metaData,
        created_at: new Date().toISOString(),
      });
    } catch (insertErr) {
      console.warn("Failed to record outbound invite in whatsapp_messages:", insertErr);
    }

    return new Response(
      JSON.stringify({ success: true, wamid, to: phone, code: invitationCode }),
      { status: 200, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error("[Unhandled Exception]", err);
    return new Response(
      JSON.stringify({ error: err.message || "Internal server error" }),
      { status: 500, headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" } }
    );
  }
});
