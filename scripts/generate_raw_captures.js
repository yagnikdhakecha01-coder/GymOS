const fs = require('fs');
const path = require('path');
const { createCanvas } = require('/Users/jenishvora/.npm-global/lib/node_modules/goldie/node_modules/@napi-rs/canvas');

const WIDTH = 1320;
const HEIGHT = 2868;
const OUT_DIR = path.join(__dirname, '../goldie/out/raw/iphone-6.9/en-US');

fs.mkdirSync(OUT_DIR, { recursive: true });

function roundRect(ctx, x, y, width, height, radius, fill, stroke) {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + width - radius, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
  ctx.lineTo(x + width, y + height - radius);
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  ctx.lineTo(x + radius, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
  ctx.lineTo(x, y + radius);
  ctx.quadraticCurveTo(x, y, x + radius, y);
  ctx.closePath();
  if (fill) ctx.fill();
  if (stroke) ctx.stroke();
}

function drawIosStatusBar(ctx, darkContent = true) {
  ctx.save();
  ctx.fillStyle = darkContent ? '#0F172A' : '#FFFFFF';
  ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
  ctx.fillText('9:41', 110, 110);

  // Dynamic Island
  ctx.fillStyle = '#000000';
  roundRect(ctx, (WIDTH - 420) / 2, 45, 420, 110, 55, true, false);

  // Icons: Battery, Wifi, Cellular
  ctx.fillStyle = darkContent ? '#0F172A' : '#FFFFFF';
  roundRect(ctx, WIDTH - 180, 75, 75, 38, 12, false, true);
  roundRect(ctx, WIDTH - 174, 81, 55, 26, 8, true, false);
  ctx.fillRect(WIDTH - 102, 88, 6, 12);
  ctx.restore();
}

// 1. OWNER DASHBOARD
function renderOwnerDashboard() {
  const canvas = createCanvas(WIDTH, HEIGHT);
  const ctx = canvas.getContext('2d');

  // Background
  ctx.fillStyle = '#F8FAFC';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);

  drawIosStatusBar(ctx, true);

  // App Bar
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 160, WIDTH, 170);
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 58px -apple-system, system-ui, sans-serif';
  ctx.fillText('Power Fitness Gym', 80, 265);

  ctx.fillStyle = '#2563EB';
  ctx.font = '600 36px -apple-system, system-ui, sans-serif';
  ctx.fillText('OWNER PORTAL', 80, 310);

  // Notification Icon & Avatar
  ctx.fillStyle = '#EFF6FF';
  roundRect(ctx, WIDTH - 160, 205, 80, 80, 40, true, false);
  ctx.fillStyle = '#2563EB';
  ctx.font = 'bold 40px sans-serif';
  ctx.fillText('🔔', WIDTH - 144, 260);

  // Metrics Grid (2x2)
  const stats = [
    { label: 'Active Members', value: '248', sub: '+18 this month', color: '#2563EB', bg: '#EFF6FF' },
    { label: "Today's Attendance", value: '86', sub: 'Peak: 6:00 - 8:30 PM', color: '#10B981', bg: '#ECFDF5' },
    { label: 'Monthly Revenue', value: '₹3,45,000', sub: '92% target achieved', color: '#F59E0B', bg: '#FFFBEB' },
    { label: 'Expiring Soon', value: '12 Members', sub: 'Next 7 days', color: '#EF4444', bg: '#FEF2F2' }
  ];

  let startY = 380;
  for (let i = 0; i < 4; i++) {
    const s = stats[i];
    const col = i % 2;
    const row = Math.floor(i / 2);
    const cardX = 80 + col * (560 + 40);
    const cardY = startY + row * 280;

    ctx.fillStyle = '#FFFFFF';
    ctx.shadowColor = 'rgba(0,0,0,0.04)';
    ctx.shadowBlur = 24;
    ctx.shadowOffsetY = 8;
    roundRect(ctx, cardX, cardY, 560, 250, 28, true, false);
    ctx.shadowColor = 'transparent';

    ctx.fillStyle = s.bg;
    roundRect(ctx, cardX + 36, cardY + 36, 68, 68, 18, true, false);

    ctx.fillStyle = '#64748B';
    ctx.font = '500 32px -apple-system, system-ui, sans-serif';
    ctx.fillText(s.label, cardX + 36, cardY + 145);

    ctx.fillStyle = '#0F172A';
    ctx.font = 'bold 50px -apple-system, system-ui, sans-serif';
    ctx.fillText(s.value, cardX + 36, cardY + 200);

    ctx.fillStyle = s.color;
    ctx.font = '600 26px -apple-system, system-ui, sans-serif';
    ctx.fillText(s.sub, cardX + 36, cardY + 230);
  }

  // Quick Action Shortcuts
  const actionsY = 990;
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
  ctx.fillText('Quick Actions', 80, actionsY);

  const actions = ['+ Add Member', 'Mark Entry', 'Raise Bill', 'Shift Plan'];
  for (let i = 0; i < 4; i++) {
    const actX = 80 + i * (270 + 26);
    ctx.fillStyle = '#FFFFFF';
    roundRect(ctx, actX, actionsY + 30, 270, 110, 22, true, false);
    ctx.fillStyle = '#1E293B';
    ctx.font = '600 30px -apple-system, system-ui, sans-serif';
    ctx.fillText(actions[i], actX + 30, actionsY + 98);
  }

  // Live Attendance Stream
  const feedY = 1200;
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
  ctx.fillText('Live Attendance Stream', 80, feedY);

  ctx.fillStyle = '#2563EB';
  ctx.font = '600 32px -apple-system, system-ui, sans-serif';
  ctx.fillText('View All (86)', WIDTH - 270, feedY);

  const recent = [
    { name: 'Rahul Verma', time: 'Just now • QR Check-in', plan: 'Gold Annual', initial: 'R', color: '#2563EB' },
    { name: 'Pooja Patel', time: '4 mins ago • Fingerprint', plan: 'Quarterly PT', initial: 'P', color: '#10B981' },
    { name: 'Sameer Khan', time: '12 mins ago • QR Check-in', plan: 'Platinum Pass', initial: 'S', color: '#8B5CF6' },
    { name: 'Ananya Roy', time: '21 mins ago • Manual Entry', plan: 'Monthly Strength', initial: 'A', color: '#F59E0B' },
    { name: 'Kunal Singhal', time: '35 mins ago • QR Check-in', plan: 'Annual Pro', initial: 'K', color: '#EC4899' }
  ];

  for (let i = 0; i < recent.length; i++) {
    const r = recent[i];
    const rowY = feedY + 40 + i * 160;

    ctx.fillStyle = '#FFFFFF';
    roundRect(ctx, 80, rowY, WIDTH - 160, 140, 24, true, false);

    // Avatar
    ctx.fillStyle = r.color;
    roundRect(ctx, 115, rowY + 25, 90, 90, 45, true, false);
    ctx.fillStyle = '#FFFFFF';
    ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
    ctx.fillText(r.initial, 145, rowY + 86);

    ctx.fillStyle = '#0F172A';
    ctx.font = '600 38px -apple-system, system-ui, sans-serif';
    ctx.fillText(r.name, 235, rowY + 68);

    ctx.fillStyle = '#64748B';
    ctx.font = '400 30px -apple-system, system-ui, sans-serif';
    ctx.fillText(r.time, 235, rowY + 106);

    // Badge
    ctx.fillStyle = '#F1F5F9';
    roundRect(ctx, WIDTH - 380, rowY + 45, 260, 52, 26, true, false);
    ctx.fillStyle = '#334155';
    ctx.font = '600 26px -apple-system, system-ui, sans-serif';
    ctx.fillText(r.plan, WIDTH - 360, rowY + 81);
  }

  // Bottom Navigation Bar
  drawBottomNav(ctx, 0, ['Dashboard', 'Members', 'Finance', 'Staff', 'More']);

  return canvas.toBuffer('image/png');
}

