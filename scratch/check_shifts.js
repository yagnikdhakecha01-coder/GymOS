const urlShifts = "https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/gym_shifts";
const urlLogs = "https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/attendance_logs?order=check_in.desc&limit=5";
const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";

const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function inspect() {
    try {
        console.log("--- Fetching Gym Shifts ---");
        const r1 = await fetch(urlShifts, { headers });
        const shifts = await r1.json();
        console.log(JSON.stringify(shifts, null, 2));

        console.log("\n--- Fetching Recent Attendance Logs ---");
        const r2 = await fetch(urlLogs, { headers });
        const logs = await r2.json();
        console.log(JSON.stringify(logs, null, 2));
    } catch (err) {
        console.error("Error:", err);
    }
}

inspect();
