// ── WHATSAPP WEB STYLE QR AUTHENTICATION ENGINE ──

class GymOSQRAuth {
  constructor() {
    this.sessionToken = null;
    this.sessionId = null;
    this.realtimeChannel = null;
    this.countdownTimer = null;
    this.timeLeft = GYMOS_CONFIG.QR_SESSION_TTL_SECONDS;
    
    this.qrContainer = document.getElementById('qr-canvas-container');
    this.qrOverlay = document.getElementById('qr-overlay');
    this.statusPill = document.getElementById('qr-status');
    this.statusDot = document.getElementById('status-dot');
    this.timerEl = document.getElementById('timer-count');
    this.refreshBtn = document.getElementById('btn-refresh-qr');
  }

  async init() {
    // If already logged in, check session validity
    const existing = this.getStoredSession();
    if (existing && existing.role) {
      console.log('Active session detected. Routing to dashboard...');
      this.routeToDashboard(existing.role);
      return;
    }

    if (this.refreshBtn) {
      this.refreshBtn.addEventListener('click', () => this.generateNewSession());
    }

    await this.generateNewSession();
  }

  getStoredSession() {
    try {
      const data = localStorage.getItem('gymos_web_session');
      return data ? JSON.parse(data) : null;
    } catch (e) {
      return null;
    }
  }

  generateToken() {
    return 'gos_' + Array.from(crypto.getRandomValues(new Uint8Array(20)))
      .map(b => b.toString(16).padStart(2, '0')).join('');
  }

  async generateNewSession() {
    clearInterval(this.countdownTimer);
    if (this.realtimeChannel) {
      await supabaseClient.removeChannel(this.realtimeChannel);
    }

    this.qrOverlay.classList.remove('active');
    this.statusPill.innerHTML = '<span class="status-dot" id="status-dot"></span> Point phone camera to scan';
    this.timeLeft = GYMOS_CONFIG.QR_SESSION_TTL_SECONDS;
    this.updateTimerDisplay();

    this.sessionToken = this.generateToken();

    try {
      // 1. Insert pending session in Supabase
      const expiresAt = new Date(Date.now() + (GYMOS_CONFIG.QR_SESSION_TTL_SECONDS * 1000)).toISOString();
      
      const { data, error } = await supabaseClient
        .from('web_login_sessions')
        .insert([{
          session_token: this.sessionToken,
          status: 'pending',
          expires_at: expiresAt
        }])
        .select()
        .single();

      if (error) throw error;
      this.sessionId = data.id;

      // 2. Render QR code
      this.renderQRCode(this.sessionToken);

      // 3. Attach Realtime listener
      this.listenForApproval();

      // 4. Start countdown
      this.startCountdown();

    } catch (err) {
      console.error('Failed to create web login session:', err);
      this.statusPill.innerText = 'Connection error. Click refresh.';
      this.qrOverlay.classList.add('active');
    }
  }

  renderQRCode(token) {
    this.qrContainer.innerHTML = '';
    
    // Construct the mobile verification URL
    // When scanned by phone camera, it opens the GymOS verification webpage
    const currentOrigin = window.location.origin;
    const currentPath = window.location.pathname.substring(0, window.location.pathname.lastIndexOf('/'));
    const verifyUrl = `${currentOrigin}${currentPath}/verify.html?token=${token}`;

    new QRCode(this.qrContainer, {
      text: verifyUrl,
      width: 230,
      height: 230,
      colorDark: "#111827",
      colorLight: "#FFFFFF",
      correctLevel: QRCode.CorrectLevel.H
    });

    console.log('QR Code generated. Verification URL:', verifyUrl);
  }

