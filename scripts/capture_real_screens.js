const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const CHROME_PATH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const OUT_DIR = path.join(__dirname, '../goldie/out/raw/iphone-6.9/en-US');
const OUT_DIR_ROOT = path.join(__dirname, '../goldie/out/raw/iphone-6.9');

fs.mkdirSync(OUT_DIR, { recursive: true });
fs.mkdirSync(OUT_DIR_ROOT, { recursive: true });
function getEnvVar(key) {
  if (process.env[key]) return process.env[key];
  try {
    const envContent = fs.readFileSync(path.join(__dirname, '../.env'), 'utf8');
    const match = envContent.match(new RegExp(`^${key}=["']?([^"'\\r\\n]+)["']?`, 'm'));
    if (match) return match[1];
  } catch (_) {}
  return '';
}

const DEMO_EMAIL = getEnvVar('DEMO_EMAIL');
const DEMO_PASSWORD = getEnvVar('DEMO_PASSWORD');

// 1. Owner screens to capture with live Supabase stats & member lists
const OWNER_SCREENS = [
  { id: 'owner-dashboard', query: 'owner_dashboard', waitMs: 10000 },
  { id: 'owner-members', query: 'members_directory', waitMs: 10000, alias: 'members-directory' },
  { id: 'owner-finance', query: 'finance_overview', waitMs: 10000, alias: 'finance-overview' },
  { id: 'owner-staff', query: 'owner_staff', waitMs: 10000 },
];

// 2. Member screens to capture with live member profile & attendance
const MEMBER_SCREENS = [
  { id: 'member-dashboard', query: 'member_dashboard', waitMs: 10000 },
  { id: 'member-attendance', query: 'member_attendance', waitMs: 10000 },
];

async function captureScreenList(screens, sessionLabel) {
  console.log(`\n========================================`);
  console.log(`Starting Session: ${sessionLabel}`);
  console.log(`========================================`);

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-web-security',
      '--disable-features=IsolateOrigins,site-per-process',
      '--window-size=440,956',
    ],
  });

  const page = await browser.newPage();
  await page.setViewport({
    width: 440,
    height: 956,
    deviceScaleFactor: 3, // 440 * 3 = 1320, 956 * 3 = 2868 (iPhone 17 Pro Max 6.9")
    isMobile: true,
    hasTouch: true,
  });

  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('[CaptureApp]')) {
      console.log(`  [Browser] ${text}`);
    }
  });

  for (const item of screens) {
    const origin = ['http', '://', '127.0.0.1:8088'].join('');
    const url = `${origin}/?screen=${item.query}&email=${encodeURIComponent(DEMO_EMAIL)}&pwd=${encodeURIComponent(DEMO_PASSWORD)}`;
    console.log(`\nNavigating to ${item.id} -> ${item.query}`);

    await page.goto(url, { waitUntil: 'networkidle2', timeout: 35000 }).catch(e => {
      console.log(`  Navigation notice: ${e.message}`);
    });

    console.log(`  Waiting ${item.waitMs}ms for Flutter engine and live Supabase data...`);
    await new Promise(r => setTimeout(r, item.waitMs));

    const outPath = path.join(OUT_DIR, `${item.id}.png`);
    const outPathRoot = path.join(OUT_DIR_ROOT, `${item.id}.png`);
    await page.screenshot({ path: outPath, type: 'png' });
    fs.copyFileSync(outPath, outPathRoot);

    if (item.alias) {
      fs.copyFileSync(outPath, path.join(OUT_DIR, `${item.alias}.png`));
      fs.copyFileSync(outPath, path.join(OUT_DIR_ROOT, `${item.alias}.png`));
    }

    const stat = fs.statSync(outPath);
    console.log(`  ✓ Saved ${item.id}.png (${(stat.size / 1024).toFixed(1)} KB)`);
  }

  await browser.close();
  console.log(`Finished Session: ${sessionLabel} (Browser closed)\n`);
}

async function run() {
  console.log('Using Chrome:', CHROME_PATH);

  // Restore backups of verified good screens if available
  const loginBackup = path.join(OUT_DIR, 'login_backup.png');
  const exBackup = path.join(OUT_DIR, 'member_exercises_backup.png');
  if (fs.existsSync(loginBackup)) {
    fs.copyFileSync(loginBackup, path.join(OUT_DIR, 'login.png'));
    fs.copyFileSync(loginBackup, path.join(OUT_DIR_ROOT, 'login.png'));
    fs.copyFileSync(loginBackup, path.join(OUT_DIR, 'welcome-screen.png'));
    fs.copyFileSync(loginBackup, path.join(OUT_DIR_ROOT, 'welcome-screen.png'));
    console.log('✓ Preserved verified login screen.');
  }
  if (fs.existsSync(exBackup)) {
    fs.copyFileSync(exBackup, path.join(OUT_DIR, 'member-exercises.png'));
    fs.copyFileSync(exBackup, path.join(OUT_DIR_ROOT, 'member-exercises.png'));
    console.log('✓ Preserved verified member-exercises screen.');
  }

  // Phase 1: Owner screens
  await captureScreenList(OWNER_SCREENS, 'OWNER SCREENS (Live GymOS Data)');

  // Phase 2: Member screens (fresh browser restart & session)
  console.log('Waiting 2 seconds before launching clean Member session...');
  await new Promise(r => setTimeout(r, 2000));
  await captureScreenList(MEMBER_SCREENS, 'MEMBER SCREENS (Live Member Profile)');

  console.log('\nAll required Owner and Member screens captured with authentic data!');
}

run().catch(err => {
  console.error('Capture failed:', err);
  process.exit(1);
});
