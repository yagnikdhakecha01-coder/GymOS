/**
 * ========================================================================================
 *  GymOS Biometric & Face Terminal Simulator (eSSL / ZKTeco Testing Utility)
 * ========================================================================================
 * Simulates an eSSL Face Recognition machine sending real-time face punches and
 * downloading member expiry / delta access commands from GymOS Cloud ADMS.
 *
 * Usage:
 *   node test_face_punch_simulator.js <device_serial_number> [pin]
 *
 * Example:
 *   node test_face_punch_simulator.js CK99812401 101
 * ========================================================================================
 */

const SUPABASE_URL = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const ADMS_ENDPOINT = `${SUPABASE_URL}/functions/v1/biometric-adms`;

async function testSimulator() {
  const args = process.argv.slice(2);
  const deviceSN = args[0] || "TEST_DEVICE_SN";
  const pin = parseInt(args[1] || "101", 10);

  console.log("====================================================================");
  console.log("   GYMOS eSSL FACE TERMINAL HARDWARE SIMULATOR");
  console.log("====================================================================");
  console.log(`Device Serial Number (SN) : ${deviceSN}`);
  console.log(`Simulated Member PIN      : #${pin}`);
  console.log(`Cloud Server Endpoint     : ${ADMS_ENDPOINT}`);
  console.log("--------------------------------------------------------------------\n");

  // 1. Test Device Handshake (GET /cdata?SN=...)
  console.log("[1/3] Testing Hardware Handshake (GET /cdata)...");
  try {
    const handshakeRes = await fetch(`${ADMS_ENDPOINT}/cdata?SN=${deviceSN}&options=all`);
    const handshakeText = await handshakeRes.text();
    console.log(`Handshake Status: HTTP ${handshakeRes.status}`);
    console.log(`Response Preview:\n${handshakeText.substring(0, 150)}...\n`);
  } catch (err) {
    console.error(`Handshake failed: ${err.message}`);
  }

  // 2. Test Face Punch Push (POST /cdata?SN=...&table=ATTLOG)
  console.log("[2/3] Simulating Member Face Scan at Turnstile (POST /cdata)...");
  try {
    const now = new Date();
    // Format YYYY-MM-DD HH:MM:SS
    const nowStr = now.toISOString().replace('T', ' ').substring(0, 19);
    // eSSL format: PIN \t DateTime \t Status(0=Checkin) \t VerifyType(15=Face) \t WorkCode(0) \t Reserved(0)
    const punchPayload = `${pin}\t${nowStr}\t0\t15\t0\t0\n`;

    const punchRes = await fetch(`${ADMS_ENDPOINT}/cdata?SN=${deviceSN}&table=ATTLOG`, {
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: punchPayload,
    });
    const punchText = await punchRes.text();
    console.log(`Punch Status: HTTP ${punchRes.status}`);
    console.log(`Response: ${punchText}\n`);
  } catch (err) {
    console.error(`Punch push failed: ${err.message}`);
  }

  // 3. Test Delta Command Polling (GET /getrequest?SN=...)
  console.log("[3/3] Polling Server for Expiry & Member Updates (GET /getrequest)...");
  try {
    const cmdRes = await fetch(`${ADMS_ENDPOINT}/getrequest?SN=${deviceSN}`);
    const cmdText = await cmdRes.text();
    console.log(`Command Poll Status: HTTP ${cmdRes.status}`);
    console.log(`Pending Hardware Commands:\n${cmdText.trim()}\n`);
  } catch (err) {
    console.error(`Command poll failed: ${err.message}`);
  }

  console.log("====================================================================");
  console.log("✔ Simulator test completed.");
  console.log("====================================================================");
}

testSimulator().catch(console.error);
