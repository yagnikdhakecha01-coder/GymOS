const APP_ROOT = process.cwd();

const config = {
  appRoot: APP_ROOT,
  appPath: `${APP_ROOT}/build/ios/iphonesimulator/Runner.app`,
  bundleId: "com.jenishvora.gymosv1",

  devices: ["iphone-6.9"],
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
    name: "Gym OS",
    subtitle: { "en-US": "Smart Gym & Fitness Management" },
    developer: "Gym OS Technologies",
    category: "Health & Fitness",
    rating: 4.9,
    ratingCount: "2.4K Ratings",
    ageRating: "4+",
    price: "Free",
    description: {
      "en-US": "Gym OS is the all-in-one operating system for gym owners, fitness trainers, and members. Streamline memberships, track daily attendance, manage staff, and automate financial reports with ease.",
    },
  },

  scenes: [
    {
      kind: "screenshot",
      id: "owner-dashboard",
      flow: "store-01-owner-dashboard",
      headline: { "en-US": "Owner Dashboard: Full Control" },
      subhead: { "en-US": "Live revenue, active member count, and daily attendance at a glance." },
      layout: "hero",
    },
    {
      kind: "screenshot",
      id: "member-dashboard",
      flow: "store-02-member-dashboard",
      headline: { "en-US": "Member Portal: Workout & QR Pass" },
      subhead: { "en-US": "Instant QR check-in, workout tracking, streaks, and plan details." },
      layout: "classic",
    },
    {
      kind: "screenshot",
      id: "staff-dashboard",
      flow: "store-03-staff-dashboard",
      headline: { "en-US": "Trainer & Staff Operations" },
      subhead: { "en-US": "Assign clients, track personal training sessions, and shift logs." },
      layout: "tilt",
    },
    {
      kind: "screenshot",
      id: "members-directory",
      flow: "store-04-members-directory",
      headline: { "en-US": "Comprehensive Member Management" },
      subhead: { "en-US": "Search profiles, manage subscriptions, and renewal reminders seamlessly." },
      layout: "offset",
    },
    {
      kind: "screenshot",
      id: "finance-overview",
      flow: "store-05-finance-overview",
      headline: { "en-US": "Automated Finance & Analytics" },
      subhead: { "en-US": "Track payments, pending dues, salary registers, and expense ledgers." },
      layout: "minimal",
    },
    {
      kind: "preview",
      id: "preview",
      segments: [
        { id: "owner", flow: "store-preview-01-owner" },
        { id: "member", flow: "store-preview-02-member" },
        { id: "staff", flow: "store-preview-03-staff", holdSeconds: 2 },
      ],
    },
  ],
};

export default config;
