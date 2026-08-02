const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function queryAlerts() {
    const url = "https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/attendance_alerts?select=*&order=created_at.desc&limit=10";
    try {
        const res = await fetch(url, { headers });
        const data = await res.json();
        console.log("Alerts:", JSON.stringify(data, null, 2));
    } catch (e) {
        console.error("Fetch failed:", e);
    }
}

queryAlerts();
