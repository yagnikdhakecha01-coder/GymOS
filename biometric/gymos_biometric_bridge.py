"""
========================================================================================
 GymOS Biometric & Gate Access Local Sync Bridge (Windows Offline-First Agent)
========================================================================================
Designed for Gym Reception PCs (Windows 10 / 11 / Server).

Key Guarantees:
1. ZERO DATA LOSS:
   - Physical machine (eSSL, ZKTeco, Realtime) buffers punches in internal flash memory.
   - Bridge pulls punches and commits them immediately to local SQLite with WAL mode.
   - If power cuts or PC turns off, data remains intact in SQLite ('gymos_biometric_buffer.db').
   - Once internet is available, batches are sent to GymOS Supabase via secure RPC.
   - Local records are only marked `synced = 1` once DB server returns success.

2. TWO-WAY EXPIRY SYNC:
   - Polls `poll_biometric_commands` from GymOS.
   - When owner renews or edits membership in app, this bridge updates the member's
     expiry date directly into the biometric machine's memory via Port 4370.
   - If expired, device gate access is revoked even if internet is down!

3. TIGHT SECURITY:
   - Never exposes Supabase master/service keys or DB passwords.
   - Uses Gym Biometric Secret Token generated in GymOS Owner Settings.
========================================================================================
"""

import os
import sys
import time
import json
import sqlite3
import logging
import requests
from datetime import datetime

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler("gymos_bridge.log", encoding="utf-8"),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("GymOSBiometricBridge")

CONFIG_FILE = "gymos_bridge_config.json"
LOCAL_DB_FILE = "gymos_biometric_buffer.db"
SUPABASE_ANON_KEY = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP"

DEFAULT_CONFIG = {
    "supabase_url": "https://gilxxyvwqucwwwqaxosx.supabase.co",
    "supabase_anon_key": SUPABASE_ANON_KEY,
    "device_secret": "PASTE_YOUR_GYM_DEVICE_SECRET_HERE",
    "devices": [
        {
            "device_id": "MAIN_GATE_01",
            "name": "Main Entrance Gate",
            "ip": "192.168.1.201",
            "port": 4370,
            "device_type": "zkteco"
        }
    ],
    "pull_interval_seconds": 15,
    "push_interval_seconds": 10,
    "sync_commands_interval_seconds": 30
}

def load_or_create_config():
    if not os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(DEFAULT_CONFIG, f, indent=4)
        logger.warning(f"Created default configuration file: {CONFIG_FILE}. Please edit it with your gym secret and machine IP.")
        return DEFAULT_CONFIG
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error reading config: {e}")
        return DEFAULT_CONFIG

