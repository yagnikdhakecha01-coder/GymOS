// ====================================================
// GYMOS ATTENDANCE DISPLAY WEBSITE JS - V2 FIXED
// ====================================================

const SUPABASE_URL = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";

// Initialize Supabase Client
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const urlParams = new URLSearchParams(window.location.search);
const displayPublicId = urlParams.get('display_id');

let isVerified = false;
let heartbeatTimer = null;
let verificationQrInstance = null;
let currentMethod = null;
let qrValiditySeconds = 30;
let dynamicQrSecondsLeft = 0;
let dynamicQrInterval = null;

// LocalStorage Keys
const SECRET_STORAGE_KEY = `gymos_display_secret_${displayPublicId}`;

// UI Elements
const screenUnverified = document.getElementById('screen-unverified');
const screenVerified = document.getElementById('screen-verified');
const displayIdText = document.getElementById('display-id-text');
const displayIdVerifiedText = document.getElementById('display-id-verified');
const gymNameHeader = document.getElementById('gym-name-header');
const gymNameTitle = document.getElementById('gym-name-title');
const statusText = document.getElementById('status-text');
const statusDot = document.getElementById('status-dot');
const statusPulse = document.getElementById('status-pulse');
const liveTimeText = document.getElementById('live-time');
const verificationQrContainer = document.getElementById("verification-qrcode");

// Initialize Lucide Icons
lucide.createIcons();

// Live Clock
setInterval(() => {
    const now = new Date();
    liveTimeText.textContent = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}, 1000);

// Check URL Params
if (!displayPublicId) {
    showError("Missing Display Link Parameter. Format should end with '?display_id=YOUR_PUBLIC_ID'");
} else {
    initDisplayHandshake();
}

function showError(message) {
    statusText.textContent = "Error";
    statusDot.className = "relative inline-flex rounded-full h-2 w-2 bg-red-500";
    statusPulse.className = "hidden";
    
    screenUnverified.innerHTML = `
        <div class="w-20 h-20 bg-red-500/10 border border-red-500/20 rounded-full flex items-center justify-center text-red-500 mb-4">
            <i data-lucide="alert-triangle" class="w-10 h-10"></i>
        </div>
        <h2 class="text-2xl font-bold text-white mb-2">Configuration Error</h2>
        <p class="text-slate-400 text-sm mb-4">${message}</p>
        <p class="text-xs text-slate-500">Access display using a permanent URL from the Owner Settings.</p>
    `;
    lucide.createIcons();
}

async function initDisplayHandshake() {
    try {
        updateConnectionStatus("Connecting...", "amber");

        const fingerprint = navigator.userAgent;
        const deviceName = navigator.platform;
        const savedSecret = localStorage.getItem(SECRET_STORAGE_KEY) || "";

        // Handshake RPC
        const { data, error } = await supabaseClient.rpc('register_display_link', {
            p_public_id: displayPublicId,
            p_fingerprint: fingerprint,
            p_device_name: deviceName,
            p_secret: savedSecret
        });

        if (error) {
            console.error("RPC register_display_link error:", error);
            throw error;
        }

        console.log("Handshake response:", JSON.stringify(data));

        if (data.success) {
            // Set Gym Names
            if (data.gym_name) {
                gymNameHeader.textContent = data.gym_name;
                gymNameTitle.textContent = data.gym_name;
            }

            if (data.status === 'VERIFIED') {
                // Save device secret securely in LocalStorage
                if (data.device_secret) {
                    localStorage.setItem(SECRET_STORAGE_KEY, data.device_secret);
                }
                
                isVerified = true;
                displayIdVerifiedText.textContent = displayPublicId;
                screenUnverified.classList.add('hidden');
                screenVerified.classList.remove('hidden');
                updateConnectionStatus("Active", "emerald");

                const secret = data.device_secret || savedSecret;

                // Immediately fetch QR on first load (don't wait for heartbeat)
                await fetchQrBasedOnSettings(secret);

                // Start 15s Heartbeat loop (faster than before for real-time settings sync)
                if (heartbeatTimer) clearInterval(heartbeatTimer);
                heartbeatTimer = setInterval(() => sendHeartbeat(secret), 15000);
            } 
            else if (data.status === 'WAITING_FOR_VERIFICATION') {
                isVerified = false;
                displayIdText.textContent = displayPublicId;
                screenUnverified.classList.remove('hidden');
                screenVerified.classList.add('hidden');
                updateConnectionStatus("Unverified", "amber");

                // Clear previous secret if server invalidated it
                localStorage.removeItem(SECRET_STORAGE_KEY);

                // Render verification token in QR code
                renderVerificationQR(data.verification_token);

                // Poll status every 3 seconds while waiting for verification
                if (heartbeatTimer) clearInterval(heartbeatTimer);
                heartbeatTimer = setInterval(pollVerificationStatus, 3000);
            }
        } else {
            showError(data.reason || "Unable to load display registration configuration.");
        }
    } catch (e) {
        console.error("Registration error:", e);
        updateConnectionStatus("Offline", "red");
        setTimeout(initDisplayHandshake, 5000); // Retry handshake after 5 seconds
    }
}

