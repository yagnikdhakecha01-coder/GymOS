/**
 * ========================================================================================
 *  GymOS Biometric Sync Bridge — Interactive 1-Time Setup Wizard
 * ========================================================================================
 * Prompts user for all required parameters, verifies the Gym Secret Key with Supabase,
 * and saves a valid gymos_bridge_config.json file.
 */

const readline = require('readline');
const fs = require('fs');
const path = require('path');

const CONFIG_FILE = path.join(__dirname, 'gymos_bridge_config.json');
const SUPABASE_URL = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";

function createPrompt() {
  return readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
}

function askQuestion(rl, query) {
  return new Promise(resolve => rl.question(query, resolve));
}

async function verifySecretWithCloud(secret) {
  try {
    const url = `${SUPABASE_URL}/rest/v1/rpc/verify_biometric_device_secret`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
      },
      body: JSON.stringify({ p_device_secret: secret }),
      signal: AbortSignal.timeout(10000)
    });
    if (!res.ok) return { success: false, error: `HTTP ${res.status}` };
    return await res.json();
  } catch (err) {
    return { success: false, error: err.message };
  }
}

async function runWizard() {
  console.log("\n====================================================================");
  console.log("       GYMOS BIOMETRIC SYNC BRIDGE - 1-TIME SETUP WIZARD");
  console.log("             (Compatible with Windows 7, 8, 10, and 11)");
  console.log("====================================================================\n");

  const rl = createPrompt();

  let existingConfig = null;
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      existingConfig = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf-8'));
    } catch (_) {}
  }

  if (existingConfig && existingConfig.device_secret && existingConfig.device_secret !== "PASTE_YOUR_GYM_DEVICE_SECRET_HERE") {
    console.log("Checking current configuration...");
    const check = await verifySecretWithCloud(existingConfig.device_secret);
    if (check && check.success) {
      console.log(`\n✔ Current config is already linked to: [${check.gym_name}]`);
      const ans = await askQuestion(rl, "Do you want to re-enter / change the settings? (y/N): ");
      if (ans.trim().toLowerCase() !== 'y' && ans.trim().toLowerCase() !== 'yes') {
        console.log("\nKeeping existing configuration. Proceeding to start background service...\n");
        rl.close();
        process.exit(0);
      }
    }
  }

  console.log("\n--- STEP 1: GYM LINKING (DEVICE SECRET) ---");
  console.log("Kahan milega? GymOS Mobile App kholiye -> Owner Attendance Settings");
  console.log("-> 'Biometric & Face Recognition (Gate Access)' Card me jaakar Secret Key Copy karein.\n");

  let validSecret = "";
  let gymData = null;

  while (true) {
    const inputSecret = (await askQuestion(rl, "👉 Enter / Paste Gym Device Secret Key: ")).trim();
    if (!inputSecret) {
      console.log("❌ Secret Key khali nahi ho sakti! Dobara paste karein.\n");
      continue;
    }

    console.log("Connecting to GymOS Cloud to verify your gym...");
    const result = await verifySecretWithCloud(inputSecret);
    if (result && result.success) {
      gymData = result;
      validSecret = inputSecret;
      console.log(`\n====================================================================`);
      console.log(`✔ SUCCESS! LINKED TO GYM: ${result.gym_name.toUpperCase()}`);
      console.log(`✔ Gym ID: ${result.gym_id}`);
      console.log(`✔ Biometric Attendance: ${result.biometric_enabled ? 'ENABLED ✅' : 'DISABLED (Please turn ON in GymOS App) ⚠️'}`);
      console.log(`====================================================================\n`);
      break;
    } else {
      console.log(`❌ Invalid Secret Key! Cloud error: ${result?.error || 'Unknown'}`);
      console.log("Kripya GymOS App me jakar sahi Secret Key copy karke try karein.\n");
    }
  }

  console.log("--- STEP 2: HARDWARE MACHINE CONFIGURATION ---");
  console.log("(Default values ke liye direct ENTER press karein)\n");

  const defaultIp = (existingConfig?.devices?.[0]?.ip) || "192.168.1.201";
  const ipInput = (await askQuestion(rl, `👉 Biometric Machine Local IP [Default: ${defaultIp}]: `)).trim();
  const machineIp = ipInput || defaultIp;

  const defaultPort = (existingConfig?.devices?.[0]?.port) || 4370;
  const portInput = (await askQuestion(rl, `👉 Machine Port [Default: ${defaultPort}]: `)).trim();
  const machinePort = portInput ? parseInt(portInput, 10) : defaultPort;

  const defaultName = (existingConfig?.devices?.[0]?.name) || "Main Entrance Gate";
  const nameInput = (await askQuestion(rl, `👉 Device / Gate Name [Default: ${defaultName}]: `)).trim();
  const deviceName = nameInput || defaultName;

  const defaultType = (existingConfig?.devices?.[0]?.device_type) || "zkteco";
  const typeInput = (await askQuestion(rl, `👉 Device Type (zkteco / essl / realtime) [Default: ${defaultType}]: `)).trim();
  const deviceType = typeInput ? typeInput.toLowerCase() : defaultType;

  // Build final config
  const finalConfig = {
    supabase_url: SUPABASE_URL,
    supabase_anon_key: SUPABASE_ANON_KEY,
    device_secret: validSecret,
    gym_name: gymData?.gym_name || "My Gym",
    gym_id: gymData?.gym_id || "",
    devices: [
      {
        device_id: "GATE_01",
        name: deviceName,
        ip: machineIp,
        port: machinePort,
        device_type: deviceType
      }
    ],
    pull_interval_seconds: 15,
    push_interval_seconds: 10,
    sync_commands_interval_seconds: 30
  };

  fs.writeFileSync(CONFIG_FILE, JSON.stringify(finalConfig, null, 2), 'utf-8');

  console.log("\n====================================================================");
  console.log("✔ CONFIGURATION SAVED SUCCESSFULLY in 'gymos_bridge_config.json'!");
  console.log(`✔ Machine Target: ${machineIp}:${machinePort} (${deviceName})`);
  console.log(`✔ Linked Gym: ${gymData?.gym_name}`);
  console.log("====================================================================\n");

  rl.close();
}

runWizard().catch(err => {
  console.error("Wizard error:", err);
  process.exit(1);
});
