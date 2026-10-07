const APP_ROOT = process.cwd();

const config = {
  appRoot: APP_ROOT,
  appPath: `${APP_ROOT}/build/ios/iphonesimulator/Runner.app`,
  bundleId: "com.jenishvora.gymosv1",

  devices: ["iphone-6.9", "ipad-13"],
  locales: ["en-US"],
  appearance: "light",

  frame: {
    variant: {
      "iphone-6.9": "17-pro-blue",
      "ipad-13": "ipad-pro-13-space-gray",
    },
  },

  theme: {
    background: "linear-gradient(160deg, #0F172A 0%, #1E293B 45%, #0A0F1D 100%)",
    headlineColor: "#FFFFFF",
    subheadColor: "#94A3B8",
    fontFamily: '-apple-system, "SF Pro Display", system-ui, sans-serif',
    copyHeightRatio: 0.22,
    deviceWidthRatio: 0.86,
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
      headline: { "en-US": "Tailored for Owners, Staff & Members" },
      subhead: { "en-US": "Choose your experience — dedicated portals for gym owners, trainers, and fitness members." },
    },
    {
      kind: "screenshot",
      id: "owner-dashboard",
      headline: { "en-US": "Owner Command Center: Full Control" },
      subhead: { "en-US": "Live revenue, active member count, quick actions, and daily metrics at a glance." },
    },
    {
      kind: "screenshot",
      id: "owner-members",
      headline: { "en-US": "150+ Member Directory & Profiles" },
      subhead: { "en-US": "Instant member search, active plan status, expiry alerts, and direct contact." },
    },
    {
      kind: "screenshot",
      id: "owner-finance",
      headline: { "en-US": "Financial Intelligence & Cash Flow" },
      subhead: { "en-US": "Track monthly collections, profit & loss graphs, and pending dues automatically." },
    },
    {
      kind: "screenshot",
      id: "owner-staff",
      headline: { "en-US": "Staff & Trainer Management" },
      subhead: { "en-US": "Manage personal trainers, roles, attendance logs, and salary registers effortlessly." },
    },
    {
      kind: "screenshot",
      id: "member-dashboard",
      headline: { "en-US": "Member Portal: Workouts & Streaks" },
      subhead: { "en-US": "Today's targeted training, quad focus workouts, streak counter, and diet plans." },
    },
    {
      kind: "screenshot",
      id: "member-exercises",
      headline: { "en-US": "1300+ Animated Exercise Library" },
      subhead: { "en-US": "Target by muscle group & equipment with high-quality step-by-step form animations." },
    },
    {
      kind: "screenshot",
      id: "member-attendance",
      headline: { "en-US": "Attendance & Check-In History" },
      subhead: { "en-US": "Interactive calendar with present, absent, and holiday logs plus monthly streak summary." },
    },
  ],
};

export default config;