// 2. MEMBER DASHBOARD
function renderMemberDashboard() {
  const canvas = createCanvas(WIDTH, HEIGHT);
  const ctx = canvas.getContext('2d');

  ctx.fillStyle = '#0B0F19';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);

  drawIosStatusBar(ctx, false);

  // Header
  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 56px -apple-system, system-ui, sans-serif';
  ctx.fillText('Hi, Alex Sharma 👋', 80, 260);

  ctx.fillStyle = '#94A3B8';
  ctx.font = '400 34px -apple-system, system-ui, sans-serif';
  ctx.fillText('Power Fitness Club • Member Pass', 80, 310);

  // Digital Pass & QR Card
  const qrY = 380;
  const qrGradient = ctx.createLinearGradient(80, qrY, WIDTH - 80, qrY + 680);
  qrGradient.addColorStop(0, '#1E3A8A');
  qrGradient.addColorStop(0.5, '#2563EB');
  qrGradient.addColorStop(1, '#1D4ED8');
  ctx.fillStyle = qrGradient;
  roundRect(ctx, 80, qrY, WIDTH - 160, 680, 36, true, false);

  // Card Content
  ctx.fillStyle = 'rgba(255,255,255,0.15)';
  roundRect(ctx, 120, qrY + 40, 240, 56, 28, true, false);
  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 28px -apple-system, system-ui, sans-serif';
  ctx.fillText('ANNUAL PRO', 150, qrY + 78);

  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 50px -apple-system, system-ui, sans-serif';
  ctx.fillText('Smart Access Pass', 120, qrY + 160);

  ctx.fillStyle = '#93C5FD';
  ctx.font = '400 32px -apple-system, system-ui, sans-serif';
  ctx.fillText('Valid until 31 Dec 2026 • Active', 120, qrY + 205);

  // QR Code Area
  ctx.fillStyle = '#FFFFFF';
  roundRect(ctx, (WIDTH - 360) / 2, qrY + 260, 360, 360, 28, true, false);
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 180px sans-serif';
  ctx.fillText('🔳', (WIDTH - 240) / 2, qrY + 510);

  // Streak & Fitness Stats Row
  const statsY = 1120;
  const metrics = [
    { title: 'Workout Streak', val: '14 Days 🔥', note: 'Best: 21 Days' },
    { title: 'Month Attendance', val: '22 / 26', note: '85% Consistency' },
    { title: 'Current Weight', val: '74.2 kg', note: '-2.8 kg target' }
  ];

  for (let i = 0; i < 3; i++) {
    const m = metrics[i];
    const mX = 80 + i * (365 + 32);
    ctx.fillStyle = '#1E293B';
    roundRect(ctx, mX, statsY, 365, 230, 28, true, false);

    ctx.fillStyle = '#94A3B8';
    ctx.font = '500 28px -apple-system, system-ui, sans-serif';
    ctx.fillText(m.title, mX + 32, statsY + 65);

    ctx.fillStyle = '#38BDF8';
    ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
    ctx.fillText(m.val, mX + 32, statsY + 130);

    ctx.fillStyle = '#64748B';
    ctx.font = '400 26px -apple-system, system-ui, sans-serif';
    ctx.fillText(m.note, mX + 32, statsY + 185);
  }

  // Today's Workout Routine Card
  const workoutY = 1410;
  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
  ctx.fillText("Today's Training Plan", 80, workoutY);

  ctx.fillStyle = '#1E293B';
  roundRect(ctx, 80, workoutY + 30, WIDTH - 160, 460, 32, true, false);

  ctx.fillStyle = '#10B981';
  roundRect(ctx, 120, workoutY + 70, 200, 50, 25, true, false);
  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 26px -apple-system, system-ui, sans-serif';
  ctx.fillText('DAY 3 OF 5', 150, workoutY + 105);

  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 48px -apple-system, system-ui, sans-serif';
  ctx.fillText('Chest & Triceps Hypertrophy', 120, workoutY + 180);

  ctx.fillStyle = '#94A3B8';
  ctx.font = '400 32px -apple-system, system-ui, sans-serif';
  ctx.fillText('5 Exercises • Estimated 55 mins • Coach Vikram', 120, workoutY + 230);

  const exercises = ['Barbell Bench Press (4x8)', 'Incline Dumbbell Fly (3x12)', 'Cable Pushdown (4x15)'];
  for (let i = 0; i < exercises.length; i++) {
    ctx.fillStyle = '#334155';
    roundRect(ctx, 120, workoutY + 280 + i * 55, WIDTH - 240, 45, 12, true, false);
    ctx.fillStyle = '#E2E8F0';
    ctx.font = '500 26px -apple-system, system-ui, sans-serif';
    ctx.fillText('✓  ' + exercises[i], 140, workoutY + 312 + i * 55);
  }

  // Bottom Navigation Bar
  drawBottomNav(ctx, 0, ['Home', 'Attendance', 'QR Scan', 'Badges', 'Profile'], true);

  return canvas.toBuffer('image/png');
}

