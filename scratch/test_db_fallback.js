const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function testFallback() {
    const finalGymId = "f6468653-aab8-4f8b-ac79-d139313270bb";
    const finalUserId = "53aaf2e6-df28-4313-aed5-be57a0f0dbae";

    const url = `https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/attendance_logs?gym_id=eq.${finalGymId}&check_out=is.null&order=check_in.desc&limit=10`;
    try {
        const res = await fetch(url, { headers });
        const allOpenLogs = await res.json();
        console.log("All Open Logs Count:", allOpenLogs.length);

        const matchingLog = allOpenLogs.where ? allOpenLogs.where(l => l.user_id === finalUserId) : allOpenLogs.filter(l => l.user_id === finalUserId);
        console.log("Matching Log Count:", matchingLog.length);
        if (matchingLog.length > 0) {
            console.log("Matching log found! Would perform CHECK OUT. ID:", matchingLog[0].id);
        } else {
            console.log("No matching log. Would perform CHECK IN.");
        }
    } catch (e) {
        console.error("Fallback query failed:", e);
    }
}

testFallback();
