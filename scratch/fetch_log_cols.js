const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const supabaseUrl = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function fetchLogCols() {
    try {
        const res = await fetch(`${supabaseUrl}/rest/v1/attendance_logs?limit=1`, {
            method: 'GET',
            headers
        });
        const data = await res.json();
        console.log("Single attendance log record data:", data);
        if (data && data.length > 0) {
            console.log("Columns returned:", Object.keys(data[0]));
        }
    } catch (e) {
        console.log("Error:", e);
    }
}

fetchLogCols();