// 3. STAFF / TRAINER DASHBOARD
function renderStaffDashboard() {
  const canvas = createCanvas(WIDTH, HEIGHT);
  const ctx = canvas.getContext('2d');

  ctx.fillStyle = '#F8FAFC';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);

  drawIosStatusBar(ctx, true);

  // App Bar
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 160, WIDTH, 170);
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 56px -apple-system, system-ui, sans-serif';
  ctx.fillText('Coach Vikram Singh', 80, 260);

  ctx.fillStyle = '#EA580C';
  ctx.font = '600 34px -apple-system, system-ui, sans-serif';
  ctx.fillText('SENIOR FITNESS TRAINER', 80, 310);

  // Shift & Punch Status Banner
  const shiftY = 380;
  ctx.fillStyle = '#FFF7ED';
  ctx.strokeStyle = '#FED7AA';
  ctx.lineWidth = 3;
  roundRect(ctx, 80, shiftY, WIDTH - 160, 160, 26, true, true);

  ctx.fillStyle = '#C2410C';
  ctx.font = 'bold 38px -apple-system, system-ui, sans-serif';
  ctx.fillText('● Shift Status: On Duty', 120, shiftY + 70);

  ctx.fillStyle = '#9A3412';
  ctx.font = '400 30px -apple-system, system-ui, sans-serif';
  ctx.fillText('Punched In at 08:00 AM • Morning Shift (08:00 - 16:00)', 120, shiftY + 118);

  // Stats Grid
  const ptStats = [
    { title: 'My PT Clients', val: '18', sub: '12 Active Today' },
    { title: 'Sessions Left', val: '4', sub: '2 Completed' },
    { title: 'This Month PT', val: '142', sub: '₹42,500 Accrued' }
  ];

  const gridY = 580;
  for (let i = 0; i < 3; i++) {
    const s = ptStats[i];
    const sX = 80 + i * (365 + 32);
    ctx.fillStyle = '#FFFFFF';
    ctx.shadowColor = 'rgba(0,0,0,0.04)';
    ctx.shadowBlur = 18;
    roundRect(ctx, sX, gridY, 365, 210, 24, true, false);
    ctx.shadowColor = 'transparent';

    ctx.fillStyle = '#64748B';
    ctx.font = '500 28px -apple-system, system-ui, sans-serif';
    ctx.fillText(s.title, sX + 32, gridY + 60);

    ctx.fillStyle = '#EA580C';
    ctx.font = 'bold 48px -apple-system, system-ui, sans-serif';
    ctx.fillText(s.val, sX + 32, gridY + 125);

    ctx.fillStyle = '#10B981';
    ctx.font = '600 26px -apple-system, system-ui, sans-serif';
    ctx.fillText(s.sub, sX + 32, gridY + 175);
  }

  // Today's PT Schedule
  const schedY = 850;
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
  ctx.fillText("Today's Client Schedule", 80, schedY);

  const clients = [
    { name: 'Karan Mehra', time: '09:00 AM', goal: 'Weight Loss • Session 14/30', status: 'Completed', color: '#10B981', bg: '#ECFDF5' },
    { name: 'Sneha Gupta', time: '10:30 AM', goal: 'Strength Training • Session 8/24', status: 'Completed', color: '#10B981', bg: '#ECFDF5' },
    { name: 'Rohan Joshi', time: '02:00 PM', goal: 'Cardio & Mobility • Session 5/12', status: 'Up Next', color: '#2563EB', bg: '#EFF6FF' },
    { name: 'Deepak Nayak', time: '04:30 PM', goal: 'Hypertrophy • Session 22/36', status: 'Scheduled', color: '#64748B', bg: '#F1F5F9' },
    { name: 'Vandana Rao', time: '06:00 PM', goal: 'Core & Posture • Session 10/20', status: 'Scheduled', color: '#64748B', bg: '#F1F5F9' }
  ];

  for (let i = 0; i < clients.length; i++) {
    const c = clients[i];
    const cY = schedY + 40 + i * 165;

    ctx.fillStyle = '#FFFFFF';
    roundRect(ctx, 80, cY, WIDTH - 160, 145, 24, true, false);

    // Time block
    ctx.fillStyle = '#F8FAFC';
    roundRect(ctx, 110, cY + 25, 140, 95, 18, true, false);
    ctx.fillStyle = '#0F172A';
    ctx.font = 'bold 30px -apple-system, system-ui, sans-serif';
    ctx.fillText(c.time.split(' ')[0], 130, cY + 70);
    ctx.fillStyle = '#64748B';
    ctx.font = '600 24px -apple-system, system-ui, sans-serif';
    ctx.fillText(c.time.split(' ')[1], 155, cY + 102);

    // Name & goal
    ctx.fillStyle = '#0F172A';
    ctx.font = 'bold 38px -apple-system, system-ui, sans-serif';
    ctx.fillText(c.name, 280, cY + 70);

    ctx.fillStyle = '#64748B';
    ctx.font = '400 30px -apple-system, system-ui, sans-serif';
    ctx.fillText(c.goal, 280, cY + 110);

    // Status badge
    ctx.fillStyle = c.bg;
    roundRect(ctx, WIDTH - 340, cY + 45, 220, 55, 28, true, false);
    ctx.fillStyle = c.color;
    ctx.font = 'bold 28px -apple-system, system-ui, sans-serif';
    ctx.fillText(c.status, WIDTH - 310, cY + 84);
  }

  // Bottom Navigation Bar
  drawBottomNav(ctx, 0, ['Dashboard', 'Clients', 'Attendance', 'Requests', 'Profile']);

  return canvas.toBuffer('image/png');
}

