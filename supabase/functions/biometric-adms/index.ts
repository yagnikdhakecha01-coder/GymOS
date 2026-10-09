import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const SECURITY_HEADERS = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, authorization",
};

/**
 * Standard eSSL / ZKTeco Push ADMS Protocol Edge Function
 * Supports:
 *  - GET  /cdata?SN=... (Device handshake & heartbeat)
 *  - POST /cdata?SN=...&table=ATTLOG (Real-time & offline punch push)
 *  - GET  /getrequest?SN=... (Fetch pending delta commands for hardware)
 *  - POST /devicecmd?SN=... (Acknowledge command executed on device)
 *  - POST /ping (Test connection from GymOS Mobile App)
 */

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: SECURITY_HEADERS });
  }

  const url = new URL(req.url);
  const pathname = url.pathname;
  const searchParams = url.searchParams;

  // eSSL machines pass device serial as "SN"
  const deviceSN = (searchParams.get("SN") || searchParams.get("sn") || "").trim();
  const table = searchParams.get("table") || "";

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // ── TEST / HEALTH CHECK FROM APP ──────────────────────────────
  if (pathname.endsWith("/ping") || (req.method === "POST" && pathname.endsWith("/test-punch"))) {
    try {
      const body = await req.json();
      const sn = (body.device_serial || deviceSN || "").trim();
      if (!sn) {
        return new Response(JSON.stringify({ success: false, error: "device_serial is required" }), {
          status: 400,
          headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
        });
      }

      if (pathname.endsWith("/ping")) {
        const { data, error } = await supabase.rpc("poll_adms_commands", { p_device_serial: sn });
        if (error || !data || !data.success) {
          return new Response(JSON.stringify({ success: false, error: data?.error || error?.message || "Device not registered" }), {
            status: 404,
            headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
          });
        }
        return new Response(JSON.stringify({ success: true, message: "Device is linked & active in GymOS", gym_id: data.gym_id }), {
          status: 200,
          headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
        });
      }

      // Simulated Punch
      const pin = parseInt(body.pin || "101", 10);
      const verifyMode = body.verify_mode || "face";
      const punchTime = body.punch_time || new Date().toISOString();

      const { data, error } = await supabase.rpc("process_adms_punch", {
        p_device_serial: sn,
        p_pin: pin,
        p_punch_time: punchTime,
        p_verify_mode: verifyMode,
      });

      return new Response(JSON.stringify({ success: !error && data?.success, result: data, error: error?.message }), {
        status: 200,
        headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
      });
    } catch (e: any) {
      return new Response(JSON.stringify({ success: false, error: e.message }), {
        status: 500,
        headers: { ...SECURITY_HEADERS, "Content-Type": "application/json" },
      });
    }
  }

  // If no serial number provided on hardware endpoints
  if (!deviceSN) {
    return new Response("ERROR: Missing Device Serial (SN)", {
      status: 400,
      headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
    });
  }

  // ── 1. HANDSHAKE: GET /cdata?SN=... ─────────────────────────────
  if (req.method === "GET" && (pathname.endsWith("/cdata") || searchParams.has("options"))) {
    // Check if device is paired to a gym
    const { data, error } = await supabase
      .from("gym_biometric_devices")
      .select("id, gym_id, status")
      .eq("device_serial_number", deviceSN)
      .maybeSingle();

    if (error || !data) {
      console.warn(`[ADMS] Handshake rejected for unknown SN: ${deviceSN}. err: ${JSON.stringify(error)}, keyLen: ${supabaseServiceKey?.length || 0}`);
      return new Response(`ERROR: UNREGISTERED DEVICE (${error?.message || 'not found'})`, {
        status: 401,
        headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
      });
    }

    // Update heartbeat
    await supabase
      .from("gym_biometric_devices")
      .update({ last_heartbeat: new Date().toISOString(), status: "online" })
      .eq("id", data.id);

    // Standard eSSL / ZKTeco IClock configuration parameters
    const handshakeResponse = [
      `GET OPTION FROM: ${deviceSN}`,
      "Stamp=9999",
      "OpStamp=9999",
      "PhotoStamp=9999",
      "TransTimes=00:00;14:05",
      "TransInterval=1",
      "TransFlag=1111111111",
      "TimeZone=5.5",
      "Realtime=1",
      "Delay=10",
      "SyncTime=1",
      "ServerVersion=3.1.1",
    ].join("\n");

    return new Response(handshakeResponse, {
      status: 200,
      headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
    });
  }

  // ── 2. PUNCH LOGS PUSH: POST /cdata?SN=...&table=ATTLOG ────────
  if (req.method === "POST" && (pathname.endsWith("/cdata") || table === "ATTLOG")) {
    // Validate device registration
    const { data: devData, error: devErr } = await supabase
      .from("gym_biometric_devices")
      .select("id, gym_id")
      .eq("device_serial_number", deviceSN)
      .maybeSingle();

    if (devErr || !devData) {
      console.warn(`[ADMS] Punch push rejected for SN: ${deviceSN}. devErr: ${JSON.stringify(devErr)}, keyLen: ${supabaseServiceKey?.length || 0}`);
      return new Response(`ERROR: UNREGISTERED DEVICE (${devErr?.message || 'not found'})`, {
        status: 401,
        headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
      });
    }

    const rawText = await req.text();
    const lines = rawText.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);

    let processedCount = 0;

    for (const line of lines) {
      // eSSL / ZKTeco tab-delimited format:
      // PIN \t DateTime \t Status \t VerifyType \t WorkCode \t Reserved
      // e.g. "101\t2026-10-09 10:30:15\t0\t15\t0\t0" (15 = Face, 1 = Fingerprint, 4 = Card)
      const parts = line.split("\t");
      if (parts.length >= 2) {
        const pin = parseInt(parts[0], 10);
        const timeStr = parts[1];
        const verifyCode = parts[3] ? parseInt(parts[3], 10) : 15;
        const verifyMode = verifyCode === 15 ? "face" : verifyCode === 1 ? "fingerprint" : "card";

        // Parse timestamp into ISO format (assuming device is configured with IST or sends local time)
        let punchIso = new Date().toISOString();
        try {
          // Format: YYYY-MM-DD HH:MM:SS
          const formatted = timeStr.replace(" ", "T") + "+05:30";
          punchIso = new Date(formatted).toISOString();
        } catch {
          // fallback to now
        }

        if (!isNaN(pin)) {
          const { error: rpcErr } = await supabase.rpc("process_adms_punch", {
            p_device_serial: deviceSN,
            p_pin: pin,
            p_punch_time: punchIso,
            p_verify_mode: verifyMode,
          });

          if (!rpcErr) {
            processedCount++;
          }
        }
      }
    }

    console.log(`[ADMS] Ingested ${processedCount} punches from SN: ${deviceSN}`);
    return new Response(`OK: ${processedCount}`, {
      status: 200,
      headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
    });
  }

  // ── 3. DELTA COMMAND POLLING: GET /getrequest?SN=... ──────────
  if (req.method === "GET" && (pathname.endsWith("/getrequest") || searchParams.has("getrequest"))) {
    const { data, error } = await supabase.rpc("poll_adms_commands", { p_device_serial: deviceSN });

    if (error || !data || !data.success || !data.commands || data.commands.length === 0) {
      return new Response("OK", {
        status: 200,
        headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
      });
    }

    // Format commands into eSSL / ZKTeco device command string
    // e.g. "C:1:DATA USER PIN=105\tName=Rahul S\tPri=0\tExpires=2026-12-31\tDisable=0\n"
    const commandLines: string[] = [];
    for (const cmd of data.commands) {
      const isAllowed = cmd.is_access_allowed === true;
      const expiry = cmd.expiry_date || "2099-12-31";
      const disableFlag = isAllowed ? "0" : "1";

      if (cmd.command === "DELETE_USER") {
        commandLines.push(`C:${cmd.id}:DATA DELETE USER PIN=${cmd.pin}`);
      } else {
        commandLines.push(
          `C:${cmd.id}:DATA USER PIN=${cmd.pin}\tName=${cmd.name || "Member"}\tPri=0\tExpires=${expiry}\tDisable=${disableFlag}`
        );
      }
    }

    console.log(`[ADMS] Dispatched ${commandLines.length} delta commands to SN: ${deviceSN}`);
    return new Response(commandLines.join("\n") + "\n", {
      status: 200,
      headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
    });
  }

  // ── 4. COMMAND ACKNOWLEDGMENT: POST /devicecmd?SN=... ──────────
  if (req.method === "POST" && pathname.endsWith("/devicecmd")) {
    const rawText = await req.text();
    // Device responds with: "ID=1&Return=0&CMD=..."
    const ackIds: string[] = [];
    const lines = rawText.split("\n");
    for (const l of lines) {
      const match = l.match(/ID=([a-f0-9\-]+)/i);
      if (match && match[1]) {
        ackIds.push(match[1]);
      }
    }

    if (ackIds.length > 0) {
      await supabase.rpc("ack_adms_commands", {
        p_device_serial: deviceSN,
        p_command_ids: ackIds,
      });
      console.log(`[ADMS] Acknowledged ${ackIds.length} commands from SN: ${deviceSN}`);
    }

    return new Response("OK", {
      status: 200,
      headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
    });
  }

  // Default response
  return new Response("OK", {
    status: 200,
    headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain" },
  });
});