async function fetchQrBasedOnSettings(secret) {
    try {
        const { data, error } = await supabaseClient.rpc('get_display_static_qr', {
            p_display_public_id: displayPublicId,
            p_secret: secret
        });

        if (error) {
            console.error("RPC get_display_static_qr error:", error);
            throw error;
        }

        console.log("QR fetch response:", JSON.stringify(data));

        if (data.success && data.static_qr_token) {
            renderAttendanceQr(data.static_qr_token);

            // Determine if this is dynamic or static based on response
            if (data.qr_type === 'Dynamic') {
                currentMethod = 'Dynamic QR';
                qrValiditySeconds = data.expires_in_seconds || 30;

                // Show timer
                const timerContainer = document.getElementById("dynamic-timer-container");
                if (timerContainer) timerContainer.classList.remove("hidden");

                // Start countdown
                dynamicQrSecondsLeft = qrValiditySeconds;
                updateTimerUI();

                if (dynamicQrInterval) clearInterval(dynamicQrInterval);
                dynamicQrInterval = setInterval(() => {
                    dynamicQrSecondsLeft--;
                    updateTimerUI();
                    
                    if (dynamicQrSecondsLeft <= 0) {
                        clearInterval(dynamicQrInterval);
                        dynamicQrInterval = null;
                        fetchQrBasedOnSettings(secret);
                    }
                }, 1000);
            } else {
                currentMethod = 'Static QR';
                // Hide timer for static
                const timerContainer = document.getElementById("dynamic-timer-container");
                if (timerContainer) timerContainer.classList.add("hidden");
                
                // Clear any running dynamic interval
                if (dynamicQrInterval) {
                    clearInterval(dynamicQrInterval);
                    dynamicQrInterval = null;
                }
            }
        } else {
            console.error("QR fetch failed:", data.reason);
            const qrContainer = document.getElementById("attendance-qrcode");
            qrContainer.innerHTML = `<div style="display:flex;align-items:center;justify-content:center;height:100%;width:100%;text-align:center;color:#ef4444;font-weight:bold;font-size:13px;background:#fef2f2;padding:8px;">
                Error: ${data.reason || 'No token returned'}<br/>Please check database settings.
            </div>`;
        }
    } catch (e) {
        console.error("Failed to fetch QR:", e);
        const qrContainer = document.getElementById("attendance-qrcode");
        qrContainer.innerHTML = `<div style="display:flex;align-items:center;justify-content:center;height:100%;width:100%;text-align:center;color:#ef4444;font-weight:bold;font-size:13px;background:#fef2f2;padding:8px;">
            RPC Error: ${e.message || 'Unknown error'}<br/>Run the SQL update in Supabase.
        </div>`;
    }
}

async function pollVerificationStatus() {
    // Use lightweight RPC to check status - does NOT regenerate tokens
    try {
        const { data, error } = await supabaseClient.rpc('check_display_verification_status', {
            p_public_id: displayPublicId
        });

        if (error) throw error;

        if (data && data.success && data.is_verified === true) {
            // Device was verified! Save secret and transition to active state.
            if (data.device_secret) {
                localStorage.setItem(SECRET_STORAGE_KEY, data.device_secret);
            }
            clearInterval(heartbeatTimer);
            initDisplayHandshake(); // Re-run handshake to transition to verified state
        }
    } catch (e) {
        console.error("Polling status error:", e);
    }
}