// 4. MEMBERS DIRECTORY
function renderMembersDirectory() {
  const canvas = createCanvas(WIDTH, HEIGHT);
  const ctx = canvas.getContext('2d');

  ctx.fillStyle = '#F8FAFC';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);

  drawIosStatusBar(ctx, true);

  // App Bar
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 160, WIDTH, 170);
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 56px -apple-system, system-ui, sans-serif';
  ctx.fillText('Members Directory', 80, 270);

  ctx.fillStyle = '#2563EB';
  roundRect(ctx, WIDTH - 270, 205, 190, 75, 22, true, false);
  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 30px -apple-system, system-ui, sans-serif';
  ctx.fillText('+ Add Member', WIDTH - 250, 253);

  // Search Bar
  const searchY = 370;
  ctx.fillStyle = '#FFFFFF';
  ctx.strokeStyle = '#E2E8F0';
  ctx.lineWidth = 2;
  roundRect(ctx, 80, searchY, WIDTH - 160, 95, 24, true, true);
  ctx.fillStyle = '#94A3B8';
  ctx.font = '400 32px -apple-system, system-ui, sans-serif';
  ctx.fillText('🔍  Search by name, phone or member ID...', 120, searchY + 60);

  // Filter Tabs
  const tabs = ['All (248)', 'Active (214)', 'Expiring (12)', 'Expired (22)'];
  const tabY = 500;
  for (let i = 0; i < 4; i++) {
    const tX = 80 + i * (270 + 26);
    const active = i === 0;
    ctx.fillStyle = active ? '#2563EB' : '#FFFFFF';
    roundRect(ctx, tX, tabY, 270, 75, 20, true, false);
    ctx.fillStyle = active ? '#FFFFFF' : '#64748B';
    ctx.font = '600 28px -apple-system, system-ui, sans-serif';
    ctx.fillText(tabs[i], tX + 40, tabY + 48);
  }

  // Member Rows
  const members = [
    { name: 'Aditya Kashyap', id: '#GYM-1042', plan: 'Platinum 12 Months', expiry: 'Expires 14 Nov 2026', status: 'ACTIVE', color: '#10B981', bg: '#ECFDF5' },
    { name: 'Meera Deshmukh', id: '#GYM-1043', plan: 'Gold 6 Months', expiry: 'Expires 28 Dec 2026', status: 'ACTIVE', color: '#10B981', bg: '#ECFDF5' },
    { name: 'Arjun Nambiar', id: '#GYM-1044', plan: 'Silver 3 Months', expiry: 'Expires in 4 days', status: 'RENEWAL DUE', color: '#EF4444', bg: '#FEF2F2' },
    { name: 'Tanvi Kapoor', id: '#GYM-1045', plan: 'Quarterly PT', expiry: 'Expires 18 Jan 2027', status: 'ACTIVE', color: '#10B981', bg: '#ECFDF5' },
    { name: 'Rishi Oberoi', id: '#GYM-1046', plan: 'Annual Strength', expiry: 'Expires 05 Feb 2027', status: 'ACTIVE', color: '#10B981', bg: '#ECFDF5' },
    { name: 'Divya Khurana', id: '#GYM-1047', plan: 'Monthly Pass', expiry: 'Expired 2 days ago', status: 'EXPIRED', color: '#64748B', bg: '#F1F5F9' }
  ];

  const listY = 620;
  for (let i = 0; i < members.length; i++) {
    const m = members[i];
    const mY = listY + i * 180;

    ctx.fillStyle = '#FFFFFF';
    roundRect(ctx, 80, mY, WIDTH - 160, 160, 24, true, false);

    // Initial Avatar
    ctx.fillStyle = '#EFF6FF';
    roundRect(ctx, 115, mY + 30, 100, 100, 50, true, false);
    ctx.fillStyle = '#2563EB';
    ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
    ctx.fillText(m.name[0], 148, mY + 96);

    ctx.fillStyle = '#0F172A';
    ctx.font = '600 38px -apple-system, system-ui, sans-serif';
    ctx.fillText(m.name, 245, mY + 75);

    ctx.fillStyle = '#64748B';
    ctx.font = '400 28px -apple-system, system-ui, sans-serif';
    ctx.fillText(`${m.id} • ${m.plan}`, 245, mY + 115);

    // Badge
    ctx.fillStyle = m.bg;
    roundRect(ctx, WIDTH - 350, mY + 50, 230, 55, 28, true, false);
    ctx.fillStyle = m.color;
    ctx.font = 'bold 26px -apple-system, system-ui, sans-serif';
    ctx.fillText(m.status, WIDTH - 325, mY + 88);
  }

  // Bottom Navigation Bar
  drawBottomNav(ctx, 1, ['Dashboard', 'Members', 'Finance', 'Staff', 'More']);

  return canvas.toBuffer('image/png');
}

