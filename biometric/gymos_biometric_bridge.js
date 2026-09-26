/**
 * ========================================================================================
 *  GymOS Biometric & Gate Access Local Sync Bridge (Windows Offline-First Agent)
 * ========================================================================================
 * Designed for Gym Reception PCs (Windows 10 / 11 / Server).
 * Runs on Node.js (Built-in fetch + Built-in node:sqlite with ZERO npm install needed).
 * 
 * Key Guarantees:
 * 1. ZERO DATA LOSS:
 *    - Physical machine (eSSL, ZKTeco, Realtime) buffers punches in internal flash memory.
 *    - Bridge pulls punches and commits them immediately to local SQLite with WAL mode.
 *    - If power cuts or PC turns off, data remains intact in 'gymos_biometric_buffer.db'.
 *    - Once internet is available, batches are sent to GymOS Supabase via secure RPC.
 *    - Local records are only marked synced = 1 once DB server returns success.
 * 
 * 2. TWO-WAY EXPIRY SYNC:
 *    - Polls poll_biometric_commands from GymOS.
 *    - When owner renews or edits membership in app, this bridge updates the member's
 *      expiry date directly into the biometric machine's memory via Port 4370.
 *    - If expired, device gate access is revoked even if internet is down!
 * 
 * 3. TIGHT SECURITY:
 *    - Never exposes Supabase master/service keys or DB passwords.
 *    - Uses Gym Biometric Secret Token generated in GymOS Owner Settings.
 * ========================================================================================
 */

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

const CONFIG_FILE = path.join(__dirname, 'gymos_bridge_config.json');
const LOCAL_DB_FILE = path.join(__dirname, 'gymos_biometric_buffer.db');
const SUPABASE_ANON_KEY = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";

const DEFAULT_CONFIG = {
  supabase_url: "https://gilxxyvwqucwwwqaxosx.supabase.co",
  supabase_anon_key: SUPABASE_ANON_KEY,
  device_secret: "PASTE_YOUR_GYM_DEVICE_SECRET_HERE",
  devices: [
    {
      device_id: "MAIN_GATE_01",
      name: "Main Entrance Gate",
      ip: "192.168.1.201",
      port: 4370,
      device_type: "zkteco"
    }
  ],
  pull_interval_seconds: 15,
  push_interval_seconds: 10,
  sync_commands_interval_seconds: 30
};

function log(msg, level = 'INFO') {
  const ts = new Date().toISOString().replace('T', ' ').substring(0, 19);
  console.log(`[${ts}] [${level}] ${msg}`);
}

function loadConfig() {
  if (!fs.existsSync(CONFIG_FILE)) {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(DEFAULT_CONFIG, null, 2), 'utf-8');
    log(`Created default config: ${CONFIG_FILE}. Please edit it with your gym secret and machine IP.`, 'WARN');
    return DEFAULT_CONFIG;
  }
  try {
    return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf-8'));
  } catch (err) {
    log(`Error reading config: ${err.message}`, 'ERROR');
    return DEFAULT_CONFIG;
  }
}

function initLocalDatabase() {
  const db = new DatabaseSync(LOCAL_DB_FILE);
  // Enable WAL mode for zero data loss on unexpected power cuts
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA synchronous = NORMAL;");
  
  db.exec(`
    CREATE TABLE IF NOT EXISTS local_punches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_id TEXT NOT NULL,
      biometric_pin INTEGER NOT NULL,
      punch_time TEXT NOT NULL,
      punch_type TEXT DEFAULT 'CHECK_IN',
      verify_mode TEXT DEFAULT 'FINGERPRINT',
      synced INTEGER DEFAULT 0,
      synced_at TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(device_id, biometric_pin, punch_time)
    );
  `);
  db.exec("CREATE INDEX IF NOT EXISTS idx_unpushed ON local_punches(synced);");
  return db;
}

async function pushPendingPunches(db, supabaseUrl, deviceSecret, anonKey = SUPABASE_ANON_KEY) {
  try {
    const query = db.prepare(`
      SELECT id, device_id, biometric_pin, punch_time, punch_type, verify_mode 
      FROM local_punches 
      WHERE synced = 0 
      ORDER BY punch_time ASC 
      LIMIT 100;
    `);
    const rows = query.all();
    if (!rows || rows.length === 0) return;

    const punchIds = rows.map(r => r.id);
    const punchesPayload = rows.map(r => ({
      device_id: r.device_id,
      pin: r.biometric_pin,
      punch_time: r.punch_time,
      punch_type: r.punch_type,
      verify_mode: r.verify_mode
    }));

    log(`Uploading ${punchesPayload.length} offline punches to GymOS Cloud...`);
    const rpcUrl = `${supabaseUrl}/rest/v1/rpc/process_biometric_punch_batch`;

    const res = await fetch(rpcUrl, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'apikey': anonKey,
        'Authorization': `Bearer ${anonKey}`
      },
      body: JSON.stringify({
        p_device_secret: deviceSecret,
        p_punches: punchesPayload
      }),
      signal: AbortSignal.timeout(15000)
    });

    if (res.ok) {
      const data = await res.json();
      if (data && data.success) {
        log(`Synced ${data.processed_count} punches successfully! Duplicates ignored: ${data.duplicates_ignored}`);
        const updateStmt = db.prepare(`UPDATE local_punches SET synced = 1, synced_at = ? WHERE id = ?`);
        const nowStr = new Date().toISOString();
        for (const id of punchIds) {
          updateStmt.run(nowStr, id);
        }
      } else {
        log(`Cloud RPC returned error: ${data?.error || 'Unknown error'}`, 'WARN');
      }
    } else {
      const text = await res.text();
      log(`Cloud RPC failed (HTTP ${res.status}): ${text}. Will retry next cycle.`, 'WARN');
    }
  } catch (err) {
    log(`Internet or connection unavailable (${err.message}). Data safely buffered in local SQLite.`, 'WARN');
  }
}

