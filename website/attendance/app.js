// ====================================================
// GYMOS ATTENDANCE DISPLAY WEB CLIENT - V3 PRODUCTION
// ====================================================

const SUPABASE_URL = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";

// Initialize Supabase Client
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const urlParams = new URLSearchParams(window.location.search);
let displayPublicId = urlParams.get('display_id');

// If not in query, check localStorage for last used display_id
const CACHED_DISPLAY_ID_KEY = 'gymos_last_display_id';
if (!displayPublicId) {
    const cachedId = localStorage.getItem(CACHED_DISPLAY_ID_KEY);
    if (cachedId && cachedId.trim().length > 0) {
        displayPublicId = cachedId.trim();
    }
}

let isVerified = false;
let heartbeatTimer = null;
let verificationQrInstance = null;
let currentMethod = null;
let qrValiditySeconds = 30;
let dynamicQrSecondsLeft = 0;
let dynamicQrInterval = null;

// UI Elements
const screenSetup = document.getElementById('screen-setup');
const screenUnverified = document.getElementById('screen-unverified');
const screenVerified = document.getElementById('screen-verified');
const setupInput = document.getElementById('setup-display-input');
const setupConnectBtn = document.getElementById('setup-connect-btn');
const switchDisplayBtn = document.getElementById('switch-display-btn');

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
    if (liveTimeText) {
        liveTimeText.textContent = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    }
}, 1000);

// Setup screen input listeners
if (setupConnectBtn && setupInput) {
    setupConnectBtn.addEventListener('click', handleManualSetup);
    setupInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') handleManualSetup();
    });
}

if (switchDisplayBtn) {
    switchDisplayBtn.addEventListener('click', () => {
        if (confirm("Disconnect this display session and enter a new Display ID?")) {
            localStorage.removeItem(CACHED_DISPLAY_ID_KEY);
            if (displayPublicId) {
                localStorage.removeItem(`gymos_display_secret_${displayPublicId}`);
            }
            window.location.href = window.location.pathname;
        }
    });
}

function handleManualSetup() {
    let raw = setupInput.value.trim();
    if (!raw) {
        alert("Please enter a valid Gym Display ID or paste your full Display link.");
        setupInput.focus();
        return;
    }

    // If pasted full URL (e.g. https://gymos.tech/attendance?display_id=xxx)
    try {
        if (raw.includes("display_id=")) {
            const parsedUrl = new URL(raw, window.location.origin);
            const extracted = parsedUrl.searchParams.get("display_id");
            if (extracted) raw = extracted;
        }
    } catch (_) {}

    displayPublicId = raw.trim();
    localStorage.setItem(CACHED_DISPLAY_ID_KEY, displayPublicId);

    // Update URL query string without reloading
    const newUrl = `${window.location.pathname}?display_id=${encodeURIComponent(displayPublicId)}`;
    window.history.replaceState({ path: newUrl }, '', newUrl);

    if (screenSetup) screenSetup.classList.add('hidden');
    initDisplayHandshake();
}

// Check initial parameters
if (!displayPublicId) {
    showSetupScreen();
} else {
    // Save valid id to cache
    localStorage.setItem(CACHED_DISPLAY_ID_KEY, displayPublicId);
    if (switchDisplayBtn) switchDisplayBtn.classList.remove('hidden');
    initDisplayHandshake();
}

function showSetupScreen() {
    updateConnectionStatus("Standby", "amber");
    if (screenSetup) screenSetup.classList.remove('hidden');
    if (screenUnverified) screenUnverified.classList.add('hidden');
    if (screenVerified) screenVerified.classList.add('hidden');
    if (switchDisplayBtn) switchDisplayBtn.classList.add('hidden');
    if (gymNameHeader) gymNameHeader.textContent = "Connect to your Gym";
    if (setupInput) setupInput.focus();
    lucide.createIcons();
}

function showError(message) {
    statusText.textContent = "Error";
    statusDot.className = "relative inline-flex rounded-full h-2 w-2 bg-red-500";
    statusPulse.className = "hidden";
    
    if (screenSetup) screenSetup.classList.add('hidden');
    if (screenVerified) screenVerified.classList.add('hidden');
    if (screenUnverified) {
        screenUnverified.classList.remove('hidden');
        screenUnverified.innerHTML = `
            <div class="w-20 h-20 bg-red-500/10 border border-red-500/20 rounded-full flex items-center justify-center text-red-500 mb-4">
                <i data-lucide="alert-triangle" class="w-10 h-10"></i>
            </div>
            <h2 class="text-2xl font-bold text-white mb-2">Display Error</h2>
            <p class="text-slate-400 text-sm mb-4">${message}</p>
            <div class="flex gap-3 justify-center">
                <button onclick="localStorage.removeItem('${CACHED_DISPLAY_ID_KEY}'); window.location.href=window.location.pathname;" 
                        class="px-4 py-2 bg-white/10 hover:bg-white/20 text-white rounded-xl text-xs font-semibold transition-all">
                    Enter New ID
                </button>
                <button onclick="location.reload();" 
                        class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-xl text-xs font-semibold transition-all">
                    Retry Connection
                </button>
            </div>
        `;
        lucide.createIcons();
    }
}

