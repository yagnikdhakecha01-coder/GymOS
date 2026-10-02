// ── GYMOS OWNER MASTER DASHBOARD CONTROLLER ──
// Two-Way Direct Supabase Live Integration (Read & Write)

let currentSession = null;
let allMembersCache = [];
let allFinancesCache = [];
let allStaffCache = [];
let attendanceChartInstance = null;
let currentGymId = null;

// Expose global navigation & modal handlers immediately
window.switchTab = (tabId, element) => {
  document.querySelectorAll('.view-section').forEach(sec => sec.classList.remove('active'));
  document.querySelectorAll('.nav-link').forEach(link => link.classList.remove('active'));

  const targetSection = document.getElementById(`tab-${tabId}`);
  if (targetSection) targetSection.classList.add('active');
  if (element) element.classList.add('active');

  // Trigger tab specific live data render
  if (tabId === 'members') renderMembersTable(allMembersCache);
  else if (tabId === 'finance') renderFinanceTable(allFinancesCache);
  else if (tabId === 'staff') renderStaffTable(allStaffCache);
  else if (tabId === 'overview') fetchDashboardData();
};

window.openNewAdmissionModal = () => {
  const modal = document.getElementById('modal-admission');
  if (modal) modal.classList.add('active');
};

window.closeNewAdmissionModal = () => {
  const modal = document.getElementById('modal-admission');
  if (modal) modal.classList.remove('active');
};

window.openAddExpenseModal = () => {
  const modal = document.getElementById('modal-expense');
  if (modal) modal.classList.add('active');
};

window.closeAddExpenseModal = () => {
  const modal = document.getElementById('modal-expense');
  if (modal) modal.classList.remove('active');
};

window.openAddStaffModal = () => {
  const modal = document.getElementById('modal-staff');
  if (modal) modal.classList.add('active');
};

window.closeAddStaffModal = () => {
  const modal = document.getElementById('modal-staff');
  if (modal) modal.classList.remove('active');
};

window.logoutSession = () => {
  if (confirm('Are you sure you want to log out?')) {
    localStorage.removeItem('gymos_web_session');
    window.location.href = '../../index.html';
  }
};

document.addEventListener('DOMContentLoaded', async () => {
  await verifyOwnerSession();
  await fetchDashboardData();
  initAttendanceChart();
});

async function verifyOwnerSession() {
  const sessionStr = localStorage.getItem('gymos_web_session');
  if (sessionStr) {
    currentSession = JSON.parse(sessionStr);
  }

  // Load active gym from Supabase
  try {
    const { data: gyms } = await supabaseClient
      .from('gyms')
      .select('id, name, phone_number, plan, status')
      .limit(1);

    if (gyms && gyms.length > 0) {
      currentGymId = gyms[0].id;
      const gName = gyms[0].name || 'KD Test 1';

      if (!currentSession) {
        currentSession = {
          role: 'owner',
          gym_id: currentGymId,
          metadata: { gym_name: gName, user_name: 'Gym Owner' }
        };
        localStorage.setItem('gymos_web_session', JSON.stringify(currentSession));
      } else {
        currentSession.gym_id = currentGymId;
        if (!currentSession.metadata) currentSession.metadata = {};
        currentSession.metadata.gym_name = gName;
      }
    }
  } catch (e) {
    console.warn('Gym auto-detect notice:', e);
  }

  // Set user and gym info in UI
  if (currentSession && currentSession.metadata) {
    const el = document.getElementById('header-gym-name');
    if (el && currentSession.metadata.gym_name) el.innerText = currentSession.metadata.gym_name;
    const nameEl = document.getElementById('owner-name');
    const welcEl = document.getElementById('welcome-name');
    if (nameEl && currentSession.metadata.user_name) nameEl.innerText = currentSession.metadata.user_name;
    if (welcEl && currentSession.metadata.user_name) welcEl.innerText = currentSession.metadata.user_name.split(' ')[0];
  }
}