// 5. FINANCE OVERVIEW
function renderFinanceOverview() {
  const canvas = createCanvas(WIDTH, HEIGHT);
  const ctx = canvas.getContext('2d');

  ctx.fillStyle = '#F8FAFC';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);

  drawIosStatusBar(ctx, true);

  // App Bar
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 160, WIDTH, 170);
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 56px -apple-system, system-ui, sans-serif';
  ctx.fillText('Finance & Ledgers', 80, 270);

  ctx.fillStyle = '#10B981';
  roundRect(ctx, WIDTH - 270, 205, 190, 75, 22, true, false);
  ctx.fillStyle = '#FFFFFF';
  ctx.font = 'bold 30px -apple-system, system-ui, sans-serif';
  ctx.fillText('+ Add Entry', WIDTH - 245, 253);

  // Big Revenue Hero Card
  const revY = 370;
  const revGradient = ctx.createLinearGradient(80, revY, WIDTH - 80, revY + 380);
  revGradient.addColorStop(0, '#0F172A');
  revGradient.addColorStop(1, '#1E293B');
  ctx.fillStyle = revGradient;
  roundRect(ctx, 80, revY, WIDTH - 160, 380, 32, true, false);

  ctx.fillStyle = '#94A3B8';
  ctx.font = '500 32px -apple-system, system-ui, sans-serif';
  ctx.fillText('OCTOBER 2026 NET CASH FLOW', 130, revY + 80);

  ctx.fillStyle = '#10B981';
  ctx.font = 'bold 74px -apple-system, system-ui, sans-serif';
  ctx.fillText('₹3,45,000', 130, revY + 180);

  ctx.fillStyle = '#F8FAFC';
  ctx.font = '400 30px -apple-system, system-ui, sans-serif';
  ctx.fillText('Collected this month from 184 memberships & PT', 130, revY + 235);

  // Dues & Advance pills
  ctx.fillStyle = 'rgba(239, 68, 68, 0.2)';
  roundRect(ctx, 130, revY + 280, 320, 55, 28, true, false);
  ctx.fillStyle = '#FCA5A5';
  ctx.font = '600 26px -apple-system, system-ui, sans-serif';
  ctx.fillText('Pending Dues: ₹28,500', 155, revY + 317);

  ctx.fillStyle = 'rgba(16, 185, 129, 0.2)';
  roundRect(ctx, 480, revY + 280, 340, 55, 28, true, false);
  ctx.fillStyle = '#86EFAC';
  ctx.font = '600 26px -apple-system, system-ui, sans-serif';
  ctx.fillText('Staff Accruals: ₹74,000', 505, revY + 317);

  // Payment Breakdown Channels
  const chY = 800;
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
  ctx.fillText('Payment Channels', 80, chY);

  const channels = [
    { name: 'UPI / QR', pct: '68%', amt: '₹2,34,600', color: '#2563EB' },
    { name: 'Cash', pct: '22%', amt: '₹75,900', color: '#10B981' },
    { name: 'Debit/Credit Card', pct: '10%', amt: '₹34,500', color: '#F59E0B' }
  ];

  for (let i = 0; i < 3; i++) {
    const ch = channels[i];
    const chX = 80 + i * (365 + 32);
    ctx.fillStyle = '#FFFFFF';
    roundRect(ctx, chX, chY + 30, 365, 175, 24, true, false);

    ctx.fillStyle = ch.color;
    roundRect(ctx, chX + 28, chY + 58, 24, 24, 6, true, false);

    ctx.fillStyle = '#64748B';
    ctx.font = '500 28px -apple-system, system-ui, sans-serif';
    ctx.fillText(ch.name, chX + 64, chY + 80);

    ctx.fillStyle = '#0F172A';
    ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
    ctx.fillText(ch.pct, chX + 28, chY + 140);

    ctx.fillStyle = '#94A3B8';
    ctx.font = '400 26px -apple-system, system-ui, sans-serif';
    ctx.fillText(ch.amt, chX + 28, chY + 180);
  }

  // Recent Transactions
  const txY = 1060;
  ctx.fillStyle = '#0F172A';
  ctx.font = 'bold 44px -apple-system, system-ui, sans-serif';
  ctx.fillText('Recent Transactions', 80, txY);

  const txs = [
    { title: 'Annual Pro Renewal • Alex Sharma', type: 'UPI Payment', amt: '+₹18,000', color: '#10B981' },
    { title: 'Personal Training 30 Sessions • Karan Mehra', type: 'Online Transfer', amt: '+₹25,000', color: '#10B981' },
    { title: 'New Member Admission • Pooja Patel', type: 'UPI Payment', amt: '+₹8,500', color: '#10B981' },
    { title: 'Equipment Maintenance Service', type: 'Vendor Expense', amt: '-₹6,200', color: '#EF4444' },
    { title: 'Quarterly Membership • Sameer Khan', type: 'Cash Counter', amt: '+₹7,000', color: '#10B981' }
  ];

  for (let i = 0; i < txs.length; i++) {
    const t = txs[i];
    const rowY = txY + 40 + i * 155;

    ctx.fillStyle = '#FFFFFF';
    roundRect(ctx, 80, rowY, WIDTH - 160, 135, 22, true, false);

    ctx.fillStyle = '#0F172A';
    ctx.font = '600 34px -apple-system, system-ui, sans-serif';
    ctx.fillText(t.title, 120, rowY + 62);

    ctx.fillStyle = '#64748B';
    ctx.font = '400 28px -apple-system, system-ui, sans-serif';
    ctx.fillText(t.type, 120, rowY + 104);

    ctx.fillStyle = t.color;
    ctx.font = 'bold 38px -apple-system, system-ui, sans-serif';
    ctx.fillText(t.amt, WIDTH - 340, rowY + 84);
  }

  // Bottom Navigation Bar
  drawBottomNav(ctx, 2, ['Dashboard', 'Members', 'Finance', 'Staff', 'More']);

  return canvas.toBuffer('image/png');
}

