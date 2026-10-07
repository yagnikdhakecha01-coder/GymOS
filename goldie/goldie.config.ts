const APP_ROOT = process.cwd();

const config = {
  appRoot: APP_ROOT,
  appPath: `${APP_ROOT}/GYMOS.apk`,
  bundleId: "com.gymos.fitness.app.v1",
  android: {
    appPath: `${APP_ROOT}/GYMOS.apk`,
    applicationId: "com.gymos.fitness.app.v1",
  },

  devices: ["pixel-10-pro"],
  locales: ["en-US"],
  appearance: "light",

  frame: {
    variant: {
      "iphone-6.9": "17-pro-blue",
    },
  },

  theme: {
    background: "linear-gradient(160deg, #0F172A 0%, #1E293B 45%, #0A0F1D 100%)",
    headlineColor: "#FFFFFF",
    subheadColor: "#94A3B8",
    fontFamily: '-apple-system, "SF Pro Display", system-ui, sans-serif',
    copyHeightRatio: 0.22,
    deviceWidthRatio: 0.86,
    template: "editorial",
    layout: "classic",
  },

  store: {
    name: "GymOS",
    subtitle: { "en-US": "Smart Gym & Fitness Management OS" },
    developer: "GymOS Technologies",
    category: "Health & Fitness",
    rating: 4.9,
    ratingCount: "2.4K Ratings",
    ageRating: "4+",
    price: "Free",
    description: {
      "en-US": "GymOS is the all-in-one operating system for gym owners, staff trainers, and fitness members. Automate membership billing, live attendance, workout routines, and financial analytics.",
    },
  },

  scenes: [
    {
      kind: "screenshot",
      id: "login",
      headline: { "en-US": "Welcome to GymOS: Fast & Secure Access" },
      subhead: { "en-US": "Seamless role-based sign in with Google or Email for owners, staff, and members." },
      layout: "hero",
    },
    {
      kind: "screenshot",
      id: "owner-dashboard",
      headline: { "en-US": "Owner Command Center: Full Control" },
      subhead: { "en-US": "Live revenue, active member count, quick actions, and daily metrics at a glance." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "owner-members",
      headline: { "en-US": "150+ Member Directory & Profiles" },
      subhead: { "en-US": "Instant member search, active plan status, expiry alerts, and direct contact." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "owner-finance",
      headline: { "en-US": "Financial Intelligence & Cash Flow" },
      subhead: { "en-US": "Track monthly collections, profit & loss graphs, and pending dues automatically." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "owner-staff",
      headline: { "en-US": "Staff & Trainer Management" },
      subhead: { "en-US": "Manage personal trainers, roles, attendance logs, and salary registers effortlessly." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "member-dashboard",
      headline: { "en-US": "Member Portal: Workouts & Streaks" },
      subhead: { "en-US": "Today's targeted training, quad focus workouts, streak counter, and diet plans." },
      layout: "hero",
    },
    {
      kind: "screenshot",
      id: "member-exercises",
      headline: { "en-US": "1300+ Animated Exercise Library" },
      subhead: { "en-US": "Target by muscle group & equipment with high-quality step-by-step form animations." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "member-attendance",
      headline: { "en-US": "Attendance & Check-In History" },
      subhead: { "en-US": "Interactive calendar with present, absent, and holiday logs plus monthly streak summary." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "packages-plans",
      headline: { "en-US": "Flexible Membership Packages" },
      subhead: { "en-US": "Customise monthly, quarterly, and annual tiers with instant admission setup." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "expenses-ledger",
      headline: { "en-US": "Expenses & Transactions Ledger" },
      subhead: { "en-US": "Log gym expenses, maintenance costs, and incoming membership payments in real-time." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "reports-analytics",
      headline: { "en-US": "Business Analytics & Growth Reports" },
      subhead: { "en-US": "Comprehensive revenue trends, attendance patterns, and membership growth insights." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "gym-settings",
      headline: { "en-US": "Complete Gym Customization" },
      subhead: { "en-US": "Tailor profile settings, WhatsApp templates, biometric gates, and billing rules." },
      layout: "classic",
    },
  ],
};

export default config;