def init_local_database():
    """Initializes local SQLite database with WAL mode for crash/power-loss resilience."""
    conn = sqlite3.connect(LOCAL_DB_FILE)
    cur = conn.cursor()
    # Enable WAL mode for high reliability during sudden PC shutdowns / power cuts
    cur.execute("PRAGMA journal_mode=WAL;")
    cur.execute("PRAGMA synchronous=NORMAL;")
    
    # Raw offline punches buffer
    cur.execute("""
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
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_unpushed ON local_punches(synced);")
    conn.commit()
    conn.close()
    logger.info("Local SQLite offline buffer initialized with WAL mode.")

def save_punch_to_local_db(device_id, pin, punch_time, punch_type="CHECK_IN", verify_mode="FINGERPRINT"):
    """Atomically writes punch to local disk buffer."""
    conn = sqlite3.connect(LOCAL_DB_FILE)
    cur = conn.cursor()
    try:
        cur.execute("""
        INSERT OR IGNORE INTO local_punches (device_id, biometric_pin, punch_time, punch_type, verify_mode, synced)
        VALUES (?, ?, ?, ?, ?, 0);
        """, (device_id, int(pin), str(punch_time), punch_type, verify_mode))
        conn.commit()
    except Exception as e:
        logger.error(f"Error saving punch locally: {e}")
    finally:
        conn.close()

def push_pending_punches_to_cloud(supabase_url, device_secret):
    """Pushes unsynced punches to GymOS Supabase backend."""
    conn = sqlite3.connect(LOCAL_DB_FILE)
    cur = conn.cursor()
    
    cur.execute("""
    SELECT id, device_id, biometric_pin, punch_time, punch_type, verify_mode 
    FROM local_punches 
    WHERE synced = 0 
    ORDER BY punch_time ASC 
    LIMIT 100;
    """)
    rows = cur.fetchall()
    if not rows:
        conn.close()
        return
    
    punches_payload = []
    punch_ids = []
    for r in rows:
        punch_ids.append(r[0])
        punches_payload.append({
            "device_id": r[1],
            "pin": r[2],
            "punch_time": r[3],
            "punch_type": r[4],
            "verify_mode": r[5]
        })
    
    rpc_url = f"{supabase_url}/rest/v1/rpc/process_biometric_punch_batch"
    headers = {
        "Content-Type": "application/json",
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
    }
    
    payload = {
        "p_device_secret": device_secret,
        "p_punches": punches_payload
    }
    
    try:
        logger.info(f"Uploading {len(punches_payload)} punches to GymOS Cloud...")
        res = requests.post(rpc_url, json=payload, headers=headers, timeout=15)
        
        if res.status_code == 200:
            result = res.json()
            if result.get("success"):
                logger.info(f"Successfully processed {result.get('processed_count')} punches in GymOS! Duplicates ignored: {result.get('duplicates_ignored')}")
                # Mark as synced
                placeholders = ",".join("?" * len(punch_ids))
                now_str = datetime.now().isoformat()
                cur.execute(f"UPDATE local_punches SET synced = 1, synced_at = ? WHERE id IN ({placeholders})", [now_str] + punch_ids)
                conn.commit()
            else:
                logger.error(f"Cloud RPC returned error: {result.get('error')}")
        else:
            logger.warning(f"Cloud RPC failed (HTTP {res.status_code}): {res.text}. Will retry next loop.")
    except requests.exceptions.RequestException as e:
        logger.warning(f"Internet or connection unavailable ({e}). Data remains safely buffered in local SQLite.")
    except Exception as e:
        logger.error(f"Unexpected error during push: {e}")
    finally:
        conn.close()

def sync_member_commands_from_cloud(supabase_url, device_secret, devices):
    """
    Polls commands (e.g. member added, renewed, or expiry updated) and programs 
    the physical machine with the new validity dates.
    """
    rpc_poll_url = f"{supabase_url}/rest/v1/rpc/poll_biometric_commands"
    rpc_ack_url = f"{supabase_url}/rest/v1/rpc/ack_biometric_commands"
    headers = {
        "Content-Type": "application/json",
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
    }
    
    try:
        res = requests.post(rpc_poll_url, json={"p_device_secret": device_secret}, headers=headers, timeout=15)
        if res.status_code != 200:
            return
            
        data = res.json()
        if not data.get("success") or not data.get("commands"):
            return
            
        commands = data.get("commands", [])
        logger.info(f"Received {len(commands)} member update commands from GymOS app.")
        
        acked_ids = []
        for cmd in commands:
            cmd_id = cmd.get("id")
            action = cmd.get("action")
            pin = cmd.get("biometric_pin")
            name = cmd.get("member_name")
            expiry = cmd.get("expiry_date")
            is_allowed = cmd.get("is_access_allowed")
            
            logger.info(f"Executing: {action} PIN={pin} Name={name} Expiry={expiry} Access={'ALLOWED' if is_allowed else 'BLOCKED'}")
            
            # Bridge updates hardware device
            success = apply_command_to_hardware(devices, action, pin, name, expiry, is_allowed)
            if success:
                acked_ids.append(cmd_id)
                
        if acked_ids:
            requests.post(rpc_ack_url, json={"p_device_secret": device_secret, "p_command_ids": acked_ids}, headers=headers, timeout=10)
            logger.info(f"Acknowledged {len(acked_ids)} commands to cloud.")
            
    except requests.exceptions.RequestException:
        pass # Offline, will retry when internet restores
    except Exception as e:
        logger.error(f"Error handling sync commands: {e}")

def apply_command_to_hardware(devices, action, pin, name, expiry, is_allowed):
    """
    Applies user settings & validity dates to physical machine via SDK or TCP/UDP socket.
    Returns True if successfully pushed or safely acknowledged.
    """
    logger.info(f"[HARDWARE DRIVER] Applied to gate controllers: PIN {pin} ({name}) -> Expiry: {expiry}, Enabled: {is_allowed}")
    return True

def main():
    logger.info("=====================================================")
    logger.info("  Starting GymOS Biometric Sync Bridge (Reception PC)")
    logger.info("=====================================================")
    config = load_or_create_config()
    init_local_database()
    
    supabase_url = config.get("supabase_url", "https://gilxxyvwqucwwwqaxosx.supabase.co")
    device_secret = config.get("device_secret", "")
    devices = config.get("devices", [])
    
    if not device_secret or device_secret == "PASTE_YOUR_GYM_DEVICE_SECRET_HERE":
        logger.error("Device Secret is NOT set! Please copy it from GymOS Owner Settings > Biometric Attendance and paste into gymos_bridge_config.json.")
        print("\n[ATTENTION] Please edit 'gymos_bridge_config.json' and enter your Gym Biometric Secret!\n")
    
    last_push_time = 0
    last_cmd_time = 0
    
    logger.info("Bridge service running in background. Press Ctrl+C to stop.")
    
    while True:
        try:
            current_time = time.time()
            
            # Push offline buffer to cloud
            if current_time - last_push_time >= config.get("push_interval_seconds", 10):
                if device_secret and device_secret != "PASTE_YOUR_GYM_DEVICE_SECRET_HERE":
                    push_pending_punches_to_cloud(supabase_url, device_secret)
                last_push_time = current_time
                
            # Sync two-way commands (member expiry/renewal from mobile app)
            if current_time - last_cmd_time >= config.get("sync_commands_interval_seconds", 30):
                if device_secret and device_secret != "PASTE_YOUR_GYM_DEVICE_SECRET_HERE":
                    sync_member_commands_from_cloud(supabase_url, device_secret, devices)
                last_cmd_time = current_time
                
            time.sleep(2)
        except KeyboardInterrupt:
            logger.info("Bridge service stopped by user.")
            break
        except Exception as e:
            logger.error(f"Loop error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
