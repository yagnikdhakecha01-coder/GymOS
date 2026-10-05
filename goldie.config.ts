const APP_ROOT = "c:/Users/jigar/OneDrive/Documents/GYMOS V1 UI";

const config = {
  appRoot: APP_ROOT,
  appPath: "build/app/outputs/flutter-apk/app-release.apk",
  bundleId: "com.gymos.fitness.app.v1",
  android: {
    appPath: "build/app/outputs/flutter-apk/app-release.apk",
    applicationId: "com.gymos.fitness.app.v1",
  },
  devices: ["pixel-10-pro"],
  locales: ["en-US"],
  appearance: "dark",
  frame: { variant: "17-pro-blue" },
  theme: {
    background: "linear-gradient(160deg, #0B111E 0%, #151F32 55%, #0B111E 100%)",
    headlineColor: "#FFFFFF",
    subheadColor: "#94A3B8",
    fontFamily: 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
    copyHeightRatio: 0.22,
    deviceWidthRatio: 0.86,
    template: "uniform",
    layout: "classic",
  },
  store: {
    name: "Gym OS",
    subtitle: {
      "en-US": "Smart Gym Management & Client Portal",
    },
    developer: "Gym OS",
    category: "Health & Fitness",
    rating: 4.9,
    ratingCount: "1.2K",
    ageRating: "4+",
    price: "Free",
    description: {
      "en-US": "All-in-one gym management software for fitness clubs, trainers, and members.",
    },
  },
  scenes: [
    {
      kind: "screenshot",
      id: "login",
      flow: "store-01-login",
      headline: {
        "en-US": "Welcome to Gym OS",
      },
      subhead: {
        "en-US": "All-in-one Smart Gym Operating System",
      },
    },
    {
      kind: "screenshot",
      id: "dashboard",
      flow: "store-02-dashboard",
      headline: {
        "en-US": "Live Operations at a Glance",
      },
      subhead: {
        "en-US": "Real-time metrics, active members, and instant alerts",
      },
    },
    {
      kind: "screenshot",
      id: "members",
      flow: "store-03-members",
      headline: {
        "en-US": "Complete Client Management",
      },
      subhead: {
        "en-US": "Track memberships, renewals, and client statuses seamlessly",
      },
    },
    {
      kind: "screenshot",
      id: "member-details",
      flow: "store-04-member-details",
      headline: {
        "en-US": "Detailed Member Profiles",
      },
      subhead: {
        "en-US": "Full subscription history, quick actions, and personal records",
      },
    },
    {
      kind: "screenshot",
      id: "attendance",
      flow: "store-05-attendance",
      headline: {
        "en-US": "Smart Attendance Tracking",
      },
      subhead: {
        "en-US": "QR check-ins and live daily attendance for staff and members",
      },
    },
    {
      kind: "screenshot",
      id: "packages",
      flow: "store-06-packages",
      headline: {
        "en-US": "Flexible Membership Plans",
      },
      subhead: {
        "en-US": "Custom pricing, durations, PT inclusions, and diet perks",
      },
    },
    {
      kind: "screenshot",
      id: "staff",
      flow: "store-07-staff",
      headline: {
        "en-US": "Trainers & Staff Oversight",
      },
      subhead: {
        "en-US": "Manage personal trainers, roles, attendance, and payroll",
      },
    },
    {
      kind: "screenshot",
      id: "finance",
      flow: "store-08-finance",
      headline: {
        "en-US": "Financial Clarity & Profit",
      },
      subhead: {
        "en-US": "Track total revenue, cash flow trends, and net income",
      },
    },
    {
      kind: "screenshot",
      id: "payments",
      flow: "store-09-payments",
      headline: {
        "en-US": "Effortless Dues Collection",
      },
      subhead: {
        "en-US": "Track pending fees, overdue alerts, and instant payment logs",
      },
    },
    {
      kind: "screenshot",
      id: "expenses",
      flow: "store-10-expenses",
      headline: {
        "en-US": "Smart Expense Control",
      },
      subhead: {
        "en-US": "Categorize operational costs, salaries, rent, and maintenance",
      },
    },
    {
      kind: "screenshot",
      id: "reports",
      flow: "store-11-reports",
      headline: {
        "en-US": "In-Depth Business Analytics",
      },
      subhead: {
        "en-US": "Revenue growth, retention metrics, and attendance insights",
      },
    },
    {
      kind: "screenshot",
      id: "settings",
      flow: "store-12-settings",
      headline: {
        "en-US": "Security & Personalization",
      },
      subhead: {
        "en-US": "Biometric lock, custom branding, notifications, and cloud sync",
      },
    },
  ],
};

export default config;