async function initDisplayHandshake() {
    try {
        if (!displayPublicId) {
            showSetupScreen();
            return;
        }

        updateConnectionStatus("Connecting...", "amber");

        const fingerprint = navigator.userAgent;
        const deviceName = navigator.platform || "Display Web Client";
        const secretStorageKey = `gymos_display_secret_${displayPublicId}`;
        const savedSecret = localStorage.getItem(secretStorageKey) || "";

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
                if (gymNameHeader) gymNameHeader.textContent = data.gym_name;
                if (gymNameTitle) gymNameTitle.textContent = data.gym_name;
            }

            if (switchDisplayBtn) switchDisplayBtn.classList.remove('hidden');

            if (data.status === 'VERIFIED') {
                // Save device secret securely in LocalStorage
                if (data.device_secret) {
                    localStorage.setItem(secretStorageKey, data.device_secret);
                }
                
                isVerified = true;
                if (displayIdVerifiedText) displayIdVerifiedText.textContent = displayPublicId;
                if (screenSetup) screenSetup.classList.add('hidden');
                if (screenUnverified) screenUnverified.classList.add('hidden');
                if (screenVerified) screenVerified.classList.remove('hidden');
                updateConnectionStatus("Active", "emerald");

                const secret = data.device_secret || savedSecret;

                // Immediately fetch QR on first load
                await fetchQrBasedOnSettings(secret);

                // Start 15s Heartbeat loop
                if (heartbeatTimer) clearInterval(heartbeatTimer);
                heartbeatTimer = setInterval(() => sendHeartbeat(secret), 15000);
            } 
            else if (data.status === 'WAITING_FOR_VERIFICATION') {
                isVerified = false;
                if (displayIdText) displayIdText.textContent = displayPublicId;
                if (screenSetup) screenSetup.classList.add('hidden');
                if (screenUnverified) screenUnverified.classList.remove('hidden');
                if (screenVerified) screenVerified.classList.add('hidden');
                updateConnectionStatus("Unverified", "amber");

                // Clear previous secret if server invalidated it
                localStorage.removeItem(secretStorageKey);

                // Render verification token in QR code
                renderVerificationQR(data.verification_token);

                // Poll status every 3 seconds while waiting for verification
                if (heartbeatTimer) clearInterval(heartbeatTimer);
                heartbeatTimer = setInterval(pollVerificationStatus, 3000);
            }
        } else {
            showError(data.reason || "Unable to register display device.");
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
            if (qrContainer) {
                qrContainer.innerHTML = `<div style="display:flex;align-items:center;justify-content:center;height:100%;width:100%;text-align:center;color:#ef4444;font-weight:bold;font-size:13px;background:#fef2f2;padding:8px;">
                    Error: ${data.reason || 'No token returned'}<br/>Please check database settings.
                </div>`;
            }
        }
    } catch (e) {
        console.error("Failed to fetch QR:", e);
        const qrContainer = document.getElementById("attendance-qrcode");
        if (qrContainer) {
            qrContainer.innerHTML = `<div style="display:flex;align-items:center;justify-content:center;height:100%;width:100%;text-align:center;color:#ef4444;font-weight:bold;font-size:13px;background:#fef2f2;padding:8px;">
                RPC Error: ${e.message || 'Unknown error'}<br/>Please check connection.
            </div>`;
        }
    }
}

async function pollVerificationStatus() {
    try {
        const { data, error } = await supabaseClient.rpc('check_display_verification_status', {
            p_public_id: displayPublicId
        });

        if (error) throw error;

        if (data && data.success && data.is_verified === true) {
            // Device was verified! Save secret and transition to active state.
            if (data.device_secret) {
                const secretStorageKey = `gymos_display_secret_${displayPublicId}`;
                localStorage.setItem(secretStorageKey, data.device_secret);
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
            
            if (newMethod) {
                const isDynamic = ['Dynamic QR', 'Dynamic QR + WiFi', 'QR Only', 'QR + WiFi'].includes(newMethod);
                const currentIsDynamic = currentMethod === 'Dynamic QR';
                
                if (isDynamic !== currentIsDynamic) {
                    console.log("Method changed to:", newMethod, "- re-fetching QR");
                    qrValiditySeconds = newValidity;
                    if (dynamicQrInterval) {
                        clearInterval(dynamicQrInterval);
                        dynamicQrInterval = null;
                    }
                    fetchQrBasedOnSettings(secret);
                } else if (isDynamic && newValidity !== qrValiditySeconds) {
                    qrValiditySeconds = newValidity;
                }
            }
        } else {
            console.warn("Heartbeat rejected:", data.reason);
            const secretStorageKey = `gymos_display_secret_${displayPublicId}`;
            localStorage.removeItem(secretStorageKey);
            location.reload();
        }
    } catch (e) {
        console.error("Heartbeat update failed:", e);
        updateConnectionStatus("Offline", "red");
    }
}

function renderVerificationQR(token) {
    if (!verificationQrContainer) return;
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
        textSpan.classList.remove("text-indigo-400");
        textSpan.classList.add("text-red-500", "animate-pulse");
    } else {
        textSpan.classList.add("text-indigo-400");
        textSpan.classList.remove("text-red-500", "animate-pulse");
    }
}

function renderAttendanceQr(token) {
    const qrContainer = document.getElementById("attendance-qrcode");
    if (!qrContainer) return;
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
    if (statusText) statusText.textContent = text;
    
    if (color === "emerald") {
        if (statusDot) statusDot.className = "relative inline-flex rounded-full h-2 w-2 bg-emerald-500";
        if (statusPulse) {
            statusPulse.className = "animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75";
            statusPulse.classList.remove('hidden');
        }
    } 
    else if (color === "amber") {
        if (statusDot) statusDot.className = "relative inline-flex rounded-full h-2 w-2 bg-amber-500";
        if (statusPulse) {
            statusPulse.className = "animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75";
            statusPulse.classList.remove('hidden');
        }
    } 
    else {
        if (statusDot) statusDot.className = "relative inline-flex rounded-full h-2 w-2 bg-red-500";
        if (statusPulse) statusPulse.className = "hidden";
    }
}