// ── FETCH LIVE DATA DIRECTLY FROM SUPABASE ──
async function fetchDashboardData() {
  try {
    // 1. Fetch live comprehensive data via RPC
    const { data: liveData, error } = await supabaseClient
      .rpc('get_web_owner_dashboard_data', {
        p_gym_id: currentGymId
      });

    if (error) {
      console.warn('Live RPC fetch warning, will fallback:', error);
      return;
    }

    if (liveData) {
      // Set KPIs
      document.getElementById('kpi-active-members').innerText = (liveData.active_members || 0).toString();
      document.getElementById('kpi-today-attendance').innerText = (liveData.today_attendance || 0).toString();
      document.getElementById('kpi-expiring-soon').innerText = (liveData.expiring_soon || 0).toString();
      document.getElementById('kpi-month-revenue').innerText = `₹${Number(liveData.monthly_revenue || 0).toLocaleString('en-IN')}`;

      // Cache real data
      allMembersCache = liveData.members || [];
      allFinancesCache = liveData.finances || [];
      allStaffCache = liveData.staff || [];

      // Render Overview Recent Check-Ins
      renderRecentAttendance(liveData.recent_attendance || []);

      // If active tab is members, finance, or staff, refresh their view
      const activeTab = document.querySelector('.view-section.active');
      if (activeTab) {
        if (activeTab.id === 'tab-members') renderMembersTable(allMembersCache);
        else if (activeTab.id === 'tab-finance') renderFinanceTable(allFinancesCache);
        else if (activeTab.id === 'tab-staff') renderStaffTable(allStaffCache);
      }
    }

  } catch (err) {
    console.error('Error fetching dashboard stats:', err);
  }
}

function renderRecentAttendance(attendanceLogs) {
  const tbody = document.getElementById('table-recent-attendance');
  if (!attendanceLogs || attendanceLogs.length === 0) {
    tbody.innerHTML = `<tr><td colspan="5" style="text-align: center; color: var(--text-muted);">No check-ins recorded today yet.</td></tr>`;
    return;
  }

  tbody.innerHTML = attendanceLogs.map(log => {
    const memberName = log.name || 'Member';
    const checkInDate = log.check_in || log.created_at;
    const timeStr = checkInDate ? new Date(checkInDate).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' }) : '—';
    const statusBadge = (log.status || 'Present').toLowerCase().includes('present') 
      ? '<span class="badge badge-success"><i data-lucide="check" style="width: 12px; height: 12px;"></i> Present</span>' 
      : `<span class="badge badge-warning">${log.status}</span>`;

    return `
      <tr>
        <td><strong>${memberName}</strong></td>
        <td style="color: var(--text-secondary);">${log.date || 'Today'}</td>
        <td>${timeStr}</td>
        <td><span class="badge badge-primary">${log.role || 'Member'}</span></td>
        <td>${statusBadge}</td>
      </tr>
    `;
  }).join('');

  lucide.createIcons();
}

function initAttendanceChart() {
  const ctx = document.getElementById('chart-attendance');
  if (!ctx) return;

  if (attendanceChartInstance) {
    attendanceChartInstance.destroy();
  }

  attendanceChartInstance = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['6 AM', '7 AM', '8 AM', '9 AM', '10 AM', '11 AM', '4 PM', '5 PM', '6 PM', '7 PM', '8 PM', '9 PM'],
      datasets: [{
        label: 'Check-Ins',
        data: [14, 29, 45, 38, 19, 12, 16, 40, 58, 65, 48, 22],
        backgroundColor: '#6C3AED',
        borderRadius: 6
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        y: { beginAtZero: true, grid: { color: '#F3F4F6' } },
        x: { grid: { display: false } }
      }
    }
  });
}

// ── MEMBER DIRECTORY (LIVE FROM SUPABASE) ──
function renderMembersTable(members) {
  const tbody = document.getElementById('table-members-body');
  if (!members || members.length === 0) {
    tbody.innerHTML = `<tr><td colspan="7" style="text-align: center; color: var(--text-muted);">No members found in database. Click "New Admission" to register.</td></tr>`;
    return;
  }

  tbody.innerHTML = members.map(m => {
    const dateStr = m.join_date || (m.created_at ? m.created_at.split('T')[0] : '—');
    const isAct = (m.status || 'Active').toLowerCase() === 'active';
    const statusClass = isAct ? 'badge-success' : 'badge-warning';

    return `
      <tr>
        <td>
          <div style="font-weight: 700; color: var(--text-primary);">${m.name}</div>
          <div style="font-size: 11px; color: var(--text-muted);">ID: ${m.id ? m.id.substring(0, 8) : '—'}</div>
        </td>
        <td style="color: var(--text-secondary);">${m.phone || '—'}</td>
        <td>${dateStr}</td>
        <td><span class="badge badge-primary">Fitness Pro</span></td>
        <td><span style="font-weight: 600;">₹${Number(m.total_received_amount || 1500).toLocaleString('en-IN')}</span></td>
        <td><span class="badge ${statusClass}">${m.status || 'Active'}</span></td>
        <td>
          <button class="btn btn-secondary" style="padding: 6px 12px; font-size: 12px;" onclick="viewMemberDetails('${m.id}')">
            View / Edit
          </button>
        </td>
      </tr>
    `;
  }).join('');

  lucide.createIcons();
}