  listenForApproval() {
    this.realtimeChannel = supabaseClient
      .channel(`session-${this.sessionToken}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'web_login_sessions',
          filter: `session_token=eq.${this.sessionToken}`
        },
        async (payload) => {
          console.log('Realtime session update received:', payload);
          if (payload.new && (payload.new.status === 'approved' || payload.new.status === 'consumed')) {
            await this.handleSessionApproved(payload.new);
          }
        }
      )
      .subscribe((status) => {
        console.log('Supabase Realtime subscription status:', status);
      });
  }

  async handleSessionApproved(sessionData) {
    clearInterval(this.countdownTimer);
    
    this.statusPill.innerHTML = '<span class="status-dot approved"></span> Verified! Logging you in...';
    this.statusPill.style.color = 'var(--success)';

    try {
      // Consume the session via RPC
      const { data: result, error } = await supabaseClient.rpc('consume_web_login_session', {
        p_session_token: this.sessionToken
      });

      if (error) {
        console.warn('RPC consume warning, using sessionData directly:', error);
      }

      const activeRole = (result && result.role) ? result.role : (sessionData.role || 'owner');
      const activeGymId = (result && result.gym_id) ? result.gym_id : sessionData.gym_id;
      const activeUserId = (result && result.user_id) ? result.user_id : sessionData.user_id;
      const userMeta = (result && result.user_metadata) ? result.user_metadata : (sessionData.user_metadata || {});

      // Store in LocalStorage
      const sessionObj = {
        token: this.sessionToken,
        role: activeRole,
        gym_id: activeGymId,
        user_id: activeUserId,
        metadata: userMeta,
        login_time: new Date().toISOString()
      };
      localStorage.setItem('gymos_web_session', JSON.stringify(sessionObj));

      // Success feedback animation then redirect
      setTimeout(() => {
        this.routeToDashboard(activeRole);
      }, 700);

    } catch (err) {
      console.error('Error establishing session:', err);
    }
  }

  startCountdown() {
    this.countdownTimer = setInterval(() => {
      this.timeLeft -= 1;
      this.updateTimerDisplay();

      if (this.timeLeft <= 0) {
        clearInterval(this.countdownTimer);
        this.qrOverlay.classList.add('active');
        this.statusPill.innerText = 'QR Code Expired';
      }
    }, 1000);
  }

  updateTimerDisplay() {
    if (this.timerEl) {
      const mins = Math.floor(this.timeLeft / 60);
      const secs = (this.timeLeft % 60).toString().padStart(2, '0');
      this.timerEl.innerText = `${mins}:${secs}`;
    }
  }

  routeToDashboard(role) {
    const currentOrigin = window.location.origin;
    const currentPath = window.location.pathname.substring(0, window.location.pathname.lastIndexOf('/'));
    
    switch (role) {
      case 'owner':
        window.location.href = `${currentOrigin}${currentPath}/dashboard/owner/index.html`;
        break;
      case 'trainer':
        window.location.href = `${currentOrigin}${currentPath}/dashboard/trainer/index.html`;
        break;
      case 'receptionist':
        window.location.href = `${currentOrigin}${currentPath}/dashboard/receptionist/index.html`;
        break;
      case 'member':
        window.location.href = `${currentOrigin}${currentPath}/dashboard/member/index.html`;
        break;
      default:
        window.location.href = `${currentOrigin}${currentPath}/dashboard/owner/index.html`;
        break;
    }
  }

  // Simulator for instant testing without scanning physically
  async simulateScan(role) {
    if (!this.sessionToken) return;
    
    // Find an actual gym_id from database if available
    let gymId = null;
    let userId = null;
    try {
      const { data: gym } = await supabaseClient.from('gyms').select('id, owner_id').limit(1).single();
      if (gym) {
        gymId = gym.id;
        userId = gym.owner_id;
      }
    } catch(e) {}

    const { data, error } = await supabaseClient.rpc('approve_web_login_session', {
      p_session_token: this.sessionToken,
      p_user_id: userId || '00000000-0000-0000-0000-000000000001',
      p_gym_id: gymId || '00000000-0000-0000-0000-000000000001',
      p_role: role,
      p_metadata: {
        gym_name: "GymOS Elite Fitness",
        user_name: role === 'owner' ? 'Gym Owner' : (role === 'trainer' ? 'Vikram Trainer' : (role === 'receptionist' ? 'Pooja Front Desk' : 'Rahul Member')),
        simulated: true
      }
    });

    if (error) {
      console.error('Simulation error:', error);
      alert('Error simulating scan: ' + error.message);
    } else {
      console.log(`Simulated ${role} approval success! Redirecting...`);
      await this.handleSessionApproved({
        role: role,
        gym_id: gymId || '00000000-0000-0000-0000-000000000001',
        user_id: userId || '00000000-0000-0000-0000-000000000001',
        user_metadata: {
          gym_name: "GymOS Elite Fitness",
          user_name: role === 'owner' ? 'Gym Owner' : (role === 'trainer' ? 'Vikram Trainer' : (role === 'receptionist' ? 'Pooja Front Desk' : 'Rahul Member')),
          simulated: true
        }
      });
    }
  }
}

// Instantiate on load
document.addEventListener('DOMContentLoaded', () => {
  window.qrAuth = new GymOSQRAuth();
  window.qrAuth.init();
});