function drawBottomNav(ctx, activeIdx, labels, isDark = false) {
  const navY = HEIGHT - 220;
  ctx.fillStyle = isDark ? '#111827' : '#FFFFFF';
  ctx.shadowColor = 'rgba(0,0,0,0.06)';
  ctx.shadowBlur = 30;
  ctx.fillRect(0, navY, WIDTH, 220);
  ctx.shadowColor = 'transparent';

  const icons = ['🏠', '👥', '💳', '📋', '⚙️'];
  const tabWidth = WIDTH / labels.length;

  for (let i = 0; i < labels.length; i++) {
    const isAct = i === activeIdx;
    const tabX = i * tabWidth;

    ctx.fillStyle = isAct ? (isDark ? '#38BDF8' : '#2563EB') : '#94A3B8';
    ctx.font = '46px sans-serif';
    ctx.fillText(icons[i], tabX + tabWidth / 2 - 23, navY + 75);

    ctx.font = `${isAct ? 'bold' : '500'} 28px -apple-system, system-ui, sans-serif`;
    const tw = ctx.measureText(labels[i]).width;
    ctx.fillText(labels[i], tabX + (tabWidth - tw) / 2, navY + 125);
  }

  // Home Indicator Bar
  ctx.fillStyle = isDark ? '#475569' : '#CBD5E1';
  roundRect(ctx, (WIDTH - 420) / 2, HEIGHT - 45, 420, 14, 7, true, false);
}

