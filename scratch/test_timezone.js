const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function testTimezone() {
    // We can call process_qr_attendance or we can select from attendance_logs
    const url = `https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/attendance_logs?select=check_in&limit=1`;
    try {
        const res = await fetch(url, { headers });
        const data = await res.json();
        console.log("Raw check_in from database:", data[0]?.check_in);
        
        // Let's call a query block to format timezone
        // We don't have SQL execution endpoint directly, but we know raw is in ISO format with UTC suffix (+00:00).
    } catch (e) {
        console.error("Test failed:", e);
    }
}

testTimezone();