async function sendHeartbeat(secret) {
    try {
        const { data, error } = await supabaseClient.rpc('send_display_heartbeat', {
            p_public_id: displayPublicId,
            p_secret: secret
        });

        if (error) {
            console.error("Heartbeat RPC error:", error);
            throw error;
        }

        console.log("Heartbeat response:", JSON.stringify(data));

        if (data.success) {
            if (!data.is_enabled) {
                // If display is disabled by owner, reload/force re-verification
                location.reload();
            }
            updateConnectionStatus("Active", "emerald");
            
            // Check if method changed from heartbeat response
            const newMethod = data.method || null;
            const newValidity = data.qr_validity_seconds || 30;
            
            // If heartbeat returns method info (updated SQL), use it to detect changes
            if (newMethod) {
                const isDynamic = ['Dynamic QR', 'Dynamic QR + WiFi', 'QR Only', 'QR + WiFi'].includes(newMethod);
                const currentIsDynamic = currentMethod === 'Dynamic QR';
                
                if (isDynamic !== currentIsDynamic) {
                    // Method changed! Re-fetch QR
                    console.log("Method changed to:", newMethod, "- re-fetching QR");
                    qrValiditySeconds = newValidity;
                    if (dynamicQrInterval) {
                        clearInterval(dynamicQrInterval);
                        dynamicQrInterval = null;
                    }
                    fetchQrBasedOnSettings(secret);
                } else if (isDynamic && newValidity !== qrValiditySeconds) {
                    // Validity time changed
                    qrValiditySeconds = newValidity;
                }
            }
        } else {
            // Heartbeat rejected (secret mismatch / revoked), force reload
            console.warn("Heartbeat rejected:", data.reason);
            localStorage.removeItem(SECRET_STORAGE_KEY);
            location.reload();
        }
    } catch (e) {
        console.error("Heartbeat update failed:", e);
        updateConnectionStatus("Offline", "red");
    }
}

function renderVerificationQR(token) {
    verificationQrContainer.innerHTML = "";
    verificationQrInstance = new QRCode(verificationQrContainer, {
        text: token,
        width: 160,
        height: 160,
        colorDark: "#000000",
        colorLight: "#ffffff",
        correctLevel: QRCode.CorrectLevel.H
    });
}

function updateTimerUI() {
    const textSpan = document.getElementById("dynamic-timer-text");
    if (!textSpan) return;
    
    textSpan.textContent = dynamicQrSecondsLeft;
    if (dynamicQrSecondsLeft <= 5) {
        textSpan.classList.remove("text-brand-500");
        textSpan.classList.add("text-red-500", "animate-pulse");
    } else {
        textSpan.classList.add("text-brand-500");
        textSpan.classList.remove("text-red-500", "animate-pulse");
    }
}

function renderAttendanceQr(token) {
    const qrContainer = document.getElementById("attendance-qrcode");
    qrContainer.innerHTML = "";
    new QRCode(qrContainer, {
        text: token,
        width: 200,
        height: 200,
        colorDark: "#000000",
        colorLight: "#ffffff",
        correctLevel: QRCode.CorrectLevel.H
    });
}

function updateConnectionStatus(text, color) {
    statusText.textContent = text;
    
    // Emerald / Green
    if (color === "emerald") {
        statusDot.className = "relative inline-flex rounded-full h-2 w-2 bg-emerald-500";
        statusPulse.className = "animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75";
        statusPulse.classList.remove('hidden');
    } 
    // Amber / Yellow
    else if (color === "amber") {
        statusDot.className = "relative inline-flex rounded-full h-2 w-2 bg-amber-500";
        statusPulse.className = "animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75";
        statusPulse.classList.remove('hidden');
    } 
    // Red / Offline
    else {
        statusDot.className = "relative inline-flex rounded-full h-2 w-2 bg-red-500";
        statusPulse.className = "hidden";
    }
}
