const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function testRpc() {
    const url = "https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/rpc/get_staff_today_attendance_details_v2";
    const payload = {
        p_user_id: "53aaf2e6-df28-4313-aed5-be57a0f0dbae",
        p_gym_id: "f6468653-aab8-4f8b-ac79-d139313270bb"
    };

    try {
        const res = await fetch(url, {
            method: "POST",
            headers,
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        console.log("RPC Response:", JSON.stringify(data, null, 2));
    } catch (e) {
        console.error("RPC failed:", e);
    }
}

testRpc();
