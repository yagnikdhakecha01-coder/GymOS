const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

const cols = [
    'id', 'gym_id', 'user_id', 'role', 'user_type', 'member_id', 'staff_id', 'shift_id',
    'date', 'check_in', 'check_out', 'method', 'status', 'shift_status', 'working_minutes',
    'late_minutes', 'early_exit_minutes', 'overtime_minutes', 'qr_type', 'qr_token_id',
    'rule_version', 'created_at', 'updated_at', 'name', 'gym_name'
];

async function checkCol(col) {
    const url = `https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/attendance_logs?select=${col}&limit=0`;
    try {
        const res = await fetch(url, { headers });
        const text = await res.text();
        if (res.status === 200) {
            return { col, exists: true };
        } else {
            return { col, exists: false, error: text };
        }
    } catch (e) {
        return { col, exists: false, error: e.message };
    }
}

async function run() {
    const results = [];
    for (const col of cols) {
        results.push(await checkCol(col));
    }
    console.log("Column verification results:");
    results.forEach(r => {
        if (r.exists) {
            console.log(`[EXISTING] ${r.col}`);
        } else {
            console.log(`[MISSING]  ${r.col} - ${r.error}`);
        }
    });
}

run();
