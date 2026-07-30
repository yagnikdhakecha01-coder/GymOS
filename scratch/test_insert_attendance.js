const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json",
    "Prefer": "return=representation"
};

async function testAttendance() {
    const url = "https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/attendance";
    const payload = {
        gym_id: "148bd482-46c0-470d-9f14-76557c5ef670",
        user_id: "8381b385-5fc3-4f14-827e-ebd06515c16c",
        role: "staff",
        check_in: new Date().toISOString(),
        status: "Present"
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

testAttendance();