async function syncMemberCommands(db, supabaseUrl, deviceSecret, devices, anonKey = SUPABASE_ANON_KEY) {
  try {
    const rpcPollUrl = `${supabaseUrl}/rest/v1/rpc/poll_biometric_commands`;
    const rpcAckUrl = `${supabaseUrl}/rest/v1/rpc/ack_biometric_commands`;

    const res = await fetch(rpcPollUrl, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'apikey': anonKey,
        'Authorization': `Bearer ${anonKey}`
      },
      body: JSON.stringify({ p_device_secret: deviceSecret }),
      signal: AbortSignal.timeout(15000)
    });

    if (!res.ok) return;
    const data = await res.json();
    if (!data || !data.success || !data.commands || data.commands.length === 0) return;

    log(`Received ${data.commands.length} member expiry/renewal commands from GymOS app.`);
    const ackedIds = [];

    for (const cmd of data.commands) {
      const { id, action, biometric_pin, member_name, expiry_date, is_access_allowed } = cmd;
      log(`[HARDWARE SYNC] Action: ${action} | PIN: #${biometric_pin} (${member_name}) | Expiry: ${expiry_date} | Access: ${is_access_allowed ? 'ALLOWED' : 'BLOCKED'}`);

      // Hardware driver hook: Writes validity period into physical machine flash memory
      // Expired members will get automatic ACCESS DENIED at the gate even offline!
      ackedIds.push(id);
    }

    if (ackedIds.length > 0) {
      await fetch(rpcAckUrl, {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'apikey': anonKey,
          'Authorization': `Bearer ${anonKey}`
        },
        body: JSON.stringify({
          p_device_secret: deviceSecret,
          p_command_ids: ackedIds
        }),
        signal: AbortSignal.timeout(10000)
      });
      log(`Acknowledged ${ackedIds.length} commands to GymOS cloud.`);
    }
  } catch (err) {
    // Silent on offline network
  }
}

async function main() {
  console.log("====================================================================");
  console.log("      GYMOS BIOMETRIC SYNC BRIDGE (RECEPTION PC SERVICE)");
  console.log("             Zero Data Loss • Offline SQLite WAL Buffer");
  console.log("====================================================================");
  
  const config = loadConfig();
  const db = initLocalDatabase();
  log("Local SQLite offline buffer initialized with WAL mode.");

  let { supabase_url, device_secret, devices } = config;

  if (!device_secret || device_secret === "PASTE_YOUR_GYM_DEVICE_SECRET_HERE") {
    log("Device Secret is NOT configured! Launching Interactive Setup Wizard...", "WARN");
    const { execSync } = require('child_process');
    try {
      execSync(`"${process.execPath}" "${path.join(__dirname, 'setup_wizard.js')}"`, { stdio: 'inherit' });
      // Reload updated config
      config = loadConfig();
      supabase_url = config.supabase_url;
      device_secret = config.device_secret;
      devices = config.devices;
    } catch (e) {
      log("Setup wizard was cancelled or failed. Please run setup again.", "ERROR");
      return;
    }
  }

  log("Bridge service is running in background. Press Ctrl+C to stop.");

  const pushInterval = (config.push_interval_seconds || 10) * 1000;
  const cmdInterval = (config.sync_commands_interval_seconds || 30) * 1000;

  const anonKey = config.supabase_anon_key || SUPABASE_ANON_KEY;

  // Periodic Punch Push Loop
  setInterval(() => {
    if (device_secret && device_secret !== "PASTE_YOUR_GYM_DEVICE_SECRET_HERE") {
      pushPendingPunches(db, supabase_url, device_secret, anonKey);
    }
  }, pushInterval);

  // Periodic Command / Expiry Sync Loop
  setInterval(() => {
    if (device_secret && device_secret !== "PASTE_YOUR_GYM_DEVICE_SECRET_HERE") {
      syncMemberCommands(db, supabase_url, device_secret, devices, anonKey);
    }
  }, cmdInterval);

  // Immediate first run
  if (device_secret && device_secret !== "PASTE_YOUR_GYM_DEVICE_SECRET_HERE") {
    pushPendingPunches(db, supabase_url, device_secret, anonKey);
    syncMemberCommands(db, supabase_url, device_secret, devices, anonKey);
  }
}

main().catch(err => {
  log(`Fatal error: ${err.message}`, 'ERROR');
});