// Generate all
console.log('Writing raw captures...');
fs.writeFileSync(path.join(OUT_DIR, 'owner-dashboard.png'), renderOwnerDashboard());
fs.writeFileSync(path.join(OUT_DIR, 'member-dashboard.png'), renderMemberDashboard());
fs.writeFileSync(path.join(OUT_DIR, 'staff-dashboard.png'), renderStaffDashboard());
fs.writeFileSync(path.join(OUT_DIR, 'members-directory.png'), renderMembersDirectory());
fs.writeFileSync(path.join(OUT_DIR, 'finance-overview.png'), renderFinanceOverview());

// Write raw manifest.json
const rawManifest = {
  screenshots: [
    { sceneId: 'owner-dashboard', file: path.join(OUT_DIR, 'owner-dashboard.png') },
    { sceneId: 'member-dashboard', file: path.join(OUT_DIR, 'member-dashboard.png') },
    { sceneId: 'staff-dashboard', file: path.join(OUT_DIR, 'staff-dashboard.png') },
    { sceneId: 'members-directory', file: path.join(OUT_DIR, 'members-directory.png') },
    { sceneId: 'finance-overview', file: path.join(OUT_DIR, 'finance-overview.png') }
  ]
};

fs.writeFileSync(path.join(OUT_DIR, '../manifest.json'), JSON.stringify(rawManifest, null, 2));
console.log('All 5 Gym OS raw screen captures generated successfully!');