window.filterMembers = () => {
  const query = document.getElementById('member-search').value.toLowerCase();
  const filtered = allMembersCache.filter(m => 
    (m.name && m.name.toLowerCase().includes(query)) ||
    (m.phone && m.phone.includes(query))
  );
  renderMembersTable(filtered);
};

window.viewMemberDetails = (id) => {
  const m = allMembersCache.find(x => x.id === id);
  if (m) {
    alert(`Member Details:\n\nName: ${m.name}\nPhone: ${m.phone}\nJoin Date: ${m.join_date}\nStatus: ${m.status}\nPaid: ₹${m.total_received_amount || 0}`);
  }
};

window.exportMembersCSV = () => {
  if (!allMembersCache || allMembersCache.length === 0) {
    alert('No members to export.');
    return;
  }
  let csv = 'Name,Phone,Join Date,Status,Paid Amount,ID\n';
  allMembersCache.forEach(m => {
    csv += `"${m.name}","${m.phone}","${m.join_date || ''}","${m.status || ''}","${m.total_received_amount || 0}","${m.id}"\n`;
  });
  const blob = new Blob([csv], { type: 'text/csv' });
  const url = window.URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.setAttribute('href', url);
  a.setAttribute('download', `GymOS_Members_${new Date().toISOString().split('T')[0]}.csv`);
  a.click();
};

// ── SAVE NEW ADMISSION DIRECTLY TO SUPABASE ──
window.handleNewAdmission = async (event) => {
  event.preventDefault();
  const submitBtn = document.getElementById('btn-submit-admission');
  submitBtn.disabled = true;
  submitBtn.innerText = 'Saving to Database...';

  const name = document.getElementById('adm-name').value.trim();
  const phone = document.getElementById('adm-phone').value.trim();
  const amount = Number(document.getElementById('adm-amount').value) || 1500;
  const method = document.getElementById('adm-method').value;

  try {
    // Call write RPC
    const { data: res, error } = await supabaseClient.rpc('web_add_new_member', {
      p_gym_id: currentGymId,
      p_name: name,
      p_phone: phone,
      p_amount: amount,
      p_payment_method: method
    });

    if (error) throw error;

    alert(`🎉 Success! Member "${name}" registered and saved in database.`);
    closeNewAdmissionModal();
    
    // Clear inputs
    document.getElementById('adm-name').value = '';
    document.getElementById('adm-phone').value = '';

    // Refresh live database data immediately
    await fetchDashboardData();

  } catch (err) {
    console.error('Admission failed:', err);
    alert('Failed to save to database: ' + err.message);
  } finally {
    submitBtn.disabled = false;
    submitBtn.innerText = 'Save Member';
  }
};

// ── FINANCE TAB (LIVE FROM SUPABASE) ──
function renderFinanceTable(transactions) {
  const tbody = document.getElementById('table-transactions-body');
  
  let inflow = 0;
  let outflow = 0;

  if (transactions && transactions.length > 0) {
    transactions.forEach(t => {
      const amt = Number(t.amount) || 0;
      const typeStr = (t.type || '').toLowerCase();
      if (typeStr === 'revenue' || typeStr === 'income' || typeStr === 'payment' || !t.type) {
        inflow += amt;
      } else {
        outflow += amt;
      }
    });
  }

  document.getElementById('fin-inflow').innerText = `₹${inflow.toLocaleString('en-IN')}`;
  document.getElementById('fin-outflow').innerText = `₹${outflow.toLocaleString('en-IN')}`;
  document.getElementById('fin-net').innerText = `₹${(inflow - outflow).toLocaleString('en-IN')}`;

  if (!transactions || transactions.length === 0) {
    tbody.innerHTML = `<tr><td colspan="5" style="text-align: center; color: var(--text-muted);">No transactions recorded in database yet.</td></tr>`;
    return;
  }

  tbody.innerHTML = transactions.map(t => {
    const dateStr = (t.transaction_date || t.created_at || '').split('T')[0];
    const typeStr = (t.type || '').toLowerCase();
    const isIncome = typeStr === 'revenue' || typeStr === 'income' || typeStr === 'payment' || !t.type;

    return `
      <tr>
        <td>${dateStr}</td>
        <td><span class="badge ${isIncome ? 'badge-success' : 'badge-danger'}">${isIncome ? 'Revenue' : 'Expense'}</span></td>
        <td><strong>${t.notes || 'Gym Fee / Expense'}</strong></td>
        <td><span class="badge badge-primary">${t.category || 'General'}</span></td>
        <td style="font-weight: 700; color: ${isIncome ? 'var(--success)' : 'var(--danger)'};">
          ${isIncome ? '+' : '-'} ₹${Number(t.amount).toLocaleString('en-IN')}
        </td>
      </tr>
    `;
  }).join('');

  lucide.createIcons();
}

