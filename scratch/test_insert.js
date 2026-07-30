const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function testInsert() {
    const url = "https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/attendance_logs";
    const payload = {
        gym_id: "148bd482-46c0-470d-9f14-76557c5ef670",
        user_id: "8381b385-5fc3-4f14-827e-ebd06515c16c",
        date: "2026-07-27",
        check_in: new Date().toISOString(),
        status: "Present",
        method: "Static QR",
        dummy_col: 1
    };

    try {
        const res = await fetch(url, {
            method: "POST",
            headers,
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        console.log("Response:", JSON.stringify(data, null, 2));
    } catch (e) {
        console.error("Fetch failed:", e);
    }
}

testInsert();
