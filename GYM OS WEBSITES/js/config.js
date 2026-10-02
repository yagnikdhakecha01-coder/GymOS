// ── GYMOS WEBSITES SUPABASE CONFIG ──

const GYMOS_CONFIG = {
  SUPABASE_URL: "https://gilxxyvwqucwwwqaxosx.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP",
  QR_SESSION_TTL_SECONDS: 90,
  APP_VERSION: "1.0.9 (Web)",
  ROUTES: {
    LOGIN: "/index.html",
    OWNER_DASHBOARD: "/dashboard/owner/index.html",
    TRAINER_DASHBOARD: "/dashboard/trainer/index.html",
    RECEPTIONIST_DASHBOARD: "/dashboard/receptionist/index.html",
    MEMBER_DASHBOARD: "/dashboard/member/index.html",
    VERIFY_MOBILE: "/verify.html"
  }
};

// Initialize Supabase Client
var supabaseClient = window.supabase.createClient(
  GYMOS_CONFIG.SUPABASE_URL,
  GYMOS_CONFIG.SUPABASE_ANON_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true
    },
    realtime: {
      params: {
        eventsPerSecond: 10
      }
    }
  }
);
window.supabaseClient = supabaseClient;