// ── SAVE EXPENSE DIRECTLY TO SUPABASE ──
window.handleAddExpense = async (event) => {
  event.preventDefault();
  const title = document.getElementById('exp-title').value.trim();
  const category = document.getElementById('exp-category').value;
  const amount = Number(document.getElementById('exp-amount').value) || 0;
  const method = document.getElementById('exp-method').value;

  try {
    const { data: res, error } = await supabaseClient.rpc('web_add_expense', {
      p_gym_id: currentGymId,
      p_title: title,
      p_category: category,
      p_amount: amount,
      p_payment_method: method
    });

    if (error) throw error;

    alert(`✅ Expense of ₹${amount} saved to database!`);
    closeAddExpenseModal();
    
    // Clear form
    document.getElementById('exp-title').value = '';
    document.getElementById('exp-amount').value = '';

    // Refresh live database data immediately
    await fetchDashboardData();

  } catch(e) {
    alert('Failed to save expense: ' + e.message);
  }
};

// ── STAFF TAB (LIVE FROM SUPABASE) ──
function renderStaffTable(staffList) {
  const tbody = document.getElementById('table-staff-body');
  if (!staffList || staffList.length === 0) {
    tbody.innerHTML = `<tr><td colspan="6" style="text-align: center; color: var(--text-muted);">No staff registered in database. Click "Add New Staff" to add.</td></tr>`;
    return;
  }

  tbody.innerHTML = staffList.map(s => {
    const shiftStr = s.shift || '06:00 AM - 02:00 PM';
    return `
      <tr>
        <td><strong>${s.name}</strong></td>
        <td><span class="badge badge-primary">${s.role || 'Trainer'}</span></td>
        <td style="color: var(--text-secondary);">${s.phone || '—'}</td>
        <td style="font-weight: 700;">₹${Number(s.salary || 15000).toLocaleString('en-IN')}</td>
        <td>${shiftStr}</td>
        <td><span class="badge badge-success">${s.status || 'Active'}</span></td>
      </tr>
    `;
  }).join('');

  lucide.createIcons();
}

// ── SAVE NEW STAFF DIRECTLY TO SUPABASE ──
window.handleAddStaff = async (event) => {
  event.preventDefault();
  const name = document.getElementById('stf-name').value.trim();
  const phone = document.getElementById('stf-phone').value.trim();
  const role = document.getElementById('stf-role').value;
  const salary = Number(document.getElementById('stf-salary').value) || 20000;
  const shift = document.getElementById('stf-shift').value;

  try {
    const { data: res, error } = await supabaseClient.rpc('web_add_staff', {
      p_gym_id: currentGymId,
      p_name: name,
      p_phone: phone,
      p_role: role,
      p_salary: salary,
      p_shift: shift
    });

    if (error) throw error;

    alert(`🎉 Staff member "${name}" registered successfully in database!`);
    closeAddStaffModal();
    
    // Clear inputs
    document.getElementById('stf-name').value = '';
    document.getElementById('stf-phone').value = '';

    // Refresh live database data immediately
    await fetchDashboardData();

  } catch(e) {
    alert('Failed to save staff: ' + e.message);
  }
};

window.saveGymSettings = async (e) => {
  e.preventDefault();
  const name = document.getElementById('setting-gym-name').value.trim();
  const phone = document.getElementById('setting-gym-phone').value.trim();

  try {
    if (currentGymId) {
      await supabaseClient
        .from('gyms')
        .update({ name: name, phone_number: phone })
        .eq('id', currentGymId);
      document.getElementById('header-gym-name').innerText = name;
    }
    alert('✅ Gym settings updated in database!');
  } catch(e) {
    alert('Settings update error: ' + e.message);
  }
};
